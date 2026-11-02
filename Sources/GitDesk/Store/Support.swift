import Foundation
import Observation

/// Transient toast messages shown at the bottom of the window.
@MainActor @Observable
final class Banner {
    static let shared = Banner()

    struct Item: Identifiable {
        let id = UUID()
        let text: String
        let detail: String?
        let isError: Bool
    }

    var current: Item?

    func info(_ text: String) { show(Item(text: text, detail: nil, isError: false)) }

    func error(_ text: String, detail: String? = nil) { show(Item(text: text, detail: detail, isError: true)) }

    private func show(_ item: Item) {
        current = item
        Task {
            try? await Task.sleep(for: .seconds(item.isError ? 10 : 3))
            if current?.id == item.id { current = nil }
        }
    }
}

/// Recently used commit messages, shared across all repositories so the same
/// message (e.g. a task ID) can be reused when committing to several repos.
@MainActor
enum MessageHistory {
    private static let key = "recentCommitMessages"
    private static let limit = 15

    static var all: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ message: String) {
        var messages = all.filter { $0 != message }
        messages.insert(message, at: 0)
        UserDefaults.standard.set(Array(messages.prefix(limit)), forKey: key)
    }
}

/// Simple fuzzy matcher for the command palette: every query character must
/// appear in order. Higher scores for prefix, word-start and contiguous matches.
enum Fuzzy {
    static func score(_ query: String, in text: String) -> Int? {
        let query = query.lowercased().filter { !$0.isWhitespace }
        guard !query.isEmpty else { return 0 }
        let haystack = Array(text.lowercased())
        var score = 0
        var position = 0
        var previous: Int?

        for character in query {
            guard let found = haystack[position...].firstIndex(of: character) else { return nil }
            score += 1
            if found == 0 { score += 8 }
            if found > 0, " /-_.:".contains(haystack[found - 1]) { score += 5 }
            if let previous, found == previous + 1 { score += 4 }
            previous = found
            position = found + 1
        }
        if text.lowercased().contains(query) { score += 15 }
        return score - haystack.count / 12
    }
}
