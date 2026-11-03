import Foundation
import Observation

/// One repository in the list: its summary status, loaded graph/refs, and
/// the per-repo UI state (selection, diff, commit draft).
@MainActor @Observable
final class Repo: Identifiable {
    let id: UUID
    let url: URL
    var name: String

    // MARK: Summary (always kept fresh, shown in the repo list)
    var branch = ""
    var upstream: String?
    var ahead = 0
    var behind = 0
    var hasCommits = true
    var staged: [FileChange] = []
    var unstaged: [FileChange] = []
    var exists = true
    var busy: String?
    var lastOutcome: Outcome?

    // MARK: Detail (loaded when the repo is opened)
    var entries: [GraphEntry] = []
    var maxLanes = 1
    var localBranches: [Branch] = []
    var remoteBranches: [Branch] = []
    var tags: [String] = []
    var stashes: [Stash] = []
    var detailLoaded = false

    // MARK: UI state
    var selection: GraphSelection = .wip
    var commitDetail: CommitDetail?
    var diff: DiffState?

    // MARK: Commit draft
    var draftSummary = ""
    var draftBody = ""
    var amend = false
    /// True when HEAD is already on the upstream branch (so amending it will need a force push).
    var headIsPushed = false
    /// Set after amending/squashing a pushed commit: the next Push uses --force-with-lease.
    var pendingForcePush = false
    var lastCommitMessage: String?

    static let logLimit = 600

    init(id: UUID = UUID(), url: URL, name: String? = nil) {
        self.id = id
        self.url = url
        self.name = name ?? url.lastPathComponent
    }

    var changeCount: Int { Set(staged.map(\.path)).union(unstaged.map(\.path)).count }
    var headCommit: Commit? { entries.first { $0.commit.isHead }?.commit }

    @discardableResult
    private func git(_ args: [String], ok: Set<Int32> = [0]) async throws -> String {
        try await Git.run(args, in: url, ok: ok).stdout
    }

    // MARK: - Refreshing

