import SwiftUI

struct PersonalChatDictationButton: View {
    @Bindable var dictation: PersonalChatDictation
    let enabled: Bool
    let start: () -> Void

    private var label: String {
        if dictation.phase == .recording { return String(localized: "personal.voice.stop", defaultValue: "Stop dictation", bundle: PersonalChatStrings.bundle) }
        if dictation.active { return String(localized: "personal.voice.cancel", defaultValue: "Cancel dictation", bundle: PersonalChatStrings.bundle) }
        return String(localized: "personal.voice.start", defaultValue: "Dictate a message", bundle: PersonalChatStrings.bundle)
    }

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Picker(String(localized: "personal.voice.language", defaultValue: "Dictation language", bundle: PersonalChatStrings.bundle), selection: $dictation.locale) {
                    Text(String(localized: "personal.voice.english", defaultValue: "English", bundle: PersonalChatStrings.bundle)).tag("en-US")
                    Text(String(localized: "personal.voice.russian", defaultValue: "Russian", bundle: PersonalChatStrings.bundle)).tag("ru-RU")
                }
            } label: {
                Text(verbatim: dictation.locale.prefix(2).uppercased())
                    .font(PersonalChatTypography.body(10, weight: .medium)).frame(width: 28, height: 28)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(.secondary)
                .disabled(dictation.active || !enabled)
                .help(String(localized: "personal.voice.language", defaultValue: "Dictation language", bundle: PersonalChatStrings.bundle))
                .accessibilityLabel(String(localized: "personal.voice.language", defaultValue: "Dictation language", bundle: PersonalChatStrings.bundle))
            Button {
                if dictation.phase == .recording { dictation.stop() }
                else if dictation.active { dictation.cancel() }
                else { start() }
            } label: {
                Image(systemName: dictation.phase == .recording ? "stop.fill" : "mic")
                    .font(.system(size: dictation.phase == .recording ? 11 : 14, weight: .medium))
                    .frame(width: 28, height: 28)
            }.buttonStyle(PersonalChatHoverStyle(radius: 7))
                .disabled(!enabled && !dictation.active)
                .help(label).accessibilityLabel(label).accessibilityIdentifier("personal.voice.toggle")
        }
    }
}
