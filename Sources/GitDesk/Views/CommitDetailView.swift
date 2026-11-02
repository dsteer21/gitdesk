import SwiftUI

/// Right panel when a commit is selected: its message, metadata and changed files.
struct CommitDetailView: View {
    let repo: Repo

    var body: some View {
        if let detail = repo.commitDetail {
            let commit = detail.commit
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("commit:").foregroundStyle(.secondary)
                        Text(commit.shortID).font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(commit.id, forType: .string)
                            Banner.shared.info("Copied \(commit.shortID)")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy full SHA")
                    }
                    .font(.system(size: 12))

                    Text(detail.message)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 24)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(commit.author).font(.system(size: 12, weight: .semibold))
                            Text("authored \(Theme.dateFormatter.string(from: commit.date))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if !commit.parents.isEmpty {
                        HStack {
                            Text(commit.isMerge ? "parents:" : "parent:").foregroundStyle(.secondary)
                            ForEach(commit.parents, id: \.self) { parent in
                                Button(String(parent.prefix(7))) { repo.select(.commit(parent)) }
                                    .buttonStyle(.link)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(12)
                .background(Theme.panel)

                Divider()

                HStack {
                    SectionHeader(title: "Changed Files", count: detail.files.count)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(detail.files) { file in
                            let source = DiffSource.commit(hash: commit.id, parent: detail.parent)
                            FileRow(file: file,
                                    selected: repo.diff?.file.path == file.path && repo.diff?.source == source,
                                    open: { repo.showDiff(file, source: source) })
                        }
                    }
                }
            }
            .background(Theme.background)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
    }
}
