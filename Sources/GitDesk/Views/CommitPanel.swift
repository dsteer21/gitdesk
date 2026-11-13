import SwiftUI

/// Right panel when "// WIP" is selected: staging area and commit box.
struct CommitPanel: View {
    @Bindable var repo: Repo
    @State private var filesToDiscard: [FileChange]?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "pencil.and.list.clipboard")
                Text("\(repo.changeCount) file change\(repo.changeCount == 1 ? "" : "s") on ")
                    + Text(repo.branch).bold()
                Spacer()
            }
            .font(.system(size: 12))
            .padding(10)
            .background(Theme.panel)

            Divider()

            VSplitView {
                FileSection(
                    title: "Unstaged Files", files: repo.unstaged, source: .unstaged, repo: repo,
                    bulkTitle: "Stage All", bulkAction: { Task { await repo.stageAll() } },
                    rowIcon: "plus.circle.fill", rowHelp: "Stage", rowAction: { file in Task { await repo.stage([file]) } },
                    discard: { filesToDiscard = $0 }
                )
                .frame(minHeight: 90)

                FileSection(
                    title: "Staged Files", files: repo.staged, source: .staged, repo: repo,
                    bulkTitle: "Unstage All", bulkAction: { Task { await repo.unstageAll() } },
                    rowIcon: "minus.circle.fill", rowHelp: "Unstage", rowAction: { file in Task { await repo.unstage([file]) } },
                    discard: nil
                )
                .frame(minHeight: 90)

                CommitBox(repo: repo)
                    .frame(minHeight: 250)
            }
        }
        .background(Theme.background)
        .confirmationDialog(
            "Discard changes to \(filesToDiscard?.count == 1 ? filesToDiscard![0].fileName : "\(filesToDiscard?.count ?? 0) files")?",
            isPresented: Binding(get: { filesToDiscard != nil }, set: { if !$0 { filesToDiscard = nil } })
        ) {
            Button("Discard", role: .destructive) {
                if let files = filesToDiscard { Task { await repo.discard(files) } }
            }
        } message: {
            Text("This can't be undone. New (untracked) files will be deleted.")
        }
    }
}

