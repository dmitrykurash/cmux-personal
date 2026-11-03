import AppKit
import SwiftUI
#if canImport(SwiftTerm)
@preconcurrency import SwiftTerm
#endif

struct PersonalChatConsoleRequest: Identifiable {
    let id = UUID()
    let command: String // Constructed only by PersonalChatConnection, never remote output.
    var cliCommand: String? = nil
}

struct PersonalChatConsolePane: View {
    @Bindable var state: PersonalChatConsoleState
    @Bindable var model: PersonalChatModel
    @State private var ended = false
    static var backgroundColor: NSColor {
        NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.043, alpha: 1)
    }
    static var supported: Bool {
        #if canImport(SwiftTerm)
        true
        #else
        false
        #endif
    }
    var body: some View {
        let palette = PersonalChatPalette(scheme: .dark)
        ZStack(alignment: .topTrailing) {
            Group {
                if let request = state.request {
                    #if canImport(SwiftTerm)
                    PersonalChatTerminalSurface(command: request.command, focusID: state.focusID, ended: {
                        if state.request?.id == request.id {
                            ended = true
                            state.terminalDidEnd(requestID: request.id)
                        }
                    })
                        .id(request.id).padding(8)
                    #endif
                } else {
                    connectionState
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if ended {
                Button(String(localized: "personal.console.reconnect", defaultValue: "Reconnect console", bundle: PersonalChatStrings.bundle), action: state.reconnect)
                    .buttonStyle(.bordered).disabled(model.busy || !model.connected)
                    .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            Button(action: state.close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(Color(white: 0.14).opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12)))
            }
            .buttonStyle(PersonalChatHoverStyle(radius: 8))
            .help(String(localized: "personal.console.close", defaultValue: "Close console", bundle: PersonalChatStrings.bundle))
            .accessibilityLabel(String(localized: "personal.console.close", defaultValue: "Close console", bundle: PersonalChatStrings.bundle))
            .accessibilityIdentifier("personal.console.close")
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(nsColor: Self.backgroundColor)
                .ignoresSafeArea(.container, edges: [.top, .trailing, .bottom])
        }
        .foregroundStyle(palette.secondary)
        .environment(\.colorScheme, .dark)
        .onChange(of: state.request?.id) { ended = false }
    }

    private var connectionState: some View {
        VStack(spacing: 14) {
            if state.opening || model.busy { ProgressView().controlSize(.small) }
            Text(model.selectedID == nil
                 ? String(localized: "personal.console.select", defaultValue: "Select a chat to open its console.", bundle: PersonalChatStrings.bundle)
                 : model.phase == "offline"
                 ? String(localized: "personal.saved", defaultValue: "Saved conversation", bundle: PersonalChatStrings.bundle)
                 : state.failed || !model.connected
                 ? String(localized: "personal.console.ended", defaultValue: "Console disconnected. Your saved chat is still available.", bundle: PersonalChatStrings.bundle)
                 : String(localized: "personal.console.connecting", defaultValue: "Connecting to your session…", bundle: PersonalChatStrings.bundle))
                .font(PersonalChatTypography.body(12)).multilineTextAlignment(.center)
            if model.selectedID != nil && model.phase == "offline" {
                Button(String(localized: "personal.resume", defaultValue: "Resume session", bundle: PersonalChatStrings.bundle)) { Task { await model.startSession(resume: true) } }
                    .buttonStyle(.bordered).disabled(!model.connected || model.busy)
            } else if state.failed {
                Button(String(localized: "personal.console.reconnect", defaultValue: "Reconnect console", bundle: PersonalChatStrings.bundle), action: state.reconnect)
                    .buttonStyle(.bordered).disabled(!model.connected || model.busy)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if canImport(SwiftTerm)
struct PersonalChatTerminalSurface: NSViewRepresentable {
    let command: String
    var focusID: UUID? = nil
    let ended: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(ended: ended) }
    func makeNSView(context: Context) -> TerminalView {
        let view = FocusedTerminal(frame: NSRect(x: 0, y: 0, width: 920, height: 550))
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeBackgroundColor = PersonalChatConsolePane.backgroundColor
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        if focusID != nil { view.focusWhenAttached() }
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
    func updateNSView(_ nsView: TerminalView, context: Context) {
        if context.coordinator.focusID != focusID {
            context.coordinator.focusID = focusID
            if focusID != nil { (nsView as? FocusedTerminal)?.focusWhenAttached() }
        }
    }
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
        private var focusPending = false
        func focusWhenAttached() { focusPending = true; applyFocus() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyFocus() }
        private func applyFocus() {
            guard focusPending, let window else { return }
            focusPending = false
            window.makeFirstResponder(self)
        }
    }
    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate, @preconcurrency LocalProcessDelegate {
        var focusID: UUID?
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
