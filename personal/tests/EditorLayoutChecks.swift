import AppKit

@main struct EditorLayoutChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let editor = PersonalChatNativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        editor.font = .systemFont(ofSize: 14.5)
        editor.textContainer?.widthTracksTextView = true
        editor.string = String(repeating: "A stable editor wraps its text at the available width. ", count: 12)
        editor.setSelectedRange(NSRange(location: 10, length: 4))
        let frame = editor.frame
        let container = editor.textContainer!.containerSize
        let selection = editor.selectedRange()
        let wide = editor.fittingSize(width: 600)
        for probe: CGFloat? in [80, 0, nil, 320, 600, 80, 600] {
            _ = editor.fittingSize(width: probe)
            precondition(editor.frame == frame, "Layout measurement must not resize the live editor")
            precondition(editor.textContainer!.containerSize == container, "Speculative widths must not reflow the live text container")
            precondition(editor.selectedRange() == selection)
        }
        precondition(editor.fittingSize(width: 600) == wide)
        precondition(editor.fittingSize(width: .infinity) == nil && editor.fittingSize(width: 0) == nil)
        editor.string = "A short line"
        let short = editor.fittingSize(width: 600)!.height
        editor.string += "\n"
        precondition(editor.fittingSize(width: 600)!.height > short, "The insertion line after Return must be visible")
        editor.string = String(repeating: "Wrapping stays stable across a resize. ", count: 6)
        let wideHeight = editor.fittingSize(width: 600)!.height
        let narrowHeight = editor.fittingSize(width: 240)!.height
        precondition(narrowHeight > wideHeight && narrowHeight <= 240)
        editor.string = String(repeating: "A pasted line\n", count: 100)
        precondition(editor.fittingSize(width: 600)!.height == 240, "Long pasted drafts scroll at the height limit")
        let scroll = PersonalChatEditorScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        scroll.documentView = editor
        for width: CGFloat in [600, 240, 500, 600] {
            scroll.setFrameSize(NSSize(width: width, height: 100))
            scroll.needsLayout = true
            scroll.layoutSubtreeIfNeeded()
            precondition(editor.frame.width == scroll.contentView.bounds.width, "The document must use the whole committed viewport")
            precondition(editor.frame.height >= scroll.contentView.bounds.height)
        }
        print("Editor layout checks passed: measurement is deterministic and does not mutate live geometry or selection.")
    }
}
