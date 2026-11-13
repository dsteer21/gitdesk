import AppKit
import Foundation
import Observation

/// App-wide state: the repository list, which one is open, and the sheets/palette.
@MainActor @Observable
final class RepoStore {
    var repos: [Repo] = []
    var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedRepo")
            if let repo = selected { Task { await repo.refresh() } }
        }
    }

    var showPalette = false
    var showClone = false
    /// ⌘P → "Commit & Push…": asks for the message, then commits and pushes the open repo.
    var showCommitPrompt = false
    var showNewBranch = false {
        didSet { if !showNewBranch { newBranchStartPoint = nil } }
    }
    /// Commit or branch the next new branch starts from (nil = HEAD).
    var newBranchStartPoint: String?
    var scanCandidates: [URL]?
    var bulkOperation: String?

    var selected: Repo? { repos.first { $0.id == selectedID } }

    private struct StoredRepo: Codable {
        let id: UUID
        let path: String
        let name: String
    }

    private static var storageURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("repositories.json")
    }

    init() {
        load()
        Task {
            await refreshAllStatuses()
            if let repo = selected { await repo.refreshDetail() }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let stored = try? JSONDecoder().decode([StoredRepo].self, from: data) else { return }
        repos = stored.map { Repo(id: $0.id, url: URL(fileURLWithPath: $0.path), name: $0.name) }
        sortRepos()
        if let saved = UserDefaults.standard.string(forKey: "selectedRepo"),
           let id = UUID(uuidString: saved), repos.contains(where: { $0.id == id }) {
            selectedID = id
        }
    }

    private func save() {
        let stored = repos.map { StoredRepo(id: $0.id, path: $0.url.path, name: $0.name) }
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: Self.storageURL, options: .atomic)
        }
    }

    private func sortRepos() {
        repos.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Adding and removing

    @discardableResult
    func addRepository(at url: URL, select: Bool = true) async -> Repo? {
        do {
            let top = try await Git.run(["rev-parse", "--show-toplevel"], in: url).stdout.trimmed
            let root = URL(fileURLWithPath: top).standardizedFileURL
            if let existing = repos.first(where: { $0.url.standardizedFileURL == root }) {
                if select { selectedID = existing.id }
                return existing
            }
            let repo = Repo(url: root)
            repos.append(repo)
            sortRepos()
            save()
            await repo.refreshStatus()
            if select { selectedID = repo.id }
            return repo
        } catch {
            Banner.shared.error("\(url.lastPathComponent) is not a Git repository")
            return nil
        }
    }

    func remove(_ repo: Repo) {
        repos.removeAll { $0.id == repo.id }
        if selectedID == repo.id { selectedID = nil }
        save()
    }

    func promptAddRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose one or more Git repositories"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            for (index, url) in urls.enumerated() {
                await addRepository(at: url, select: index == urls.count - 1)
            }
        }
    }

    func promptScanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to search for Git repositories"
        guard panel.runModal() == .OK, let root = panel.url else { return }
        Task {
            bulkOperation = "Scanning \(root.lastPathComponent)…"
            let known = Set(repos.map { $0.url.standardizedFileURL.path })
            let found = await Task.detached { Self.findRepositories(in: root) }.value
            bulkOperation = nil
            let candidates = found.filter { !known.contains($0.standardizedFileURL.path) }
            if candidates.isEmpty {
                Banner.shared.info(found.isEmpty ? "No repositories found in \(root.lastPathComponent)" : "All repositories found are already added")
            } else {
                scanCandidates = candidates
            }
        }
    }

    func addScanned(_ urls: [URL]) async {
        for url in urls { await addRepository(at: url, select: false) }
        Banner.shared.info("Added \(urls.count) repositor\(urls.count == 1 ? "y" : "ies")")
    }

    /// Walks `root` looking for working copies, without descending into repos or dependency folders.
    nonisolated static func findRepositories(in root: URL, maxDepth: Int = 5) -> [URL] {
        let skip: Set<String> = ["node_modules", "vendor", "Pods", ".build", "build", "dist", "Library"]
        var found: [URL] = []
        let fm = FileManager.default

        func visit(_ directory: URL, depth: Int) {
            if fm.fileExists(atPath: directory.appendingPathComponent(".git").path) {
                found.append(directory)
                return
            }
            guard depth < maxDepth,
                  let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true, !skip.contains(child.lastPathComponent) else { continue }
                visit(child, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func clone(_ remote: String, into parent: URL, name: String) async throws {
        let destination = parent.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitError(message: "\(destination.path) already exists.")
        }
        try await Git.run(["clone", "--", remote, destination.path], in: parent)
        await addRepository(at: destination)
        Banner.shared.info("Cloned \(name)")
    }

    // MARK: - Bulk operations

    func refreshAllStatuses() async {
        await forEachRepo(repos) { await $0.refreshStatus() }
    }

    func pullAll() async {
        guard bulkOperation == nil else { return }
        bulkOperation = "Pulling all repositories…"
        await forEachRepo(repos) { await $0.pullForBulk() }
        bulkOperation = nil
        Banner.shared.info(summary(verb: "Pull all"))
    }

    func fetchAll() async {
        guard bulkOperation == nil else { return }
        bulkOperation = "Fetching all repositories…"
        await forEachRepo(repos) { await $0.fetchForBulk() }
        bulkOperation = nil
        Banner.shared.info(summary(verb: "Fetch all"))
    }

    private func summary(verb: String) -> String {
        let outcomes = repos.compactMap(\.lastOutcome)
        let updated = outcomes.filter { $0.kind == .updated }.count
        let failed = outcomes.filter { $0.kind == .failed }.count
        let current = outcomes.filter { $0.kind == .upToDate }.count
        return "\(verb): \(updated) updated, \(current) up to date" + (failed > 0 ? ", \(failed) need attention" : "")
    }

    /// Runs `operation` on each repo, a few at a time.
    private func forEachRepo(_ items: [Repo], concurrency: Int = 4, _ operation: @escaping @Sendable @MainActor (Repo) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<concurrency {
                guard let repo = iterator.next() else { break }
                group.addTask { await operation(repo) }
            }
            while await group.next() != nil {
                if let repo = iterator.next() { group.addTask { await operation(repo) } }
            }
        }
    }

    // MARK: - Shell helpers

    func revealInFinder(_ repo: Repo) {
        NSWorkspace.shared.activateFileViewerSelecting([repo.url])
    }

    func openInTerminal(_ repo: Repo) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([repo.url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Command palette

    struct PaletteItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let action: @MainActor () -> Void
    }

    func paletteItems() -> [PaletteItem] {
        var items: [PaletteItem] = []
        func add(_ title: String, _ subtitle: String = "", _ icon: String, _ action: @escaping @MainActor () -> Void) {
            items.append(PaletteItem(title: title, subtitle: subtitle, icon: icon, action: action))
        }

        if let repo = selected {
            let name = repo.name
            if repo.changeCount > 0 {
                add("Commit & Push…", name, "arrow.up.circle") { [weak self] in self?.showCommitPrompt = true }
            }
            add("Pull", name, "arrow.down.to.line") { Task { await repo.pull() } }
            add("Push", name, "arrow.up.to.line") { Task { await repo.push() } }
            add("Force Push (with lease)", name, "exclamationmark.arrow.triangle.2.circlepath") { Task { await repo.push(force: true) } }
            add("Fetch", name, "arrow.triangle.2.circlepath") { Task { await repo.fetch() } }
            for mode in PullMode.allCases {
                add("Pull: \(mode.title)", name, "arrow.down.to.line") { Task { await repo.pull(mode) } }
            }
            add("Stage All Changes", name, "plus.circle") { Task { await repo.stageAll() } }
            add("Unstage All Changes", name, "minus.circle") { Task { await repo.unstageAll() } }
            add("Use Last Commit Message", name, "arrow.uturn.backward") { [weak repo] in
                guard let repo, let message = repo.lastCommitMessage else { return }
                repo.select(.wip)
                repo.useMessage(message)
            }
            add("Amend Previous Commit (squash)", name, "arrow.triangle.merge") { [weak repo] in
                guard let repo else { return }
                repo.select(.wip)
                repo.amend = true
                if repo.draftSummary.isEmpty, let message = repo.lastCommitMessage { repo.useMessage(message) }
            }
            add("Squash Last Commit into Previous", name, "rectangle.compress.vertical") { Task { await repo.squashLastTwo() } }
            add("Stash Changes", name, "tray.and.arrow.down") { Task { await repo.stash() } }
            add("Pop Stash", name, "tray.and.arrow.up") { Task { await repo.popStash() } }
            add("Create Branch…", name, "arrow.triangle.branch") { [weak self] in self?.showNewBranch = true }
            add("Refresh", name, "arrow.clockwise") { Task { await repo.refresh() } }
            add("Reveal in Finder", name, "folder") { [weak self] in self?.revealInFinder(repo) }
            add("Open in Terminal", name, "terminal") { [weak self] in self?.openInTerminal(repo) }

            for branch in repo.localBranches where !branch.isHead {
                add("Checkout \(branch.name)", "Local branch", "arrow.triangle.branch") { Task { await repo.checkout(branch) } }
            }
            for branch in repo.remoteBranches {
                add("Checkout \(branch.name)", "Remote branch", "cloud") { Task { await repo.checkout(branch) } }
            }
        }

        add("Pull All Repositories", "\(repos.count) repositories", "square.stack.3d.down.right") { [weak self] in
            Task { await self?.pullAll() }
        }
        add("Fetch All Repositories", "\(repos.count) repositories", "arrow.triangle.2.circlepath.circle") { [weak self] in
            Task { await self?.fetchAll() }
        }
        add("Clone Repository…", "", "square.and.arrow.down") { [weak self] in self?.showClone = true }
        add("Add Repository…", "", "plus.rectangle.on.folder") { [weak self] in self?.promptAddRepository() }
        add("Scan Folder for Repositories…", "", "magnifyingglass") { [weak self] in self?.promptScanFolder() }
        add("All Repositories", "Overview", "list.bullet.rectangle") { [weak self] in self?.selectedID = nil }

        for repo in repos {
            add("Open \(repo.name)", repo.url.path, "folder.badge.gearshape") { [weak self] in self?.selectedID = repo.id }
        }
        return items
    }
}
