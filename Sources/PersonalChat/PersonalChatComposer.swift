import AppKit
import SwiftUI

struct PersonalChatComposer: View {
    @Bindable var model: PersonalChatModel
    let openTerminal: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focused = false
    @State private var dropTarget = false
    private var palette: PersonalChatPalette { PersonalChatPalette(scheme: scheme) }
    private var placeholder: String { String(localized: "personal.composer.placeholder", defaultValue: "How can I help you today?") }

    var body: some View {
        VStack(spacing: 10) {
            if model.selectedID != nil && model.phase != "ready" {
                statusRow
            }
            VStack(alignment: .leading, spacing: 10) {
                if !model.attachments.isEmpty { attachmentStrip }
                ZStack(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text(placeholder).font(.system(size: 15)).foregroundStyle(palette.secondary)
                            .padding(.top, 8).allowsHitTesting(false)
                    }
                    PersonalChatTextEditor(
                        text: $model.draft, editable: !model.busy && model.selectedID != nil,
                        canSubmit: model.canSend, label: placeholder,
                        textColor: NSColor(palette.text), insertionColor: NSColor(palette.accent),
                        focusChanged: { focused = $0 }, submit: { Task { await model.send() } }
                    ).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    Button(action: chooseFiles) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .regular)).frame(width: 30, height: 30)
                    }.buttonStyle(PersonalChatHoverStyle()).disabled(model.busy || model.selectedID == nil)
                        .help(String(localized: "personal.attach", defaultValue: "Attach files") + "\n" + String(localized: "personal.files.note", defaultValue: "Files are uploaded to your VPS when you send."))
                        .accessibilityLabel(String(localized: "personal.attach", defaultValue: "Attach files"))
                    Button { model.showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 14)).frame(width: 30, height: 30)
                    }.buttonStyle(PersonalChatHoverStyle()).disabled(model.busy)
                        .help(String(localized: "personal.connection", defaultValue: "Connection"))
                        .accessibilityLabel(String(localized: "personal.connection", defaultValue: "Connection"))
                    Spacer()
                    Text(verbatim: "Claude Code").font(.system(size: 13, weight: .medium, design: .serif)).foregroundStyle(palette.secondary)
                        .padding(.trailing, 10)
                    sendButton
                }.foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 12)
            .background(palette.composer, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(dropTarget ? palette.accent : (focused ? palette.border.opacity(1) : palette.border.opacity(0.7)), lineWidth: dropTarget ? 2 : 1)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.10 : 0.055), radius: focused ? 16 : 9, y: 4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: focused)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: dropTarget)
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.busy, model.selectedID != nil else { return false }
                let files = urls.filter { $0.isFileURL }
                addFiles(files)
                return !files.isEmpty
            } isTargeted: { dropTarget = $0 }
            if model.selectedID == nil {
                Button(model.connected ? String(localized: "personal.new", defaultValue: "New chat") : String(localized: "personal.connect", defaultValue: "Connect")) {
                    Task { if model.connected { await model.startSession() } else { await model.connect() } }
                }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.accent)
                    .disabled(model.busy || (model.connected && model.project == nil))
            } else {
                Text(String(localized: "personal.composer.hint", defaultValue: "Enter to send · Shift + Enter for a new line"))
                    .font(.system(size: 10.5)).foregroundStyle(palette.muted)
            }
        }
    }

    private var sendButton: some View {
        let stopping = model.phase == "busy"
        return Button {
            Task { if stopping { await model.interrupt() } else { await model.send() } }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(model.canSend || stopping ? palette.accent : palette.hover)
                if model.busy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: stopping ? "stop.fill" : "arrow.up")
                        .font(.system(size: stopping ? 11 : 16, weight: .semibold))
                        .foregroundStyle(model.canSend || stopping ? palette.onAccent : palette.muted)
                        .contentTransition(.opacity)
                }
            }.frame(width: 32, height: 32)
        }.buttonStyle(.plain)
            .disabled(model.busy || (!model.canSend && !stopping))
            .help(stopping ? String(localized: "personal.stop", defaultValue: "Stop") : String(localized: "personal.send", defaultValue: "Send"))
            .accessibilityLabel(stopping ? String(localized: "personal.stop", defaultValue: "Stop") : String(localized: "personal.send", defaultValue: "Send"))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.canSend)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if model.phase == "busy" || model.busy {
                ProgressView().controlSize(.mini)
                Text(String(localized: "personal.working", defaultValue: "Claude is working…"))
            } else if model.phase == "offline" {
                Image(systemName: "clock.arrow.circlepath")
                Text(String(localized: "personal.saved", defaultValue: "Saved conversation"))
                Spacer()
                Button(String(localized: "personal.resume", defaultValue: "Resume session")) { Task { await model.startSession(resume: true) } }
                    .disabled(!model.connected || model.busy)
            } else {
                Image(systemName: "hand.raised")
                Text(String(localized: "personal.permission", defaultValue: "Continue in the terminal to review permissions or questions.")).lineLimit(2)
                Spacer()
                Button(action: openTerminal) { Image(systemName: "arrow.up.right") }
                    .help(String(localized: "personal.terminal", defaultValue: "Open terminal"))
                    .accessibilityLabel(String(localized: "personal.terminal", defaultValue: "Open terminal"))
            }
            Spacer(minLength: 0)
        }.font(.system(size: 12)).foregroundStyle(palette.secondary).buttonStyle(.plain).padding(.horizontal, 4)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.attachments, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: "doc").foregroundStyle(palette.accent)
                        Text(url.lastPathComponent).lineLimit(1)
                        Button { model.attachments.removeAll { $0 == url } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                        }.buttonStyle(.plain).disabled(model.busy)
                            .accessibilityLabel(String(localized: "personal.attachment.remove", defaultValue: "Remove attachment"))
                    }.font(.system(size: 12)).foregroundStyle(palette.text)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.hover, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }.scrollIndicators(.hidden)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    private func addFiles(_ urls: [URL]) {
        for url in urls where !model.attachments.contains(url) { model.attachments.append(url) }
    }
}
