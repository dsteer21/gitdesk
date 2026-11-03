import SwiftUI

/// ⌘P: fuzzy search over actions, repositories and branches.
struct CommandPalette: View {
    @Environment(RepoStore.self) private var store
    @State private var query = ""
    @State private var highlighted = 0
    @State private var items: [RepoStore.PaletteItem] = []
    @FocusState private var focused: Bool

    /// Items containing every typed word win; loose fuzzy matching is only a fallback.
    private var results: [RepoStore.PaletteItem] {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return items }
        let words = trimmed.split(separator: " ").map(String.init)
        let text = { (item: RepoStore.PaletteItem) in item.title + " " + item.subtitle }

        let exact = items.filter { item in words.allSatisfy { text(item).localizedCaseInsensitiveContains($0) } }
        return (exact.isEmpty ? items : exact)
            .compactMap { item in Fuzzy.score(trimmed, in: text(item)).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        let results = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search actions, repositories and branches…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($focused)
                        .onSubmit { run(results) }
                        .onKeyPress(.downArrow) {
                            highlighted = min(highlighted + 1, max(results.count - 1, 0))
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            highlighted = max(highlighted - 1, 0)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            close()
                            return .handled
                        }
                }
                .padding(14)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.prefix(60).enumerated()), id: \.element.id) { index, item in
                                // Identify rows by item, not position, or SwiftUI keeps showing stale rows as the list filters.
                                row(item, highlighted: index == highlighted)
                                    .id(item.id)
                                    .onTapGesture {
                                        highlighted = index
                                        run(results)
                                    }
                            }
                            if results.isEmpty {
                                Text("No matches").foregroundStyle(.secondary).padding(20)
                            }
                        }
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: highlighted) { _, index in
                        if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                    }
                }
            }
            .frame(width: 600)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel).shadow(radius: 24))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 70)
        }
        .onAppear {
            items = store.paletteItems()
            focused = true
        }
        .onChange(of: query) { highlighted = 0 }
    }

    private func row(_ item: RepoStore.PaletteItem, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon).frame(width: 20).foregroundStyle(.secondary)
            Text(item.title).font(.system(size: 13))
            Spacer()
            Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(highlighted ? Theme.selection : .clear)
        .contentShape(Rectangle())
    }

    private func run(_ results: [RepoStore.PaletteItem]) {
        guard results.indices.contains(highlighted) else { return }
        let item = results[highlighted]
        close()
        item.action()
    }

    private func close() {
        store.showPalette = false
    }
}
