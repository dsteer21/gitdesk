import SwiftUI

struct CloneSheet: View {
    @Environment(RepoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cloneFolder") private var cloneFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sites").path

    @State private var remote = ""
    @State private var name = ""
    @State private var nameEdited = false
    @State private var cloning = false
    @State private var error: String?

    /// "git@github.com:org/my-repo.git" or "https://…/my-repo.git" → "my-repo"
    private var suggestedName: String {
        let last = remote.trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clone a Repository").font(.title2.bold())

            Form {
                TextField("URL", text: $remote, prompt: Text("git@github.com:org/repo.git or https://…"))
                    .onChange(of: remote) { if !nameEdited { name = suggestedName } }
                HStack {
                    TextField("Where to clone to", text: $cloneFolder)
                    Button("Browse…", action: chooseFolder)
                }
                TextField("Folder name", text: Binding(get: { name }, set: { name = $0; nameEdited = true }))
            }
            .formStyle(.columns)

            if !name.isEmpty {
                Text("Full path: \((cloneFolder as NSString).appendingPathComponent(name))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }

            HStack {
                if cloning { ProgressView().controlSize(.small); Text("Cloning…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(cloning)
                Button("Clone", action: clone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cloning || remote.trimmed.isEmpty || name.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: cloneFolder)
        if panel.runModal() == .OK, let url = panel.url { cloneFolder = url.path }
    }

    private func clone() {
        cloning = true
        error = nil
        Task {
            do {
                try await store.clone(remote.trimmed, into: URL(fileURLWithPath: cloneFolder), name: name.trimmed)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            cloning = false
        }
    }
}

struct ScanSheet: View {
    @Environment(RepoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let candidates: [URL]
    @State private var chosen: Set<URL> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Found \(candidates.count) Repositor\(candidates.count == 1 ? "y" : "ies")").font(.title2.bold())
            Text("Choose which to add to GitDesk.").foregroundStyle(.secondary)

            List(candidates, id: \.self) { url in
                Toggle(isOn: Binding(
                    get: { chosen.contains(url) },
                    set: { if $0 { chosen.insert(url) } else { chosen.remove(url) } }
                )) {
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent).fontWeight(.medium)
                        Text(url.path).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 320)

            HStack {
                Button(chosen.count == candidates.count ? "Select None" : "Select All") {
                    chosen = chosen.count == candidates.count ? [] : Set(candidates)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add \(chosen.count)") {
                    let urls = candidates.filter { chosen.contains($0) }
                    dismiss()
                    Task { await store.addScanned(urls) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { chosen = Set(candidates) }
    }
}

struct NewBranchSheet: View {
    @Environment(RepoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let repo: Repo
    @State private var name = ""

    var body: some View {
        let startPoint = store.newBranchStartPoint
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Branch").font(.title2.bold())
            Text("From \(startPoint.map { $0.count == 40 ? String($0.prefix(7)) : $0 } ?? repo.branch). The new branch will be checked out.")
                .foregroundStyle(.secondary)
            TextField("Branch name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// Spaces aren't allowed in branch names; swap them for hyphens as you type.
    private var cleanName: String { name.trimmed.replacingOccurrences(of: " ", with: "-") }

    private func create() {
        guard !cleanName.isEmpty else { return }
        let branch = cleanName
        let startPoint = store.newBranchStartPoint
        dismiss()
        Task { await repo.createBranch(branch, at: startPoint) }
    }
}

/// ⌘P → "Commit & Push…": asks for a commit message, then commits and pushes.
/// Uses the same draft as the commit panel, so nothing typed in either place is lost.
struct CommitPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var repo: Repo
    @FocusState private var summaryFocused: Bool

    /// What will be committed: the staged files, or everything when nothing is staged.
    private var scope: String {
        if !repo.staged.isEmpty {
            let count = repo.staged.count
            return "\(count) staged file\(count == 1 ? "" : "s")"
        }
        let count = repo.unstaged.count
        return count == 1 ? "the 1 changed file" : "all \(count) changed files"
    }

    private var canCommit: Bool {
        repo.busy == nil && !repo.draftSummary.trimmed.isEmpty && (repo.amend || repo.changeCount > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Commit & Push").font(.title2.bold())
                Spacer()
                ReuseMessageMenu(repo: repo)
            }
            Text("Commits \(scope) to \(repo.branch) in \(repo.name), then pushes.")
                .foregroundStyle(.secondary)

            TextField("Summary", text: $repo.draftSummary)
                .textFieldStyle(.roundedBorder)
                .focused($summaryFocused)
                .onSubmit(commit)

            TextField("Description (optional)", text: $repo.draftBody, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            Toggle("Amend previous commit (squash into \(repo.headCommit?.shortID ?? "the last commit"))", isOn: $repo.amend)
                .disabled(!repo.hasCommits)
                .onChange(of: repo.amend) { _, amending in
                    // Same as the commit panel: amending starts from the previous message.
                    if amending, repo.draftSummary.trimmed.isEmpty, let message = repo.lastCommitMessage {
                        repo.useMessage(message)
                    }
                }
            if repo.amend && repo.headIsPushed {
                Label("The last commit is already pushed, so this will force-push with lease.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(repo.amend && repo.headIsPushed ? "Amend & Force Push" : "Commit & Push", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommit)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { summaryFocused = true }
    }

    private func commit() {
        guard canCommit else { return }
        dismiss()
        Task { await repo.commit(andPush: true) }
    }
}
