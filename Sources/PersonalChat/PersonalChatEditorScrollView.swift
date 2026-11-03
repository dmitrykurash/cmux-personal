import AppKit

/// Only the committed viewport, never a SwiftUI sizing proposal, owns wrapping.
@MainActor
final class PersonalChatEditorScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let editor = documentView as? PersonalChatNativeTextView else { return }
        let width = contentView.bounds.width
        guard width.isFinite, width > 0 else { return }
        let size = NSSize(width: width, height: max(contentView.bounds.height, editor.measuredHeight(width: width)))
        if editor.frame.size != size { editor.setFrameSize(size) }
    }
}
