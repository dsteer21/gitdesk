import SwiftUI

/// The GitKraken-style top bar: repo/branch switchers on the left, the main
/// actions in the centre, and app-wide actions on the right.
struct TopBar: View {
    @Environment(RepoStore.self) private var store
    @AppStorage("pullMode") private var pullMode: PullMode = .merge
    @State private var showRepoPicker = false
    @State private var showBranchPicker = false

    var body: some View {
        let repo = store.selected
        let idle = repo != nil && repo?.busy == nil

        HStack(spacing: 2) {
            switcher(caption: "repository", value: repo?.name ?? "All Repositories", icon: "folder") { showRepoPicker = true }
                .popover(isPresented: $showRepoPicker, arrowEdge: .bottom) {
                    RepoPicker { showRepoPicker = false }
                }
            if let repo {
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                switcher(caption: "branch", value: repo.branch.isEmpty ? "—" : repo.branch, icon: "arrow.triangle.branch") { showBranchPicker = true }
                    .popover(isPresented: $showBranchPicker, arrowEdge: .bottom) {
                        BranchPicker(repo: repo) { showBranchPicker = false }
                    }
            }

            Spacer(minLength: 16)

            Group {
                SplitToolButton(title: "Pull", icon: "arrow.down.to.line", badge: repo?.behind ?? 0,
                                help: "Pull (\(pullMode.title))") {
                    Task { await repo?.pull(pullMode) }
                } menu: {
                    ForEach(PullMode.allCases) { mode in
                        Button {
                            pullMode = mode
                            Task { await repo?.pull(mode) }
                        } label: {
                            if mode == pullMode { Label(mode.title, systemImage: "checkmark") } else { Text(mode.title) }
                        }
                    }
                    Divider()
                    Button("Fetch") { Task { await repo?.fetch() } }
                }
                SplitToolButton(title: "Push", icon: "arrow.up.to.line", badge: repo?.ahead ?? 0,
                                help: repo?.pendingForcePush == true ? "Push (will force with lease after amend)" : "Push") {
                    Task { await repo?.push() }
                } menu: {
                    Button("Push") { Task { await repo?.push() } }
                    Button("Force Push (with lease)") { Task { await repo?.push(force: true) } }
                }
                ToolButton(title: "Fetch", icon: "arrow.triangle.2.circlepath") { Task { await repo?.fetch() } }
                ToolButton(title: "Branch", icon: "arrow.triangle.branch") { store.showNewBranch = true }
                ToolButton(title: "Stash", icon: "tray.and.arrow.down") { Task { await repo?.stash() } }
                ToolButton(title: "Pop", icon: "tray.and.arrow.up") { Task { await repo?.popStash() } }
            }
            .disabled(!idle)

            Spacer(minLength: 16)

            ToolButton(title: "Pull All", icon: "square.stack.3d.down.right",
                       help: "Fast-forward pull every repository") {
                Task { await store.pullAll() }
            }
            .disabled(store.bulkOperation != nil || store.repos.isEmpty)
            ToolButton(title: "Clone", icon: "square.and.arrow.down") { store.showClone = true }
            Menu {
                Button("Add Repository…") { store.promptAddRepository() }
                Button("Scan Folder…") { store.promptScanFolder() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 32)
            .help("Add repositories")

            Button {
                store.showPalette = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                    Text("⌘P").foregroundStyle(.tertiary)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
        .padding(.leading, 78) // clear the window's traffic-light buttons
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(Theme.toolbar)
    }

    private func switcher(caption: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(caption).font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 240, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Searchable list used by the repo and branch pop-overs.
private struct PickerList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let text: (Item) -> String
    let onPick: (Item) -> Void
    @ViewBuilder let row: (Item) -> Row
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List {
                ForEach(items.filter { query.isEmpty || text($0).localizedCaseInsensitiveContains(query) }) { item in
                    Button { onPick(item) } label: { row(item).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 320, height: 380)
    }
}

private struct RepoPicker: View {
    @Environment(RepoStore.self) private var store
    let dismiss: () -> Void

    var body: some View {
        PickerList(items: store.repos, text: \.name) { repo in
            store.selectedID = repo.id
            dismiss()
        } row: { repo in
            HStack {
                Text(repo.name)
                Spacer()
                Text(repo.branch).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BranchPicker: View {
    let repo: Repo
    let dismiss: () -> Void

    var body: some View {
        PickerList(items: repo.localBranches + repo.remoteBranches, text: \.name) { branch in
            dismiss()
            if !branch.isHead { Task { await repo.checkout(branch) } }
        } row: { branch in
            HStack {
                Image(systemName: branch.isRemote ? "cloud" : "laptopcomputer").foregroundStyle(.secondary)
                Text(branch.name).fontWeight(branch.isHead ? .bold : .regular)
                if branch.isHead { Image(systemName: "checkmark").foregroundStyle(.green) }
            }
        }
    }
}
