import SwiftUI

/// The centre panel: commit history with a lane graph, newest first.
struct GraphView: View {
    let repo: Repo

    static let rowHeight: CGFloat = 28
    static let laneWidth: CGFloat = 22
    static let avatarSize: CGFloat = 18
    static let maxVisibleLanes = 14

    private var graphWidth: CGFloat {
        max(CGFloat(min(repo.maxLanes, Self.maxVisibleLanes)) * Self.laneWidth + 8, 56)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if repo.entries.isEmpty && repo.changeCount == 0 {
                ContentUnavailableView(repo.detailLoaded ? "No commits yet" : "Loading…", systemImage: "point.3.connected.trianglepath.dotted")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if repo.changeCount > 0 {
                            WIPRow(repo: repo, graphWidth: graphWidth)
                        }
                        ForEach(repo.entries) { entry in
                            CommitRow(repo: repo, entry: entry, graphWidth: graphWidth)
                        }
                        if repo.entries.count >= Repo.logLimit {
                            Text("Showing the latest \(Repo.logLimit) commits")
                                .font(.caption).foregroundStyle(.secondary).padding()
                        }
                    }
                }
            }
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("BRANCH / TAG").frame(width: CommitRow.refsWidth, alignment: .leading)
            Text("GRAPH").frame(width: graphWidth, alignment: .leading)
            Text("COMMIT MESSAGE").frame(maxWidth: .infinity, alignment: .leading)
            Text("AUTHOR").frame(width: CommitRow.authorWidth, alignment: .leading)
            Text("DATE").frame(width: CommitRow.dateWidth, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Theme.panel)
    }
}

private struct WIPRow: View {
    let repo: Repo
    let graphWidth: CGFloat
    @State private var hovering = false

