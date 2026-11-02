import Foundation

struct StatusSnapshot {
    var branch = ""
    var upstream: String?
    var ahead = 0
    var behind = 0
    var hasCommits = true
    var staged: [FileChange] = []
    var unstaged: [FileChange] = []
}

/// Parsers for git's machine-readable output formats.
enum GitParse {
    static let fieldSeparator: Character = "\u{1f}"
    static let recordSeparator: Character = "\u{1e}"

    /// `git log --format=` string matching `commits(_:)`.
    static let logFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1e"

    /// `git for-each-ref --format=` string matching `branches(_:)`.
    static let refFormat = "%(refname)%1f%(refname:short)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(HEAD)"

    static func commits(_ output: String) -> [Commit] {
        output.split(separator: recordSeparator).compactMap { record in
            let fields = record.trimmingCharacters(in: .newlines)
                .split(separator: fieldSeparator, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count >= 7, !fields[0].isEmpty else { return nil }
            return Commit(
                id: fields[0],
                parents: fields[1].split(separator: " ").map(String.init),
                author: fields[2],
                email: fields[3],
                date: Date(timeIntervalSince1970: TimeInterval(fields[4]) ?? 0),
                refs: refs(fields[5]),
                subject: fields[6...].joined(separator: " ")
            )
        }
    }

    /// Parses a `--decorate=full` ref list, e.g. "HEAD -> refs/heads/master, refs/remotes/origin/master, tag: refs/tags/v1".
    static func refs(_ decoration: String) -> [RefLabel] {
        var labels: [RefLabel] = []
        for raw in decoration.components(separatedBy: ", ") where !raw.isEmpty {
            var item = raw
            if item.hasPrefix("HEAD -> ") {
                labels.append(RefLabel(name: "HEAD", kind: .head))
                item = String(item.dropFirst(8))
            } else if item == "HEAD" {
                labels.append(RefLabel(name: "HEAD", kind: .head))
                continue
            }
            if item.hasPrefix("tag: ") { item = String(item.dropFirst(5)) }

            if item.hasPrefix("refs/heads/") {
                labels.append(RefLabel(name: String(item.dropFirst(11)), kind: .local))
            } else if item.hasPrefix("refs/remotes/") {
                guard !item.hasSuffix("/HEAD") else { continue }
                labels.append(RefLabel(name: String(item.dropFirst(13)), kind: .remote))
            } else if item.hasPrefix("refs/tags/") {
                labels.append(RefLabel(name: String(item.dropFirst(10)), kind: .tag))
            }
        }
        return labels
    }

    /// Parses `git status --porcelain=v2 --branch -z`.
    static func status(_ output: String) -> StatusSnapshot {
        var snapshot = StatusSnapshot()
        let parts = output.components(separatedBy: "\0")
        var i = 0
        while i < parts.count {
            let line = parts[i]
            i += 1
            guard let kind = line.first else { continue }

            switch kind {
            case "#":
                if line.hasPrefix("# branch.oid ") {
                    snapshot.hasCommits = !line.hasSuffix("(initial)")
                } else if line.hasPrefix("# branch.head ") {
                    snapshot.branch = String(line.dropFirst(14))
                } else if line.hasPrefix("# branch.upstream ") {
                    snapshot.upstream = String(line.dropFirst(18))
                } else if line.hasPrefix("# branch.ab ") {
                    let numbers = line.dropFirst(12).split(separator: " ")
                    if numbers.count == 2 {
                        snapshot.ahead = Int(numbers[0].dropFirst()) ?? 0
                        snapshot.behind = Int(numbers[1].dropFirst()) ?? 0
                    }
                }

            case "1", "2", "u":
                // Ordinary (1), renamed/copied (2) and unmerged (u) entries have a fixed number of fields before the path.
                let fieldCount = kind == "1" ? 8 : (kind == "2" ? 9 : 10)
                let fields = line.split(separator: " ", maxSplits: fieldCount, omittingEmptySubsequences: false)
                guard fields.count == fieldCount + 1 else { continue }
                let xy = Array(fields[1])
                let path = String(fields[fieldCount])

                var original: String?
                if kind == "2", i < parts.count {
                    original = parts[i]
                    i += 1
                }
                if kind == "u" {
                    snapshot.unstaged.append(FileChange(path: path, originalPath: nil, status: "U"))
                    continue
                }
                if xy.count == 2 {
                    if xy[0] != "." { snapshot.staged.append(FileChange(path: path, originalPath: original, status: xy[0])) }
                    if xy[1] != "." { snapshot.unstaged.append(FileChange(path: path, originalPath: nil, status: xy[1])) }
                }

            case "?":
                snapshot.unstaged.append(FileChange(path: String(line.dropFirst(2)), originalPath: nil, status: "?"))

            default:
                break
            }
        }
        snapshot.staged.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        snapshot.unstaged.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return snapshot
    }

    static func branches(_ output: String) -> (local: [Branch], remote: [Branch], tags: [String]) {
        var local: [Branch] = [], remote: [Branch] = [], tags: [String] = []
        for line in output.split(separator: "\n") {
            let f = line.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5 else { continue }
            let fullName = f[0]
            if fullName.hasPrefix("refs/heads/") {
                local.append(Branch(fullName: fullName, name: f[1], upstream: f[2].isEmpty ? nil : f[2],
                                    track: f[3], isHead: f[4] == "*", isRemote: false))
            } else if fullName.hasPrefix("refs/remotes/") {
                guard !fullName.hasSuffix("/HEAD") else { continue }
                remote.append(Branch(fullName: fullName, name: f[1], upstream: nil, track: "", isHead: false, isRemote: true))
            } else if fullName.hasPrefix("refs/tags/") {
                tags.append(f[1])
            }
        }
        return (local, remote, tags)
    }

    static func stashes(_ output: String) -> [Stash] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: fieldSeparator, maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 2 else { return nil }
            return Stash(ref: f[0], message: f[1])
        }
    }

    /// Parses `--name-status -z` output (from `git diff` or `git diff-tree`).
    static func nameStatus(_ output: String) -> [FileChange] {
        let tokens = output.components(separatedBy: "\0").filter { !$0.isEmpty }
        var files: [FileChange] = []
        var i = 0
        while i < tokens.count {
            let code = tokens[i]
            i += 1
            guard let status = code.first else { continue }
            if status == "R" || status == "C" {
                guard i + 1 < tokens.count else { break }
                files.append(FileChange(path: tokens[i + 1], originalPath: tokens[i], status: status))
                i += 2
            } else {
                guard i < tokens.count else { break }
                files.append(FileChange(path: tokens[i], originalPath: nil, status: status))
                i += 1
            }
        }
        return files
    }

    /// Parses a unified diff into display lines with old/new line numbers.
    static func diff(_ output: String, limit: Int = 8000) -> (lines: [DiffLine], truncated: Bool) {
        var lines: [DiffLine] = []
        var oldNumber = 0, newNumber = 0
        var inHunk = false

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if lines.count >= limit { return (lines, true) }
            let text = String(raw)
            let id = lines.count

            if text.hasPrefix("diff --git") {
                inHunk = false
                continue
            }
            if text.hasPrefix("@@") {
                inHunk = true
                // "@@ -a,b +c,d @@ context"
                let parts = text.split(separator: " ")
                if parts.count >= 3 {
                    oldNumber = Int(parts[1].dropFirst().split(separator: ",").first ?? "") ?? 0
                    newNumber = Int(parts[2].dropFirst().split(separator: ",").first ?? "") ?? 0
                }
                lines.append(DiffLine(id: id, kind: .hunk, text: text, oldNumber: nil, newNumber: nil))
                continue
            }
            if !inHunk {
                // File headers: only surface the ones a human cares about.
                if text.hasPrefix("Binary files") || text.hasPrefix("new file mode") || text.hasPrefix("deleted file mode")
                    || text.hasPrefix("rename from") || text.hasPrefix("rename to") {
                    lines.append(DiffLine(id: id, kind: .meta, text: text, oldNumber: nil, newNumber: nil))
                }
                continue
            }
            switch text.first {
            case "+":
                lines.append(DiffLine(id: id, kind: .add, text: String(text.dropFirst()), oldNumber: nil, newNumber: newNumber))
                newNumber += 1
            case "-":
                lines.append(DiffLine(id: id, kind: .delete, text: String(text.dropFirst()), oldNumber: oldNumber, newNumber: nil))
                oldNumber += 1
            case "\\":
                lines.append(DiffLine(id: id, kind: .meta, text: text, oldNumber: nil, newNumber: nil))
            case " ":
                lines.append(DiffLine(id: id, kind: .context, text: String(text.dropFirst()), oldNumber: oldNumber, newNumber: newNumber))
                oldNumber += 1
                newNumber += 1
            default:
                break
            }
        }
        return (lines, false)
    }
}
