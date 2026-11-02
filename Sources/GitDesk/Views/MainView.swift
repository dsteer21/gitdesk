import SwiftUI

struct MainView: View {
    @Environment(RepoStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            TopBar()
            Divider()
            HSplitView {
                SidebarView()
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 340)

                if let repo = store.selected {
                    Group {
                        if repo.diff != nil {
                            DiffView(repo: repo)
                        } else {
                            GraphView(repo: repo)
                        }
                    }
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    Group {
                        if repo.selection == .wip {
                            CommitPanel(repo: repo)
                        } else {
                            CommitDetailView(repo: repo)
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 480, maxHeight: .infinity)
                } else {
                    OverviewView()
                        .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            StatusBar()
        }
        .background(Theme.background)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .bottomTrailing) { BannerView().padding(.bottom, 34).padding(.trailing, 16) }
        .overlay {
            if store.showPalette { CommandPalette() }
        }
        .sheet(isPresented: $store.showClone) { CloneSheet() }
        .sheet(isPresented: $store.showNewBranch) {
            if let repo = store.selected { NewBranchSheet(repo: repo) }
        }
        .sheet(isPresented: Binding(get: { store.scanCandidates != nil }, set: { if !$0 { store.scanCandidates = nil } })) {
            ScanSheet(candidates: store.scanCandidates ?? [])
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Pick up changes made in the terminal or an editor while we were in the background.
            Task {
                if let repo = store.selected { await repo.refresh() }
                await store.refreshAllStatuses()
            }
        }
        .task {
            // Light polling of the open repo's working tree so the WIP panel stays current.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if NSApp.isActive, let repo = store.selected, repo.busy == nil { await repo.refreshStatus() }
            }
        }
    }
}

struct StatusBar: View {
    @Environment(RepoStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            if let operation = store.bulkOperation ?? store.selected?.busy.map({ "\($0)…" }) {
                ProgressView().controlSize(.small)
                Text(operation)
            } else if let repo = store.selected {
                Image(systemName: "folder")
                Text(repo.url.path).lineLimit(1).truncationMode(.middle)
            } else {
                Text("\(store.repos.count) repositories")
            }
            Spacer()
            if let repo = store.selected, let upstream = repo.upstream {
                Image(systemName: "cloud")
                Text(upstream)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Theme.toolbar)
    }
}

struct BannerView: View {
    @State private var banner = Banner.shared

    var body: some View {
        if let item = banner.current {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.isError ? "exclamationmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundStyle(item.isError ? .red : .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.text).font(.system(size: 12, weight: .semibold))
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .textSelection(.enabled)
                    }
                }
                Button {
                    banner.current = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: 460, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel).shadow(radius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.isError ? Color.red.opacity(0.6) : Color.white.opacity(0.1)))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(item.id)
        }
    }
}
