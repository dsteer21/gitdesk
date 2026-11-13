import SwiftUI

@main
struct GitDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = RepoStore()

    var body: some Scene {
        Window("GitDesk", id: "main") {
            MainView()
                .environment(store)
                .frame(minWidth: 1100, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Clone Repository…") { store.showClone = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Add Repository…") { store.promptAddRepository() }
                    .keyboardShortcut("o")
                Button("Scan Folder for Repositories…") { store.promptScanFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Repository") {
                Button("Command Palette…") { store.showPalette.toggle() }
                    .keyboardShortcut("p")
                Divider()
                Button("Pull") { Task { await store.selected?.pull() } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                Button("Push") { Task { await store.selected?.push() } }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Fetch") { Task { await store.selected?.fetch() } }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Pull All Repositories") { Task { await store.pullAll() } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
                Button("New Branch…") { store.showNewBranch = true }
                    .keyboardShortcut("b")
                    .disabled(store.selected == nil)
                Button("Stash Changes") { Task { await store.selected?.stash() } }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Pop Stash") { Task { await store.selected?.popStash() } }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Divider()
                Button("Stage All Changes") { Task { await store.selected?.stageAll() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Use Last Commit Message") {
                    if let repo = store.selected, let message = repo.lastCommitMessage {
                        repo.select(.wip)
                        repo.useMessage(message)
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Refresh") {
                    Task {
                        await store.selected?.refresh()
                        await store.refreshAllStatuses()
                    }
                }
                .keyboardShortcut("r")
                Button("All Repositories") { store.selectedID = nil }
                    .keyboardShortcut("0")
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        scheduleSnapshotIfRequested()
        SelfTest.runIfRequested()
        #endif
    }

    #if DEBUG
    /// Development aid: `GITDESK_SNAPSHOT=/path/shot.png swift run` saves the window to a PNG after a few seconds.
    private func scheduleSnapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["GITDESK_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["GITDESK_SNAPSHOT_DELAY"] ?? "") ?? 4
        // GITDESK_SNAPSHOT_TYPE="text": open the palette and type into whatever has keyboard focus.
        if let typed = ProcessInfo.processInfo.environment["GITDESK_SNAPSHOT_TYPE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay - 2) {
                NotificationCenter.default.post(name: .debugOpenPalette, object: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay - 1) {
                let responder = NSApp.keyWindow?.firstResponder
                print("first responder:", responder.map { String(describing: type(of: $0)) } ?? "none")
                (responder as? NSTextView)?.insertText(typed, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
        // GITDESK_SNAPSHOT_DIFF="path/in/repo": open that file's unstaged diff.
        if let path = ProcessInfo.processInfo.environment["GITDESK_SNAPSHOT_DIFF"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay - 2) {
                NotificationCenter.default.post(name: .debugOpenDiff, object: path)
            }
        }
        // GITDESK_SNAPSHOT_COMMIT_PROMPT=1: open the ⌘P "Commit & Push…" prompt; the snapshot is of the sheet.
        if ProcessInfo.processInfo.environment["GITDESK_SNAPSHOT_COMMIT_PROMPT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay - 2) {
                NotificationCenter.default.post(name: .debugOpenCommitPrompt, object: nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let main = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })
            let sheet = main?.attachedSheet
            guard let view = (sheet ?? main)?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            // An open sheet would stop the app quitting. (Sheet snapshots come out pale: their
            // translucent background isn't captured, but the sheet itself is dark.)
            if let sheet { sheet.sheetParent?.endSheet(sheet) }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct SettingsView: View {
    @AppStorage("useGravatar") private var useGravatar = true
    @AppStorage("pullMode") private var pullMode: PullMode = .merge
    @AppStorage("cloneFolder") private var cloneFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sites").path

    var body: some View {
        Form {
            Picker("Pull button", selection: $pullMode) {
                ForEach(PullMode.allCases) { Text($0.title).tag($0) }
            }
            TextField("Default clone folder", text: $cloneFolder)
            Toggle("Show Gravatar avatars", isOn: $useGravatar)
            Text("Looks up commit authors' email addresses (hashed) on Gravatar. When off, initials are shown instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Pull All always uses fast-forward only, so it never creates merge commits or conflicts across your repositories.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("git", value: Git.executable)
        }
        .padding(20)
        .frame(width: 480)
    }
}

#if DEBUG
extension Notification.Name {
    static let debugOpenPalette = Notification.Name("GitDesk.debugOpenPalette")
    static let debugOpenDiff = Notification.Name("GitDesk.debugOpenDiff")
    static let debugOpenCommitPrompt = Notification.Name("GitDesk.debugOpenCommitPrompt")
}
#endif