    func refreshStatus() async {
        exists = FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
        guard exists else { return }
        do {
            let output = try await git(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"])
            let s = GitParse.status(output)
            branch = s.branch
            upstream = s.upstream
            ahead = s.ahead
            behind = s.behind
            hasCommits = s.hasCommits
            staged = s.staged
            unstaged = s.unstaged

            if hasCommits {
                lastCommitMessage = try? await git(["log", "-1", "--format=%B"]).trimmed
            } else {
                lastCommitMessage = nil
            }
            if upstream != nil && hasCommits {
                let result = try? await Git.run(["merge-base", "--is-ancestor", "HEAD", "@{u}"], in: url, ok: [0, 1])
                headIsPushed = result?.status == 0
            } else {
                headIsPushed = false
            }
        } catch {
            Banner.shared.error("\(name): couldn't read status", detail: error.localizedDescription)
        }
    }

    func refreshDetail() async {
        guard exists else { return }
        do {
            var commits: [Commit] = []
            if hasCommits {
                let log = try await git(["log", "--branches", "--remotes", "--tags", "HEAD", "--date-order",
                                         "--decorate=full", "-n", "\(Self.logLimit)", "--format=\(GitParse.logFormat)"])
                commits = GitParse.commits(log)
            }
            let graph = CommitGraph.build(commits)
            entries = zip(commits, graph.rows).map { GraphEntry(commit: $0, row: $1) }
            maxLanes = graph.maxLanes

            let refs = GitParse.branches(try await git(["for-each-ref", "--sort=refname", "--format=\(GitParse.refFormat)",
                                                        "refs/heads", "refs/remotes", "refs/tags"]))
            localBranches = refs.local
            remoteBranches = refs.remote
            tags = refs.tags.reversed()
            stashes = GitParse.stashes(try await git(["stash", "list", "--format=%gd%x1f%s"]))
            detailLoaded = true

            // Keep the selection valid after history changes.
            if case .commit(let hash) = selection, !entries.contains(where: { $0.id == hash }) {
                select(.wip)
            }
        } catch {
            Banner.shared.error("\(name): couldn't load history", detail: error.localizedDescription)
        }
    }

    func refresh() async {
        await refreshStatus()
        await refreshDetail()
    }

    /// Runs a user-initiated operation: marks the repo busy, reports errors, then refreshes.
    @discardableResult
    private func perform(_ label: String, fullRefresh: Bool = true, _ work: () async throws -> String?) async -> Bool {
        busy = label
        defer { busy = nil }
        var success = true
        do {
            if let message = try await work() { Banner.shared.info(message) }
        } catch {
            Banner.shared.error("\(name): \(label) failed", detail: error.localizedDescription)
            success = false
        }
        if fullRefresh { await refresh() } else { await refreshStatus() }
        return success
    }

    // MARK: - Selection & diffs

    func select(_ newSelection: GraphSelection) {
        selection = newSelection
        diff = nil
        commitDetail = nil
        if case .commit(let hash) = newSelection {
            Task { await loadCommitDetail(hash) }
        }
    }

    private func loadCommitDetail(_ hash: String) async {
        guard let commit = entries.first(where: { $0.id == hash })?.commit else { return }
        do {
            let message = try await git(["show", "-s", "--format=%B", hash]).trimmed
            let files: [FileChange]
            if let parent = commit.parents.first {
                files = GitParse.nameStatus(try await git(["diff", "--name-status", "-z", "-M", parent, hash]))
            } else {
                files = GitParse.nameStatus(try await git(["diff-tree", "--root", "-r", "--name-status", "-z", "--no-commit-id", "-M", hash]))
            }
            // Ignore the result if the user has moved on to another commit.
            guard selection == .commit(hash) else { return }
            commitDetail = CommitDetail(commit: commit, message: message, files: files)
        } catch {
            Banner.shared.error("Couldn't load commit \(commit.shortID)", detail: error.localizedDescription)
        }
    }

    func showDiff(_ file: FileChange, source: DiffSource) {
        diff = DiffState(file: file, source: source)
        Task {
            do {
                let paths = [file.originalPath, file.path].compactMap { $0 }
                let output: String
                switch source {
                case .unstaged where file.status == "?":
                    output = try await git(["diff", "--no-index", "--", "/dev/null", file.path], ok: [0, 1])
                case .unstaged:
                    output = try await git(["diff", "--"] + paths)
                case .staged:
                    output = try await git(["diff", "--cached", "-M", "--"] + paths)
                case .commit(let hash, let parent?):
                    output = try await git(["diff", "-M", parent, hash, "--"] + paths)
                case .commit(let hash, nil):
                    output = try await git(["show", "--format=", hash, "--", file.path])
                }
                guard diff?.file == file, diff?.source == source else { return }
                let parsed = GitParse.diff(output)
                diff?.lines = parsed.lines
                diff?.truncated = parsed.truncated
                diff?.isLoading = false
            } catch {
                diff?.isLoading = false
                Banner.shared.error("Couldn't load diff", detail: error.localizedDescription)
            }
        }
    }

    // MARK: - Staging

    func stage(_ files: [FileChange]) async {
        await perform("Stage", fullRefresh: false) {
            try await git(["add", "-A", "--"] + files.map(\.path))
            return nil
        }
        refreshOpenDiff()
    }

    func stageAll() async {
        await perform("Stage all", fullRefresh: false) {
            try await git(["add", "-A"])
            return nil
        }
        refreshOpenDiff()
    }

    func unstage(_ files: [FileChange]) async {
        let paths = files.flatMap { [$0.originalPath, $0.path].compactMap { $0 } }
        await perform("Unstage", fullRefresh: false) {
            if hasCommits {
                try await git(["restore", "--staged", "--"] + paths)
            } else {
                try await git(["rm", "--cached", "-r", "-q", "--"] + paths)
            }
            return nil
        }
        refreshOpenDiff()
    }

    func unstageAll() async {
        await unstage(staged)
    }

    /// Throws away working-tree changes. Untracked files are deleted.
    func discard(_ files: [FileChange]) async {
        await perform("Discard", fullRefresh: false) {
            let untracked = files.filter { $0.status == "?" }.map(\.path)
            let tracked = files.filter { $0.status != "?" }.map(\.path)
            if !tracked.isEmpty { try await git(["restore", "--"] + tracked) }
            if !untracked.isEmpty { try await git(["clean", "-f", "-q", "--"] + untracked) }
            return nil
        }
        diff = nil
    }

    /// Appends a pattern (relative to the repo root) to the top-level .gitignore, unless it is already there.
    func addToGitignore(_ pattern: String, trackedPaths: [String] = []) async {
        await perform("Add to .gitignore", fullRefresh: false) {
            let file = url.appendingPathComponent(".gitignore")
            var contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let existing = contents.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            guard !existing.contains(pattern) else { return "\(pattern) is already in .gitignore" }
            if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
            contents += pattern + "\n"
            try contents.write(to: file, atomically: true, encoding: .utf8)
            // Ignoring doesn't affect files git already tracks, so say so rather than leave them listed silently.
            if !trackedPaths.isEmpty {
                return "Added \(pattern) to .gitignore. It's already tracked, so changes still show until you run git rm --cached"
            }
            return "Added \(pattern) to .gitignore"
        }
        diff = nil
    }

    /// A root-anchored .gitignore pattern matching exactly this path; folders get a trailing slash.
    static func gitignorePattern(for path: String, isFolder: Bool = false) -> String {
        // Escape glob characters so names like "file[1].txt" match literally.
        var escaped = ""
        for char in path {
            if "*?[]\\".contains(char) { escaped.append("\\") }
            escaped.append(char)
        }
        return "/" + escaped + (isFolder ? "/" : "")
    }

    private func refreshOpenDiff() {
        guard let diff else { return }
        // The file has moved between staged/unstaged; follow it if we can, otherwise close the diff.
        if diff.source == .unstaged, let file = unstaged.first(where: { $0.path == diff.file.path }) {
            showDiff(file, source: .unstaged)
        } else if diff.source == .staged, let file = staged.first(where: { $0.path == diff.file.path }) {
            showDiff(file, source: .staged)
        } else if case .commit = diff.source {
            return
        } else {
            self.diff = nil
        }
    }

    // MARK: - Committing

    /// Fills the commit draft from a full commit message (first line = summary).
    func useMessage(_ message: String) {
        let lines = message.components(separatedBy: "\n")
        draftSummary = lines.first ?? ""
        draftBody = lines.dropFirst().joined(separator: "\n").trimmed
    }

    var draftMessage: String {
        let body = draftBody.trimmed
        return body.isEmpty ? draftSummary.trimmed : draftSummary.trimmed + "\n\n" + body
    }

    func commit(andPush: Bool) async {
        let summary = draftSummary.trimmed
        guard !summary.isEmpty else {
            Banner.shared.error("Enter a commit summary first")
            return
        }
        let amending = amend
        guard amending || !staged.isEmpty || !unstaged.isEmpty else {
            Banner.shared.error("Nothing to commit")
            return
        }
        let needsForce = amending && headIsPushed
        let message = draftMessage

        let ok = await perform(amending ? "Amend" : "Commit") {
            // Nothing staged: behave like "stage all and commit".
            if staged.isEmpty && !amending { try await git(["add", "-A"]) }
            var args = ["commit", "-m", summary]
            let body = draftBody.trimmed
            if !body.isEmpty { args += ["-m", body] }
            if amending { args.append("--amend") }
            try await git(args)
            return andPush ? nil : (amending ? "Amended last commit" : "Committed to \(branch)")
        }
        guard ok else { return }

        MessageHistory.add(message)
        if needsForce { pendingForcePush = true }
        draftSummary = ""
        draftBody = ""
        amend = false
        select(.wip)
        if andPush { await push() }
    }

    /// Squashes HEAD into its parent, keeping the parent's message.
    func squashLastTwo() async {
        guard staged.isEmpty else {
            Banner.shared.error("Commit or unstage your staged changes before squashing")
            return
        }
        guard (try? await git(["rev-parse", "--verify", "-q", "HEAD~1"])) != nil else {
            Banner.shared.error("There is no previous commit to squash into")
            return
        }
        var parentPushed = false
        if upstream != nil {
            parentPushed = (try? await Git.run(["merge-base", "--is-ancestor", "HEAD~1", "@{u}"], in: url, ok: [0, 1]))?.status == 0
        }
        let ok = await perform("Squash") {
            try await git(["reset", "--soft", "HEAD~1"])
            try await git(["commit", "--amend", "--no-edit"])
            return "Squashed the last commit into the previous one"
        }
        if ok && parentPushed { pendingForcePush = true }
    }

    // MARK: - Remote operations

    func fetch() async {
        await perform("Fetch") {
            try await git(["fetch", "--all", "--prune"])
            return "Fetched \(name)"
        }
    }

    func pull(_ mode: PullMode = .current) async {
        await perform("Pull") {
            guard upstream != nil else { throw GitError(message: "\(branch) has no upstream branch to pull from.") }
            try await git(mode.args)
            return "Pulled \(branch)"
        }
    }

    func push(force: Bool = false) async {
        let useForce = force || pendingForcePush
        await perform(useForce ? "Force push" : "Push") {
            var args = ["push"]
            if useForce { args.append("--force-with-lease") }
            if upstream == nil {
                // First push of a new branch: publish it and set upstream.
                let remotes = try await git(["remote"]).split(separator: "\n").map(String.init)
                guard let remote = remotes.first(where: { $0 == "origin" }) ?? remotes.first else {
                    throw GitError(message: "This repository has no remote to push to.")
                }
                args += ["-u", remote, "HEAD"]
            }
            try await git(args)
            pendingForcePush = false
            return useForce ? "Force-pushed \(branch) (with lease)" : "Pushed \(branch)"
        }
    }

    /// Quiet fast-forward-only pull used by Pull All: records an outcome instead of showing banners.
    func pullForBulk() async {
        busy = "Pull"
        defer { busy = nil }
        await refreshStatus()
        guard exists else {
            lastOutcome = Outcome(kind: .failed, message: "Folder not found")
            return
        }
        guard upstream != nil else {
            lastOutcome = Outcome(kind: .skipped, message: "No upstream branch")
            return
        }
        do {
            let before = try await git(["rev-parse", "HEAD"]).trimmed
            try await git(["pull", "--ff-only"])
            let after = try await git(["rev-parse", "HEAD"]).trimmed
            if before == after {
                lastOutcome = Outcome(kind: .upToDate, message: "Up to date")
            } else {
                let count = (try? await git(["rev-list", "--count", "\(before)..\(after)"]).trimmed) ?? "?"
                lastOutcome = Outcome(kind: .updated, message: "Pulled \(count) commit\(count == "1" ? "" : "s")")
            }
        } catch {
            let firstLine = error.localizedDescription.components(separatedBy: "\n").first ?? ""
            lastOutcome = Outcome(kind: .failed, message: firstLine)
        }
        await refreshStatus()
        if detailLoaded { await refreshDetail() }
    }

    func fetchForBulk() async {
        busy = "Fetch"
        defer { busy = nil }
        do {
            try await git(["fetch", "--all", "--prune"])
            await refreshStatus()
            lastOutcome = Outcome(kind: behind > 0 ? .updated : .upToDate,
                                  message: behind > 0 ? "\(behind) to pull" : "Up to date")
        } catch {
            lastOutcome = Outcome(kind: .failed, message: error.localizedDescription.components(separatedBy: "\n").first ?? "")
        }
        if detailLoaded { await refreshDetail() }
    }

    // MARK: - Branches

    func checkout(_ branch: Branch) async {
        await perform("Checkout") {
            if branch.isRemote {
                // Remote branch: switch to the matching local branch, creating a tracking branch if needed.
                let localName = branch.name.split(separator: "/", maxSplits: 1).last.map(String.init) ?? branch.name
                if localBranches.contains(where: { $0.name == localName }) {
                    try await git(["checkout", localName])
                } else {
                    try await git(["checkout", "-b", localName, "--track", branch.name])
                }
                return "Checked out \(localName)"
            }
            try await git(["checkout", branch.name])
            return "Checked out \(branch.name)"
        }
    }

    func createBranch(_ name: String, at startPoint: String? = nil) async {
        await perform("Create branch") {
            try await git(["checkout", "-b", name] + (startPoint.map { [$0] } ?? []))
            return "Created and checked out \(name)"
        }
    }

    func deleteBranch(_ branch: Branch) async {
        await perform("Delete branch") {
            try await git(["branch", "-d", branch.name])
            return "Deleted \(branch.name)"
        }
    }

    func merge(_ ref: String) async {
        await perform("Merge") {
            try await git(["merge", ref])
            return "Merged \(ref) into \(branch)"
        }
    }

    // MARK: - Commits

    func cherryPick(_ hash: String) async {
        await perform("Cherry-pick") {
            try await git(["cherry-pick", hash])
            return "Cherry-picked \(hash.prefix(7))"
        }
    }

    func revert(_ hash: String) async {
        await perform("Revert") {
            try await git(["revert", "--no-edit", hash])
            return "Reverted \(hash.prefix(7))"
        }
    }

    /// Moves the current branch to `hash`. Soft keeps changes staged; mixed keeps them unstaged.
    func reset(to hash: String, mode: String) async {
        await perform("Reset") {
            try await git(["reset", "--\(mode)", hash])
            return "Reset \(branch) to \(hash.prefix(7)) (\(mode))"
        }
    }

    // MARK: - Stashes

    func stash() async {
        guard changeCount > 0 else {
            Banner.shared.error("No changes to stash")
            return
        }
        await perform("Stash") {
            try await git(["stash", "push", "--include-untracked"])
            return "Stashed changes"
        }
    }

    func popStash(_ stash: Stash? = nil) async {
        await perform("Pop stash") {
            try await git(["stash", "pop"] + (stash.map { [$0.ref] } ?? []))
            return "Popped stash"
        }
    }

    func applyStash(_ stash: Stash) async {
        await perform("Apply stash") {
            try await git(["stash", "apply", stash.ref])
            return "Applied \(stash.ref)"
        }
    }

    func dropStash(_ stash: Stash) async {
        await perform("Drop stash") {
            try await git(["stash", "drop", stash.ref])
            return "Dropped \(stash.ref)"
        }
    }
}
