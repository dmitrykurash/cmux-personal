import AppKit
import SwiftUI

/// The same native chat UI with the standard macOS editing/menu commands.
/// The full cmux build opens Ghostty; this preview uses Terminal.app.
@main
struct PersonalChatPreview: App {
    @State private var model: PersonalChatModel

    init() {
        PersonalChatTypography.register()
        let url = Bundle.main.url(forResource: "personal-bridge", withExtension: "py")
        let source = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/cmux-personal/config.json")
        _model = State(initialValue: PersonalChatModel(service: PersonalChatService(source: source), repository: PersonalChatRepository(file: file)))
    }

    var body: some Scene {
        WindowGroup("cmux Personal") {
            PersonalChatView(model: model, openTerminal: Self.openTerminal)
        }
        .defaultSize(width: 1320, height: 860)
        .windowStyle(.hiddenTitleBar)
    }

    @MainActor private static func openTerminal(_ command: String) {
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-personal-terminal")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let script = folder.appendingPathComponent(UUID().uuidString + ".command")
            // No credentials are in the command. Delete the launcher on open.
            try ("#!/bin/sh\nrm -- \"$0\"\nexec " + command + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch { NSAlert(error: error).runModal() }
    }
}
