import SwiftUI

/// Replaces the graph while a file diff is open (like GitKraken). Esc closes it.
struct DiffView: View {
    let repo: Repo

    var body: some View {
        if let diff = repo.diff {
            VStack(spacing: 0) {
                header(diff)
                Divider()
                if diff.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if diff.lines.isEmpty {
                    ContentUnavailableView("No textual changes", systemImage: "doc.text.magnifyingglass",
                                           description: Text("The file may be binary, empty, or only have mode changes."))
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(diff.lines) { line in
                                DiffLineView(line: line)
                            }
                            if diff.truncated {
                                Text("Diff truncated — open the file to see the rest.")
                                    .font(.caption).foregroundStyle(.secondary).padding()
                            }
                        }
                        .frame(minWidth: 600, alignment: .leading)
                    }
                }
            }
            .background(Theme.background)
        }
    }

    private func header(_ diff: DiffState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Theme.statusIcon(diff.file.status)).foregroundStyle(Theme.statusColour(diff.file.status))
            VStack(alignment: .leading, spacing: 1) {
                Text(diff.file.fileName).font(.system(size: 13, weight: .semibold))
                Text(diff.file.originalPath.map { "\($0) → \(diff.file.path)" } ?? diff.file.path)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            switch diff.source {
            case .unstaged:
                Button("Stage File") { Task { await repo.stage([diff.file]) } }
            case .staged:
                Button("Unstage File") { Task { await repo.unstage([diff.file]) } }
            case .commit:
                EmptyView()
            }
            Button("Open File") { NSWorkspace.shared.open(repo.url.appendingPathComponent(diff.file.path)) }
            Button {
                repo.diff = nil
            } label: {
                Image(systemName: "xmark")
            }
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close diff (Esc)")
        }
        .controlSize(.small)
        .padding(10)
        .background(Theme.panel)
    }
}

private struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(marker)
                .frame(width: 16)
                .foregroundStyle(foreground)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .hunk || line.kind == .meta ? .secondary : .primary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(height: 18)
        .background(background)
        .textSelection(.enabled)
    }

    private var marker: String {
        switch line.kind {
        case .add: "+"
        case .delete: "-"
        default: ""
        }
    }

    private var foreground: Color {
        switch line.kind {
        case .add: .green
        case .delete: .red
        default: .secondary
        }
    }

    private var background: Color {
        switch line.kind {
        case .add: Color.green.opacity(0.15)
        case .delete: Color.red.opacity(0.15)
        case .hunk: Color.blue.opacity(0.12)
        default: .clear
        }
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(.tertiary)
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 6)
    }
}
