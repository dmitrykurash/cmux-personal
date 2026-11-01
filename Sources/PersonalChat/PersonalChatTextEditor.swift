import AppKit
import SwiftUI

/// A real macOS editor that grows with wrapped text, then scrolls at a bounded height.
struct PersonalChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool
    var canSubmit: Bool
    var label: String
    var textColor: NSColor
    var insertionColor: NSColor
    var focusChanged: (Bool) -> Void
    var submit: () -> Void

    func makeCoordinator() -> PersonalChatTextEditorCoordinator {
        PersonalChatTextEditorCoordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let editor = PersonalChatNativeTextView(frame: .zero)
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.font = .systemFont(ofSize: 15)
        editor.textContainerInset = NSSize(width: 0, height: 8)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        editor.defaultParagraphStyle = paragraph
        editor.setAccessibilityIdentifier("personal.composer.editor")
        // The surrounding composer owns file drops as attachments.
        editor.unregisterDraggedTypes()
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PersonalChatNativeTextView else { return }
        if !editor.hasMarkedText(), editor.string != text { editor.string = text }
        editor.isEditable = editable
        editor.textColor = textColor
        editor.insertionPointColor = insertionColor
        editor.setAccessibilityLabel(label)
        editor.focusChanged = focusChanged
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let editor = scroll.documentView as? NSTextView,
              let container = editor.textContainer, let layout = editor.layoutManager else { return nil }
        let width = max(1, proposal.width ?? 600)
        editor.setFrameSize(NSSize(width: width, height: max(52, editor.frame.height)))
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height) + 18
        editor.setFrameSize(NSSize(width: width, height: max(52, height)))
        return CGSize(width: width, height: min(180, max(52, height)))
    }
}