private struct FileSection: View {
    let title: String
    let files: [FileChange]
    let source: DiffSource
    let repo: Repo
    let bulkTitle: String
    let bulkAction: () -> Void
    let rowIcon: String
    let rowHelp: String
    let rowAction: (FileChange) -> Void
    let discard: (([FileChange]) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeader(title: title, count: files.count)
                Spacer()
                if let discard, !files.isEmpty {
                    Button("Discard All") { discard(files) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                Button(bulkTitle, action: bulkAction)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .disabled(files.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if files.isEmpty {
                Text(source == .staged ? "Nothing staged" : "No unstaged changes")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            FileRow(
                                file: file,
                                selected: repo.diff?.file.path == file.path && repo.diff?.source == source,
                                actionIcon: rowIcon, actionHelp: rowHelp,
                                action: { rowAction(file) },
                                open: { repo.showDiff(file, source: source) }
                            )
                            .contextMenu {
                                Button(rowHelp) { rowAction(file) }
                                if let discard {
                                    Button("Discard Changes…", role: .destructive) { discard([file]) }
                                }
                                if source == .unstaged { ignoreMenu(file) }
                                Divider()
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([repo.url.appendingPathComponent(file.path)])
                                }
                                Button("Open File") { NSWorkspace.shared.open(repo.url.appendingPathComponent(file.path)) }
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(file.path, forType: .string)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

extension FileSection {
    /// "Add to .gitignore" submenu: the file, each folder it sits in, or every file with its extension.
    @ViewBuilder
    func ignoreMenu(_ file: FileChange) -> some View {
        let tracked = file.status == "?" ? [] : [file.path]
        let folders = ancestorFolders(of: file.path)
        let ext = (file.fileName as NSString).pathExtension
        Menu("Add to .gitignore") {
            Button("Ignore \(file.fileName)") {
                Task { await repo.addToGitignore(Repo.gitignorePattern(for: file.path), trackedPaths: tracked) }
            }
            ForEach(folders, id: \.self) { folder in
                Button("Ignore Folder \(folder)/") {
                    Task { await repo.addToGitignore(Repo.gitignorePattern(for: folder, isFolder: true), trackedPaths: tracked) }
                }
            }
            if !ext.isEmpty {
                Divider()
                Button("Ignore All *.\(ext) Files") {
                    Task { await repo.addToGitignore("*." + ext, trackedPaths: tracked) }
                }
            }
        }
    }

    /// "a/b/c.txt" → ["a/b", "a"]: the nearest folder first.
    private func ancestorFolders(of path: String) -> [String] {
        var folders: [String] = []
        var current = (path as NSString).deletingLastPathComponent
        while !current.isEmpty {
            folders.append(current)
            current = (current as NSString).deletingLastPathComponent
        }
        return folders
    }
}

struct FileRow: View {
    let file: FileChange
    let selected: Bool
    var actionIcon: String?
    var actionHelp = ""
    var action: () -> Void = {}
    let open: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Theme.statusIcon(file.status))
                .foregroundStyle(Theme.statusColour(file.status))
                .font(.system(size: 11))
            Text(file.fileName).lineLimit(1)
            Text(file.directory)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            if let actionIcon, hovering {
                Button(action: action) {
                    Image(systemName: actionIcon).foregroundStyle(actionIcon.hasPrefix("plus") ? .green : .red)
                }
                .buttonStyle(.plain)
                .help(actionHelp)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(selected ? Theme.selection : (hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help(file.originalPath.map { "\($0) → \(file.path)" } ?? file.path)
    }
}

/// Summary/description box with the amend (squash) toggle and message re-use.
private struct CommitBox: View {
    @Bindable var repo: Repo
    @FocusState private var summaryFocused: Bool

    private var commitTitle: String {
        if repo.amend { return "Amend Previous Commit" }
        if repo.staged.isEmpty && !repo.unstaged.isEmpty { return "Stage All & Commit" }
        let count = repo.staged.count
        return "Commit \(count) File\(count == 1 ? "" : "s")"
    }

    private var canCommit: Bool {
        repo.busy == nil && !repo.draftSummary.trimmed.isEmpty && (repo.amend || repo.changeCount > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Commit")
                Spacer()
                ReuseMessageMenu(repo: repo)
            }

            Toggle(isOn: $repo.amend) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Amend previous commit").font(.system(size: 12))
                    Text("Squash these changes into \(repo.headCommit?.shortID ?? "the last commit")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!repo.hasCommits)
            .onChange(of: repo.amend) { _, amending in
                // Pre-fill the previous message so amend keeps it unless changed.
                if amending, repo.draftSummary.trimmed.isEmpty, let message = repo.lastCommitMessage {
                    repo.useMessage(message)
                }
            }

            if repo.amend && repo.headIsPushed {
                Label("The last commit is already pushed. Pushing after amending will force-push with lease.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if repo.pendingForcePush {
                Label("Next push will force-push with lease (history was rewritten).", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Summary", text: $repo.draftSummary)
                    .textFieldStyle(.roundedBorder)
                    .focused($summaryFocused)
                    .onSubmit { if canCommit { Task { await repo.commit(andPush: false) } } }
                Text("\(72 - repo.draftSummary.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(repo.draftSummary.count > 72 ? .red : .secondary)
                    .frame(width: 26, alignment: .trailing)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $repo.draftBody)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                if repo.draftBody.isEmpty {
                    Text("Description").font(.system(size: 12)).foregroundStyle(.tertiary).padding(8).allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.25)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1)))
            .frame(minHeight: 60, maxHeight: .infinity)

            HStack(spacing: 8) {
                Button {
                    Task { await repo.commit(andPush: false) }
                } label: {
                    Text(commitTitle).frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩")

                Button {
                    Task { await repo.commit(andPush: true) }
                } label: {
                    Text(repo.amend && repo.headIsPushed ? "Amend & Force Push" : "Commit & Push").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .help("⇧⌘↩")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canCommit)
        }
        .padding(10)
        .background(Theme.panel)
    }
}

/// "Reuse message" menu: last commit in this repo plus messages recently used in any repo.
struct ReuseMessageMenu: View {
    let repo: Repo

    var body: some View {
        Menu {
            if let last = repo.lastCommitMessage {
                Section("Last commit in \(repo.name)") {
                    Button(preview(last)) { repo.useMessage(last) }
                }
            }
            let recent = MessageHistory.all.filter { $0 != repo.lastCommitMessage }
            if !recent.isEmpty {
                Section("Recently used") {
                    ForEach(recent, id: \.self) { message in
                        Button(preview(message)) { repo.useMessage(message) }
                    }
                }
            }
            Divider()
            Button("Clear Message") {
                repo.draftSummary = ""
                repo.draftBody = ""
            }
        } label: {
            Label("Reuse message", systemImage: "arrow.uturn.backward")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Reuse the last commit message")
    }

    private func preview(_ message: String) -> String {
        let firstLine = message.components(separatedBy: "\n").first ?? message
        return firstLine.count > 70 ? String(firstLine.prefix(70)) + "…" : firstLine
    }
}
