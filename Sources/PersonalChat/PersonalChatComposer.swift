import AppKit
import SwiftUI

struct PersonalChatComposer: View {
    @Bindable var model: PersonalChatModel
    let openTerminal: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focused = false
    @State private var dropTarget = false
    @State private var hovered = false
    private var palette: PersonalChatPalette { PersonalChatPalette(scheme: scheme) }
    private var placeholder: String { String(localized: "personal.composer.placeholder", defaultValue: "How can I help you today?", bundle: PersonalChatStrings.bundle) }

    var body: some View {
        VStack(spacing: 10) {
            if model.selectedID != nil && model.approvals.isEmpty && model.phase != "ready" && (model.messages.isEmpty || model.phase != "busy") {
                statusRow
            }
            VStack(alignment: .leading, spacing: 8) {
                if !model.attachments.isEmpty { attachmentStrip }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock").font(.system(size: 13)).foregroundStyle(palette.muted)
                        .padding(.top, 5).help(String(localized: "personal.connection", defaultValue: "Connection", bundle: PersonalChatStrings.bundle))
                    ZStack(alignment: .topLeading) {
                        if model.draft.isEmpty && model.dictation?.active != true {
                            Text(placeholder).font(PersonalChatTypography.body(14.5)).foregroundStyle(palette.muted)
                                .padding(.top, 2).allowsHitTesting(false)
                        }
                        PersonalChatTextEditor(
                            text: $model.draft, editable: !model.busy && model.selectedID != nil && model.dictation?.active != true,
                            canSubmit: model.canSend, label: placeholder,
                            textColor: NSColor(palette.text), insertionColor: NSColor(palette.text),
                            focusChanged: { focused = $0 }, submit: { Task { await model.send() } }
                        ).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .opacity(model.dictation?.active == true ? 0 : 1)
                            .allowsHitTesting(model.dictation?.active != true)
                            .accessibilityHidden(model.dictation?.active == true)
                        if let dictation = model.dictation, dictation.active {
                            PersonalChatDictationWaveform(dictation: dictation)
                        }
                    }.frame(maxWidth: .infinity, minHeight: model.dictation?.active == true ? 72 : 28, alignment: .topLeading)
                }.frame(maxWidth: .infinity).padding(.trailing, 6)
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "asterisk").font(.system(size: 11, weight: .medium))
                        Text(verbatim: "Claude Code").font(PersonalChatTypography.body(12, weight: .medium))
                    }.padding(.horizontal, 9).frame(height: 28)
                        .background(palette.chip, in: RoundedRectangle(cornerRadius: 7))
                    Button(action: chooseFiles) {
                        Image(systemName: "paperclip").font(.system(size: 14)).frame(width: 28, height: 28)
                    }.buttonStyle(PersonalChatHoverStyle(radius: 7)).disabled(model.busy || model.selectedID == nil)
                        .help(String(localized: "personal.attach", defaultValue: "Attach files", bundle: PersonalChatStrings.bundle) + "\n" + String(localized: "personal.files.note", defaultValue: "Files are uploaded to your VPS when you send.", bundle: PersonalChatStrings.bundle))
                        .accessibilityLabel(String(localized: "personal.attach", defaultValue: "Attach files", bundle: PersonalChatStrings.bundle))
                    Button(action: openTerminal) {
                        Image(systemName: "terminal").font(.system(size: 13)).frame(width: 28, height: 28)
                    }.buttonStyle(PersonalChatHoverStyle(radius: 7))
                        .disabled(model.selectedID == nil || model.phase == "offline" || !model.connected)
                        .help(String(localized: "personal.console.open", defaultValue: "Open console", bundle: PersonalChatStrings.bundle))
                        .accessibilityLabel(String(localized: "personal.console.open", defaultValue: "Open console", bundle: PersonalChatStrings.bundle))
                    Spacer()
                    if let dictation = model.dictation {
                        PersonalChatDictationButton(dictation: dictation, enabled: !model.busy && model.selectedID != nil, start: model.startDictation)
                    }
                    sendButton
                }.foregroundStyle(palette.secondary)
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.top, 12).padding(.bottom, 8)
            .background(focused ? palette.composerFocus : (hovered ? palette.composerHover : palette.composer),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(dropTarget ? palette.accent : (focused ? palette.focusBorder : (hovered ? palette.strongBorder : palette.border)), lineWidth: dropTarget ? 2 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(palette.focusRing, lineWidth: 4).padding(-2).opacity(focused ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.04), radius: 6, y: 2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: focused)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: dropTarget)
            .onHover { hovered = $0 }
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.busy, model.selectedID != nil else { return false }
                let files = urls.filter { $0.isFileURL }
                addFiles(files)
                return !files.isEmpty
            } isTargeted: { dropTarget = $0 }
            if let dictation = model.dictation {
                PersonalChatDictationStatus(dictation: dictation)
            }
            if model.selectedID == nil && model.connected && model.project != nil {
                Button(model.connected ? String(localized: "personal.new", defaultValue: "New chat", bundle: PersonalChatStrings.bundle) : String(localized: "personal.connect", defaultValue: "Connect", bundle: PersonalChatStrings.bundle)) {
                    Task { if model.connected { await model.startSession() } else { await model.connect() } }
                }.buttonStyle(.plain).font(PersonalChatTypography.body(12, weight: .medium)).foregroundStyle(palette.accent)
                    .disabled(model.busy || (model.connected && model.project == nil))
            } else {
                Text(String(localized: "personal.composer.hint", defaultValue: "Enter to send · Shift + Enter for a new line", bundle: PersonalChatStrings.bundle))
                    .font(PersonalChatTypography.body(11.5)).foregroundStyle(palette.muted)
            }
        }
    }

    private var sendButton: some View {
        let stopping = model.phase == "busy"
        return Button {
            Task { if stopping { await model.interrupt() } else { await model.send() } }
        } label: {
            ZStack {
                Circle().fill(palette.send).opacity(model.canSend || stopping ? 1 : 0.4)
                if model.busy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: stopping ? "stop.fill" : "arrow.up")
                        .font(.system(size: stopping ? 11 : 16, weight: .semibold))
                        .foregroundStyle(palette.onAccent)
                        .contentTransition(.opacity)
                }
            }.frame(width: 34, height: 34)
        }.buttonStyle(PersonalChatSendStyle())
            .disabled(model.busy || (!model.canSend && !stopping))
            .help(stopping ? String(localized: "personal.stop", defaultValue: "Stop", bundle: PersonalChatStrings.bundle) : String(localized: "personal.send", defaultValue: "Send", bundle: PersonalChatStrings.bundle))
            .accessibilityLabel(stopping ? String(localized: "personal.stop", defaultValue: "Stop", bundle: PersonalChatStrings.bundle) : String(localized: "personal.send", defaultValue: "Send", bundle: PersonalChatStrings.bundle))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.canSend)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if model.phase == "busy" || model.busy {
                ProgressView().controlSize(.mini)
                Text(String(localized: "personal.working", defaultValue: "Claude is working…", bundle: PersonalChatStrings.bundle))
            } else if model.phase == "console" {
                Image(systemName: "terminal")
                Text(model.consoleCommand ?? String(localized: "personal.console.title", defaultValue: "Remote console", bundle: PersonalChatStrings.bundle))
                Spacer()
                Button(String(localized: "personal.console.done", defaultValue: "Back to chat", bundle: PersonalChatStrings.bundle)) { Task { await model.resumeNativeApprovals() } }
                Button(action: openTerminal) { Image(systemName: "arrow.up.right").frame(width: 28, height: 28) }
                    .buttonStyle(PersonalChatHoverStyle(radius: 7))
                    .help(String(localized: "personal.console.open", defaultValue: "Open console", bundle: PersonalChatStrings.bundle))
                    .accessibilityLabel(String(localized: "personal.console.open", defaultValue: "Open console", bundle: PersonalChatStrings.bundle))
            } else if model.phase == "offline" {
                Image(systemName: "clock.arrow.circlepath")
                Text(String(localized: "personal.saved", defaultValue: "Saved conversation", bundle: PersonalChatStrings.bundle))
                Spacer()
                Button(String(localized: "personal.resume", defaultValue: "Resume session", bundle: PersonalChatStrings.bundle)) { Task { await model.startSession(resume: true) } }
                    .disabled(!model.connected || model.busy)
            } else {
                Image(systemName: "hand.raised")
                Text(String(localized: "personal.console.fallback", defaultValue: "Continue in the console to finish this step.", bundle: PersonalChatStrings.bundle)).lineLimit(2)
                Spacer()
                Button(action: openTerminal) { Image(systemName: "arrow.up.right").frame(width: 28, height: 28) }
                    .buttonStyle(PersonalChatHoverStyle(radius: 7))
                    .help(String(localized: "personal.console.open", defaultValue: "Open console", bundle: PersonalChatStrings.bundle))
                    .accessibilityLabel(String(localized: "personal.console.open", defaultValue: "Open console", bundle: PersonalChatStrings.bundle))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .font(PersonalChatTypography.body(12)).foregroundStyle(palette.secondary).buttonStyle(.plain).padding(.horizontal, 4)
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
                            .accessibilityLabel(String(localized: "personal.attachment.remove", defaultValue: "Remove attachment", bundle: PersonalChatStrings.bundle))
                    }.font(PersonalChatTypography.body(12)).foregroundStyle(palette.text)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.hover, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }.scrollIndicators(.hidden)
    }

    private func chooseFiles() {
        model.dictation?.cancel(restore: false)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    private func addFiles(_ urls: [URL]) {
        for url in urls where !model.attachments.contains(url) { model.attachments.append(url) }
    }
}
