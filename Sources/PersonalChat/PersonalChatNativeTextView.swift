import AppKit

/// Reports real responder focus without global event monitors or key bindings.
@MainActor
final class PersonalChatNativeTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?

    func fittingSize(width proposedWidth: CGFloat?) -> CGSize? {
        guard let container = textContainer, let layout = layoutManager else { return nil }
        let width = max(1, proposedWidth ?? 600)
        setFrameSize(NSSize(width: width, height: max(28, frame.height)))
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height) + 4
        setFrameSize(NSSize(width: width, height: max(28, height)))
        return CGSize(width: width, height: min(240, max(28, height)))
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
