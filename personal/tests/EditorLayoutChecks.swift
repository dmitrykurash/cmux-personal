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
        print("Editor layout checks passed: measurement is deterministic and does not mutate live geometry or selection.")
    }
}