    var body: some View {
        let selected = repo.selection == .wip
        HStack(spacing: 0) {
            Color.clear.frame(width: CommitRow.refsWidth)
            Canvas { context, size in
                let centre = CGPoint(x: GraphView.laneWidth / 2 + 4, y: size.height / 2)
                let circle = Path(ellipseIn: CGRect(x: centre.x - 6, y: centre.y - 6, width: 12, height: 12))
                context.stroke(circle, with: .color(Theme.lane(0)), style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
                var line = Path()
                line.move(to: CGPoint(x: centre.x, y: centre.y + 6))
                line.addLine(to: CGPoint(x: centre.x, y: size.height))
                context.stroke(line, with: .color(Theme.lane(0)), style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
            }
            .frame(width: graphWidth)
            HStack(spacing: 8) {
                Text("// WIP").italic().foregroundStyle(.secondary)
                changeBadge(repo.unstaged.count + repo.staged.count, icon: "pencil", colour: .orange)
                if !repo.staged.isEmpty { changeBadge(repo.staged.count, icon: "checkmark", colour: .green) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(height: GraphView.rowHeight)
        .background(selected ? Theme.selection : (hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { repo.select(.wip) }
        .onHover { hovering = $0 }
    }

    private func changeBadge(_ count: Int, icon: String, colour: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 9))
            Text("\(count)")
        }
        .font(.system(size: 11))
        .foregroundStyle(colour)
    }
}

struct CommitRow: View {
    let repo: Repo
    let entry: GraphEntry
    let graphWidth: CGFloat

    static let refsWidth: CGFloat = 180
    static let authorWidth: CGFloat = 130
    static let dateWidth: CGFloat = 112

    @Environment(RepoStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let commit = entry.commit
        let selected = repo.selection == .commit(commit.id)

        HStack(spacing: 0) {
            RefsCell(commit: commit, laneColour: Theme.lane(entry.row.lane))
                .frame(width: Self.refsWidth, alignment: .leading)
            GraphCell(row: entry.row, commit: commit)
                .frame(width: graphWidth, height: GraphView.rowHeight)
                .clipped()
            Text(commit.subject)
                .fontWeight(commit.isHead ? .semibold : .regular)
                .foregroundStyle(commit.isMerge ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(commit.author)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.authorWidth, alignment: .leading)
            Text(Theme.dateFormatter.string(from: commit.date))
                .foregroundStyle(.secondary)
                .frame(width: Self.dateWidth, alignment: .leading)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(height: GraphView.rowHeight)
        .background(selected ? Theme.selection : (hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { repo.select(.commit(commit.id)) }
        .onHover { hovering = $0 }
        .contextMenu { menu(commit) }
    }

    @ViewBuilder
    private func menu(_ commit: Commit) -> some View {
        Button("Copy Commit SHA") { copy(commit.id) }
        Button("Copy Commit Message") { copy(commit.subject) }
        Divider()
        if commit.isHead {
            Button("Squash into Previous Commit") { Task { await repo.squashLastTwo() } }
            Button("Edit Message / Amend…") {
                repo.select(.wip)
                repo.amend = true
                if let message = repo.lastCommitMessage { repo.useMessage(message) }
            }
            Divider()
        }
        Button("Create Branch Here…") {
            store.newBranchStartPoint = commit.id
            store.showNewBranch = true
        }
        if !commit.isHead {
            Button("Cherry-pick Commit") { Task { await repo.cherryPick(commit.id) } }
        }
        Button("Revert Commit") { Task { await repo.revert(commit.id) } }
        if !commit.isHead {
            Menu("Reset \(repo.branch) to This Commit") {
                Button("Soft — keep changes staged") { Task { await repo.reset(to: commit.id, mode: "soft") } }
                Button("Mixed — keep changes unstaged") { Task { await repo.reset(to: commit.id, mode: "mixed") } }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Branch and tag labels for a commit. Local and remote branches with the same name are merged into one pill.
private struct RefsCell: View {
    let commit: Commit
    let laneColour: Color

    private struct Pill: Hashable {
        let text: String
        let icons: [String]
        let isHead: Bool
    }

    private var pills: [Pill] {
        let isHead = commit.isHead
        let locals = commit.refs.filter { $0.kind == .local }.map(\.name)
        var remotes = commit.refs.filter { $0.kind == .remote }.map(\.name)
        var pills: [Pill] = []

        for (index, local) in locals.enumerated() {
            var icons = ["laptopcomputer"]
            if let match = remotes.firstIndex(where: { $0.split(separator: "/", maxSplits: 1).last.map(String.init) == local }) {
                remotes.remove(at: match)
                icons.append("cloud")
            }
            // git lists the checked-out branch first after "HEAD ->".
            pills.append(Pill(text: local, icons: icons, isHead: isHead && index == 0))
        }
        pills += remotes.map { Pill(text: $0, icons: ["cloud"], isHead: false) }
        pills += commit.refs.filter { $0.kind == .tag }.map { Pill(text: $0.name, icons: ["tag"], isHead: false) }
        if isHead && locals.isEmpty { pills.insert(Pill(text: "HEAD", icons: ["exclamationmark.triangle"], isHead: true), at: 0) }
        return pills
    }

    var body: some View {
        let all = pills
        HStack(spacing: 4) {
            if let first = all.first {
                RefPill(text: first.text, icons: first.icons, colour: laneColour, bold: first.isHead)
                    .help(all.map(\.text).joined(separator: "\n"))
            }
            if all.count > 1 {
                Text("+\(all.count - 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(all.dropFirst().map(\.text).joined(separator: "\n"))
            }
        }
        .padding(.trailing, 6)
    }
}

/// Draws one row of the lane graph.
/// Ordinary commits show the author's avatar in the node; merges are a small dot.
private struct GraphCell: View {
    let row: GraphRow
    let commit: Commit

    private func x(_ lane: Int) -> CGFloat { CGFloat(lane) * GraphView.laneWidth + GraphView.laneWidth / 2 + 4 }

    var body: some View {
        let isMerge = commit.isMerge
        let isHead = commit.isHead
        Canvas { context, size in
            let mid = size.height / 2

            func segment(from start: CGPoint, to end: CGPoint, colour: Color) {
                var path = Path()
                path.move(to: start)
                if start.x == end.x {
                    path.addLine(to: end)
                } else {
                    let midY = (start.y + end.y) / 2
                    path.addCurve(to: end, control1: CGPoint(x: start.x, y: midY), control2: CGPoint(x: end.x, y: midY))
                }
                context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            for line in row.top {
                segment(from: CGPoint(x: x(line.from), y: 0), to: CGPoint(x: x(line.to), y: mid), colour: Theme.lane(line.from))
            }
            for line in row.bottom {
                segment(from: CGPoint(x: x(line.from), y: mid), to: CGPoint(x: x(line.to), y: size.height), colour: Theme.lane(line.to))
            }

            let colour = Theme.lane(row.lane)
            let radius: CGFloat = isMerge ? 4 : GraphView.avatarSize / 2 + 1.5
            let node = CGRect(x: x(row.lane) - radius, y: mid - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: node), with: .color(isMerge ? colour : Theme.background))
            context.stroke(Path(ellipseIn: node), with: .color(colour), lineWidth: isHead ? 3 : 2)
        }
        .overlay(alignment: .leading) {
            if !isMerge {
                AvatarView(name: commit.author, email: commit.email, size: GraphView.avatarSize)
                    .offset(x: x(row.lane) - GraphView.avatarSize / 2)
            }
        }
    }
}
