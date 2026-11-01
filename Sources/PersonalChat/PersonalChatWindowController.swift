import AppKit
import SwiftUI

@MainActor
final class PersonalChatWindowController: NSWindowController {
    private let model: PersonalChatModel

    init(openTerminal: @escaping (String) -> Void) {
        PersonalChatTypography.register()
        let sourceURL = Bundle.main.url(forResource: "personal-bridge", withExtension: "py")
        let source = sourceURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/cmux-personal/config.json")
        model = PersonalChatModel(service: PersonalChatService(source: source), repository: PersonalChatRepository(file: file))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "cmux Personal"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PersonalChatView(model: model, openTerminal: openTerminal))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if model.connected && model.selectedID != nil { model.startRefresh() }
        window?.makeKeyAndOrderFront(sender)
    }
}
