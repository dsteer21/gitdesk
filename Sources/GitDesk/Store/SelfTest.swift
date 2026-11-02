#if DEBUG
import AppKit

/// Development aid: `GITDESK_SELFTEST=/path/to/clone swift run` drives the main
/// workflows through `Repo` against a throwaway clone and prints the results.
@MainActor
enum SelfTest {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["GITDESK_SELFTEST"] else { return }
        Task {
            await run(URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }

    private static func check(_ label: String, _ condition: Bool) {
        print(condition ? "PASS" : "FAIL", label)
    }

    private static func shell(_ args: [String], in url: URL) async -> String {
        (try? await Git.run(args, in: url, ok: [0, 1, 128]).stdout.trimmed) ?? ""
    }

    private static func run(_ url: URL) async {
        let repo = Repo(url: url)
        await repo.refresh()
        check("loads history", !repo.entries.isEmpty && repo.branch == "master")

        // 1. Stage-all & commit & push in one go.
        try? "first\n".write(to: url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        await repo.refreshStatus()
        repo.draftSummary = "[GIT-9001] First push"
        await repo.commit(andPush: true)
        check("commit & push leaves nothing ahead", repo.ahead == 0 && repo.changeCount == 0)
        check("HEAD is marked pushed", repo.headIsPushed)
        check("last message available for reuse", repo.lastCommitMessage == "[GIT-9001] First push")

        // 2. Second round: amend the pushed commit, which must force-push with lease.
        try? "second\n".write(to: url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        await repo.refreshStatus()
        repo.amend = true
        if let message = repo.lastCommitMessage { repo.useMessage(message) }
        check("reuse message fills summary", repo.draftSummary == "[GIT-9001] First push")
        let headBefore = await shell(["rev-parse", "HEAD"], in: url)
        await repo.commit(andPush: true)
        let headAfter = await shell(["rev-parse", "HEAD"], in: url)
        let remoteHead = await shell(["rev-parse", "@{u}"], in: url)
        check("amend rewrote HEAD", headBefore != headAfter)
        check("amend + push updated remote (force with lease)", remoteHead == headAfter && !repo.pendingForcePush)
        check("message history recorded", MessageHistory.all.first == "[GIT-9001] First push")

        // 3. Squash last two commits.
        try? "third\n".write(to: url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        await repo.refreshStatus()
        repo.draftSummary = "[GIT-9001] Follow-up"
        await repo.commit(andPush: false)
        let countBefore = Int(await shell(["rev-list", "--count", "HEAD"], in: url)) ?? 0
        await repo.squashLastTwo()
        let countAfter = Int(await shell(["rev-list", "--count", "HEAD"], in: url)) ?? 0
        check("squash removed one commit", countAfter == countBefore - 1)
        check("squash kept previous message", await shell(["log", "-1", "--format=%s"], in: url) == "[GIT-9001] First push")
        check("squash of pushed commit flags force push", repo.pendingForcePush)
        await repo.push()
        check("push after squash succeeded", await shell(["rev-parse", "@{u}"], in: url) == (await shell(["rev-parse", "HEAD"], in: url)))

        // 4. Stash and pop.
        try? "stash me\n".write(to: url.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        await repo.refreshStatus()
        await repo.stash()
        check("stash cleaned working tree", repo.changeCount == 0 && repo.stashes.count == 1)
        await repo.popStash()
        check("pop restored changes", repo.changeCount == 1 && repo.stashes.isEmpty)
        await repo.discard(repo.unstaged)
        check("discard removed untracked file", repo.changeCount == 0)

        // 5. Branch create / checkout.
        await repo.createBranch("feature/test")
        check("created and checked out branch", repo.branch == "feature/test")
        if let master = repo.localBranches.first(where: { $0.name == "master" }) { await repo.checkout(master) }
        check("checked out master again", repo.branch == "master")

        // 6. Bulk pull: reset local back one commit behind the remote, then pull.
        _ = await shell(["reset", "--hard", "HEAD~1"], in: url)
        await repo.refreshStatus()
        check("now behind remote", repo.behind == 1)
        await repo.pullForBulk()
        check("pull-all fast-forwarded (\(repo.lastOutcome?.message ?? "-"))", repo.lastOutcome?.kind == .updated && repo.behind == 0)
        await repo.pullForBulk()
        check("second pull-all is up to date", repo.lastOutcome?.kind == .upToDate)

        print("SELFTEST DONE")
    }
}
#endif
