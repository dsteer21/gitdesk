import Foundation

struct Commit: Identifiable, Hashable {
    let id: String
    let parents: [String]
    let author: String
    let email: String
    let date: Date
    let refs: [RefLabel]
    let subject: String

    var shortID: String { String(id.prefix(7)) }
    var isMerge: Bool { parents.count > 1 }
    var isHead: Bool { refs.contains { $0.kind == .head } }
}

struct RefLabel: Hashable {
    enum Kind { case head, local, remote, tag }
    let name: String
    let kind: Kind
}

struct FileChange: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let originalPath: String?
    /// Single-letter git status: M, A, D, R, C, T, U (conflict) or ? (untracked).
    let status: Character

    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

struct Branch: Identifiable, Hashable {
    var id: String { fullName }
    let fullName: String
    let name: String
    let upstream: String?
    /// e.g. "ahead 1, behind 2", "gone" or empty.
    let track: String
    let isHead: Bool
    let isRemote: Bool
}

struct Stash: Identifiable, Hashable {
    var id: String { ref }
    let ref: String
    let message: String
}

struct CommitDetail {
    let commit: Commit
    let message: String
    let files: [FileChange]
    var parent: String? { commit.parents.first }
}

enum GraphSelection: Hashable {
    case wip
    case commit(String)
}

enum DiffSource: Hashable {
    case unstaged
    case staged
    case commit(hash: String, parent: String?)
}

struct DiffLine: Identifiable {
    enum Kind { case hunk, add, delete, context, meta }
    let id: Int
    let kind: Kind
    let text: String
    let oldNumber: Int?
    let newNumber: Int?
}

struct DiffState {
    let file: FileChange
    let source: DiffSource
    var lines: [DiffLine] = []
    var isLoading = true
    var truncated = false
}

enum PullMode: String, CaseIterable, Identifiable {
    case merge, ffOnly, rebase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: "Fast-forward if possible"
        case .ffOnly: "Fast-forward only"
        case .rebase: "Rebase"
        }
    }

    var args: [String] {
        switch self {
        case .merge: ["pull", "--no-rebase"]
        case .ffOnly: ["pull", "--ff-only"]
        case .rebase: ["pull", "--rebase", "--autostash"]
        }
    }

    static var current: PullMode {
        PullMode(rawValue: UserDefaults.standard.string(forKey: "pullMode") ?? "") ?? .merge
    }
}

/// Result of the last bulk operation (Pull All / Fetch All) on a repository.
struct Outcome {
    enum Kind { case updated, upToDate, failed, skipped }
    let kind: Kind
    let message: String
    let date = Date()
}

/// One row of the commit graph: the commit and how to draw its lanes.
struct GraphEntry: Identifiable {
    var id: String { commit.id }
    let commit: Commit
    let row: GraphRow
}
