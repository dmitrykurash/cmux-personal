import AppKit

/// A lightweight executable of the same native chat UI for verification with
/// Command Line Tools. The full cmux build opens its own Ghostty terminal;
/// this standalone preview uses Terminal.app only for that escape hatch.
@main
struct PersonalChatPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "personal.quit", defaultValue: "Quit cmux Personal"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        app.mainMenu = menu
        let controller = PersonalChatWindowController { command in
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-personal-terminal")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let script = folder.appendingPathComponent(UUID().uuidString + ".command")
                // No credentials are in this command. Remove the launch file as
                // soon as Terminal opens it; exec preserves the SSH exit code.
                try ("#!/bin/sh\nrm -- \"$0\"\nexec " + command + "\n").write(to: script, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
                NSWorkspace.shared.open(script)
            } catch { NSAlert(error: error).runModal() }
        }
        controller.showWindow(nil)
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(controller) { app.run() }
    }
}
