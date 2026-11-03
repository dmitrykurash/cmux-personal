import AppKit

/// Reports real responder focus without global event monitors or key bindings.
@MainActor
final class PersonalChatNativeTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?

    /// SwiftUI probes several widths in one layout pass. Measure a separate
    /// text system; a proposal must never reflow the editor the user is typing in.
    func fittingSize(width: CGFloat?) -> CGSize? {
        guard let width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: min(240, measuredHeight(width: width)))
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: attributedString())
        if storage.length == 0 { storage.setAttributedString(NSAttributedString(string: " ", attributes: typingAttributes)) }
        let container = NSTextContainer(containerSize: NSSize(width: max(1, width - 2 * textContainerInset.width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let bottom = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        return max(28, ceil(bottom + 2 * textContainerInset.height))
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }
        return accepted
    }
}
