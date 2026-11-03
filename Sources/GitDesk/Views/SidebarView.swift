import SwiftUI

/// Left panel: every repository, then the open repo's branches, stashes and tags.
struct SidebarView: View {
    @Environment(RepoStore.self) private var store
    @State private var filter = ""
    @State private var showRepos = true
    @State private var showLocal = true
    @State private var showRemote = true
    @State private var showStashes = true
    @State private var showTags = false
    @State private var branchToDelete: Branch?

    private var filteredRepos: [Repo] {
        filter.isEmpty ? store.repos : store.repos.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                TextField("Filter repositories", text: $filter).textFieldStyle(.plain)
            }
            .font(.system(size: 12))
            .padding(8)
            .background(Theme.toolbar)

            List(selection: $store.selectedID) {
                Button {
                    store.selectedID = nil
                } label: {
                    Label("All Repositories", systemImage: "square.grid.2x2")
                        .fontWeight(store.selectedID == nil ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Section(isExpanded: $showRepos) {
                    ForEach(filteredRepos) { repo in
                        RepoRow(repo: repo)
                            .tag(Optional(repo.id))
                            .contextMenu { repoMenu(repo) }
                    }
                } header: {
                    SectionHeader(title: "Repositories", count: store.repos.count)
                }

                if let repo = store.selected, filter.isEmpty {
                    Section(isExpanded: $showLocal) {
                        ForEach(repo.localBranches) { branch in
                            BranchRow(branch: branch)
                                .onTapGesture(count: 2) { Task { await repo.checkout(branch) } }
                                .contextMenu { branchMenu(branch, in: repo) }
                        }
                    } header: {
                        SectionHeader(title: "Local", count: repo.localBranches.count)
                    }

                    Section(isExpanded: $showRemote) {
                        ForEach(repo.remoteBranches) { branch in
                            BranchRow(branch: branch)
                                .onTapGesture(count: 2) { Task { await repo.checkout(branch) } }
                                .contextMenu { branchMenu(branch, in: repo) }
                        }
                    } header: {
                        SectionHeader(title: "Remote", count: repo.remoteBranches.count)
                    }

                    Section(isExpanded: $showStashes) {
                        ForEach(repo.stashes) { stash in
                            Label(stash.message, systemImage: "tray")
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .help(stash.ref)
                                .contextMenu {
                                    Button("Apply") { Task { await repo.applyStash(stash) } }
                                    Button("Pop") { Task { await repo.popStash(stash) } }
                                    Divider()
                                    Button("Drop", role: .destructive) { Task { await repo.dropStash(stash) } }
                                }
                        }
                    } header: {
                        SectionHeader(title: "Stashes", count: repo.stashes.count)
                    }

                    Section(isExpanded: $showTags) {
                        ForEach(repo.tags, id: \.self) { tag in
                            Label(tag, systemImage: "tag").font(.system(size: 12))
                        }
                    } header: {
                        SectionHeader(title: "Tags", count: repo.tags.count)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .confirmationDialog("Delete branch \(branchToDelete?.name ?? "")?", isPresented: Binding(
            get: { branchToDelete != nil }, set: { if !$0 { branchToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let branch = branchToDelete, let repo = store.selected { Task { await repo.deleteBranch(branch) } }
            }
        } message: {
            Text("Only branches that are fully merged can be deleted.")
        }
    }

    @ViewBuilder
    private func repoMenu(_ repo: Repo) -> some View {
        Button("Pull") { Task { await repo.pull() } }
        Button("Push") { Task { await repo.push() } }
        Button("Fetch") { Task { await repo.fetch() } }
        Divider()
        Button("Reveal in Finder") { store.revealInFinder(repo) }
        Button("Open in Terminal") { store.openInTerminal(repo) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(repo.url.path, forType: .string)
        }
        Divider()
        Button("Remove from List", role: .destructive) { store.remove(repo) }
    }

    @ViewBuilder
    private func branchMenu(_ branch: Branch, in repo: Repo) -> some View {
        if !branch.isHead {
            Button("Checkout \(branch.name)") { Task { await repo.checkout(branch) } }
            Button("Merge \(branch.name) into \(repo.branch)") { Task { await repo.merge(branch.name) } }
        }
        Button("Create Branch Here…") {
            store.newBranchStartPoint = branch.name
            store.showNewBranch = true
        }
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch.name, forType: .string)
        }
        if !branch.isRemote && !branch.isHead {
            Divider()
            Button("Delete \(branch.name)…", role: .destructive) { branchToDelete = branch }
        }
    }
}

private struct RepoRow: View {
    let repo: Repo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: repo.exists ? "folder.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(repo.exists ? Theme.accent : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(repo.exists ? repo.branch : "Folder missing")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if repo.busy != nil {
                ProgressView().controlSize(.mini)
            }
            if repo.changeCount > 0 {
                Circle().fill(.orange).frame(width: 6, height: 6).help("\(repo.changeCount) uncommitted changes")
            }
            if repo.behind > 0 {
                Text("↓\(repo.behind)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
            }
            if repo.ahead > 0 {
                Text("↑\(repo.ahead)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct BranchRow: View {
    let branch: Branch

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: branch.isRemote ? "cloud" : (branch.isHead ? "checkmark.circle.fill" : "laptopcomputer"))
                .foregroundStyle(branch.isHead ? .green : .secondary)
                .font(.system(size: 11))
            Text(branch.name)
                .font(.system(size: 12, weight: branch.isHead ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            if !branch.track.isEmpty {
                Text(branch.track.replacingOccurrences(of: "ahead ", with: "↑").replacingOccurrences(of: "behind ", with: "↓"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
