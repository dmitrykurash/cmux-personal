import SwiftUI

struct PersonalChatDictationStatus: View {
    @Bindable var dictation: PersonalChatDictation
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = PersonalChatPalette(scheme: scheme)
        Group {
            if let issue = dictation.issue {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "mic.slash")
                    Text(issue).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: dictation.dismissIssue) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                        .buttonStyle(PersonalChatHoverStyle(radius: 7))
                        .accessibilityLabel(String(localized: "personal.voice.dismiss", defaultValue: "Dismiss dictation message", bundle: PersonalChatStrings.bundle))
                }.foregroundStyle(palette.secondary)
            } else if dictation.active {
                HStack(spacing: 8) {
                    if dictation.phase == .recording {
                        Image(systemName: "mic.fill")
                        Text(String(localized: "personal.voice.listening", defaultValue: "Recording… Stop to add the text to your draft.", bundle: PersonalChatStrings.bundle))
                    } else {
                        ProgressView().controlSize(.mini)
                        Text(dictation.phase == .finishing
                             ? String(localized: "personal.voice.finishing", defaultValue: "Finishing dictation…", bundle: PersonalChatStrings.bundle)
                             : String(localized: "personal.voice.preparing", defaultValue: "Preparing on-device dictation… The first use may download a language model.", bundle: PersonalChatStrings.bundle))
                    }
                    Spacer(minLength: 0)
                    Button(String(localized: "personal.voice.cancel", defaultValue: "Cancel dictation", bundle: PersonalChatStrings.bundle)) { dictation.cancel() }
                        .buttonStyle(.plain)
                }.foregroundStyle(palette.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).font(PersonalChatTypography.body(11.5)).padding(.horizontal, 4)
    }
}
