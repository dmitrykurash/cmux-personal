import AppKit
import SwiftUI
#if canImport(SwiftTerm)
@preconcurrency import SwiftTerm
#endif

struct PersonalChatConsoleRequest: Identifiable {
    let id = UUID()
    let command: String // Constructed only by PersonalChatConnection, never remote output.
}

struct PersonalChatConsoleSheet: View {
    let request: PersonalChatConsoleRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var ended = false
    static var supported: Bool {
        #if canImport(SwiftTerm)
        true
        #else
        false
        #endif
    }
    var body: some View {
        let palette = PersonalChatPalette(scheme: scheme)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "terminal").foregroundStyle(palette.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "personal.console.title", defaultValue: "Remote console", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.body(14, weight: .medium))
                    Text(ended ? String(localized: "personal.console.ended", defaultValue: "Console disconnected. Your saved chat is still available.", bundle: PersonalChatStrings.bundle) : String(localized: "personal.console.note", defaultValue: "Your live VPS session. Closing this panel keeps Claude running.", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(11)).foregroundStyle(palette.muted)
                }
                Spacer()
                Button(String(localized: "personal.console.done", defaultValue: "Back to chat", bundle: PersonalChatStrings.bundle)) { dismiss() }
                    .buttonStyle(.bordered)
            }.padding(16)
            Divider().overlay(palette.border)
            #if canImport(SwiftTerm)
            PersonalChatTerminalSurface(command: request.command, ended: { ended = true })
                .padding(10)
            #endif
        }.frame(width: 960, height: 650).background(palette.canvas).foregroundStyle(palette.text)
            .interactiveDismissDisabled() // Escape belongs to the CLI, not the sheet.
    }
}

#if canImport(SwiftTerm)
struct PersonalChatTerminalSurface: NSViewRepresentable {
    let command: String
    let ended: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(ended: ended) }
    func makeNSView(context: Context) -> TerminalView {
        let view = FocusedTerminal(frame: NSRect(x: 0, y: 0, width: 920, height: 550))
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeBackgroundColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.086, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        view.terminalDelegate = context.coordinator
        context.coordinator.view = view
        let process = LocalProcess(delegate: context.coordinator, dispatchQueue: .main)
        context.coordinator.process = process
        // Every production command is a quoted /usr/bin/ssh invocation generated
        // from validated connection fields. No remote output becomes local code.
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        if let socket = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] { environment.append("SSH_AUTH_SOCK=" + socket) }
        process.startProcess(executable: "/bin/sh", args: ["-c", "exec " + command], environment: environment)
        return view
    }
    func updateNSView(_ nsView: TerminalView, context: Context) {}
    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        // Disconnect only this local SSH process; remote tmux remains alive.
        if let process = coordinator.process, process.running {
            let pid = process.shellPid
            process.terminate()
            // SwiftTerm cancels its exit monitor on terminate; reap our child.
            Task.detached { var status: Int32 = 0; _ = waitpid(pid, &status, 0) }
        }
        coordinator.process = nil
        nsView.terminalDelegate = nil
    }
    private final class FocusedTerminal: TerminalView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    }
    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate, @preconcurrency LocalProcessDelegate {
        weak var view: TerminalView?
        var process: LocalProcess?
        let ended: () -> Void
        init(ended: @escaping () -> Void) { self.ended = ended }
        func processTerminated(_ source: LocalProcess, exitCode: Int32?) { ended() }
        func dataReceived(slice: ArraySlice<UInt8>) { view?.feed(byteArray: slice) }
        func getWindowSize() -> winsize {
            winsize(ws_row: UInt16(view?.getTerminal().rows ?? 30), ws_col: UInt16(view?.getTerminal().cols ?? 110), ws_xpixel: 0, ws_ypixel: 0)
        }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard let process, process.running else { return }
            var size = getWindowSize()
            _ = ioctl(process.childfd, TIOCSWINSZ, &size)
        }
        func send(source: TerminalView, data: ArraySlice<UInt8>) { process?.send(data: data) }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func clipboardCopy(source: TerminalView, content: Data) {} // Deny remote OSC 52 writes.
        func clipboardRead(source: TerminalView) -> Data? { nil } // Deny remote clipboard reads.
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { return }
            NSWorkspace.shared.open(url) // Only a user's explicit link click.
        }
    }
}
#endif
