import SwiftUI

/// "All Repositories": a table of every repo with Pull All / Fetch All.
struct OverviewView: View {
    @Environment(RepoStore.self) private var store
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Repositories").font(.title2.bold())
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if let operation = store.bulkOperation {
                    ProgressView().controlSize(.small)
                    Text(operation).foregroundStyle(.secondary)
                }
                Button { Task { await store.refreshAllStatuses() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button { Task { await store.fetchAll() } } label: { Label("Fetch All", systemImage: "arrow.triangle.2.circlepath") }
                Button { Task { await store.pullAll() } } label: { Label("Pull All", systemImage: "arrow.down.to.line") }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
            .disabled(store.bulkOperation != nil)
            .padding(16)

            if store.repos.isEmpty {
                ContentUnavailableView {
                    Label("No repositories yet", systemImage: "folder.badge.plus")
                } description: {
                    Text("Add repositories one at a time, scan a folder to find them all, or clone a new one.")
                } actions: {
                    HStack {
                        Button("Add Repository…") { store.promptAddRepository() }
                        Button("Scan Folder…") { store.promptScanFolder() }
                        Button("Clone…") { store.showClone = true }
                    }
                }
            } else {
                Table(store.repos, selection: $selection) {
                    TableColumn("Repository") { repo in
                        HStack {
                            Image(systemName: repo.exists ? "folder.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(repo.exists ? Theme.accent : .orange)
                            Text(repo.name).fontWeight(.medium)
                            if repo.busy != nil { ProgressView().controlSize(.mini) }
                        }
                    }
                    .width(min: 160, ideal: 220)
                    TableColumn("Branch") { repo in Text(repo.branch) }
                        .width(min: 80, ideal: 140)
                    TableColumn("Changes") { repo in
                        Text(repo.changeCount == 0 ? "—" : "\(repo.changeCount)")
                            .foregroundStyle(repo.changeCount == 0 ? .secondary : Color.orange)
                    }
                    .width(70)
                    TableColumn("Behind / Ahead") { repo in
                        HStack(spacing: 8) {
                            Text("↓\(repo.behind)").foregroundStyle(repo.behind > 0 ? .cyan : .secondary)
                            Text("↑\(repo.ahead)").foregroundStyle(repo.ahead > 0 ? .green : .secondary)
                        }
                        .font(.system(size: 12, design: .monospaced))
                    }
                    .width(110)
                    TableColumn("Last Pull / Fetch") { repo in
                        if let outcome = repo.lastOutcome {
                            Label(outcome.message, systemImage: icon(outcome.kind))
                                .foregroundStyle(colour(outcome.kind))
                                .help("\(outcome.message) — \(Theme.dateFormatter.string(from: outcome.date))")
                        }
                    }
                    .width(min: 140, ideal: 260)
                    TableColumn("Path") { repo in
                        Text(repo.url.path).foregroundStyle(.secondary).truncationMode(.middle)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    let chosen = store.repos.filter { ids.contains($0.id) }
                    Button("Open") { if let first = chosen.first { store.selectedID = first.id } }
                    Button("Pull") { Task { for repo in chosen { await repo.pull() } } }
                    Button("Fetch") { Task { for repo in chosen { await repo.fetch() } } }
                    Divider()
                    if let first = chosen.first {
                        Button("Reveal in Finder") { store.revealInFinder(first) }
                        Button("Open in Terminal") { store.openInTerminal(first) }
                    }
                    Divider()
                    Button("Remove from List", role: .destructive) { chosen.forEach(store.remove) }
                } primaryAction: { ids in
                    if let id = ids.first { store.selectedID = id }
                }
            }
        }
        .background(Theme.background)
    }

    private var summary: String {
        let dirty = store.repos.filter { $0.changeCount > 0 }.count
        let behind = store.repos.filter { $0.behind > 0 }.count
        let ahead = store.repos.filter { $0.ahead > 0 }.count
        return "\(store.repos.count) repositories · \(dirty) with changes · \(behind) to pull · \(ahead) to push · double-click to open"
    }

    private func icon(_ kind: Outcome.Kind) -> String {
        switch kind {
        case .updated: "arrow.down.circle.fill"
        case .upToDate: "checkmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        case .skipped: "minus.circle"
        }
    }

    private func colour(_ kind: Outcome.Kind) -> Color {
        switch kind {
        case .updated: .cyan
        case .upToDate: .secondary
        case .failed: .orange
        case .skipped: .secondary
        }
    }
}
