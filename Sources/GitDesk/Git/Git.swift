import Foundation

/// An error raised by a git command, carrying git's own message.
struct GitError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct GitResult: Sendable {
    let stdout: String
    let stderr: String
    let status: Int32
}

/// Thin wrapper around the git command-line tool.
///
/// Everything goes through the user's own git install, so SSH keys, the
/// macOS Keychain credential helper and global config all behave exactly as
/// they do in the terminal.
enum Git {
    /// Prefer Homebrew's git when present (usually newer), else Apple's.
    static let executable: String = {
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }()

    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a minimal PATH; make sure helpers (git-lfs, ssh, gpg) resolve.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        // Never block waiting on a terminal prompt or an editor - there isn't one.
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_EDITOR"] = "true"
        // Don't take optional locks during background status refreshes.
        env["GIT_OPTIONAL_LOCKS"] = "0"
        return env
    }()

    /// Runs git with `args` in `directory`. Throws unless the exit status is in `ok`.
    @discardableResult
    static func run(_ args: [String], in directory: URL?, ok: Set<Int32> = [0]) async throws -> GitResult {
        let fullArgs = ["-c", "core.quotepath=false", "-c", "color.ui=false"] + args
        let result: GitResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runSync(fullArgs, in: directory))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        guard ok.contains(result.status) else {
            let text = (result.stderr.isEmpty ? result.stdout : result.stderr)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError(message: text.isEmpty ? "git \(args.first ?? "") exited with status \(result.status)" : text)
        }
        return result
    }

    private final class DataBox: @unchecked Sendable { var data = Data() }

    private static func runSync(_ args: [String], in directory: URL?) throws -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = environment
        if let directory { process.currentDirectoryURL = directory }

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Drain stderr on a second thread so neither pipe can fill up and stall git.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return GitResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errBox.data, as: UTF8.self),
            status: process.terminationStatus
        )
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
