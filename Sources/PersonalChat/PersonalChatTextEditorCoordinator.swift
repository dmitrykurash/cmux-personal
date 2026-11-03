import AppKit

@MainActor
final class PersonalChatTextEditorCoordinator: NSObject, NSTextViewDelegate {
    var parent: PersonalChatTextEditor

    init(parent: PersonalChatTextEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        parent.text = textView.string
        textView.invalidateIntrinsicContentSize()
        textView.enclosingScrollView?.needsLayout = true
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        // These are local editor semantics. Preserve IME composition and the
        // standard modified-Return newline, without intercepting app shortcuts.
        guard !modifiers.contains(.shift), !modifiers.contains(.option), !modifiers.contains(.control), !modifiers.contains(.command) else { return false }
        if parent.canSubmit { parent.submit() }
        return true
    }
}
