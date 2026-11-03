import SwiftUI

struct PersonalChatDictationStatus: View {
    @Bindable var dictation: PersonalChatDictation
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Capsule().fill(palette.text)
                                    .frame(width: 3, height: reduceMotion ? 8 : 4 + CGFloat(dictation.level) * CGFloat(18 - abs(index - 2) * 5))
                            }
                        }.frame(width: 24, height: 20).accessibilityHidden(true)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: dictation.level)
                        Text(String(localized: "personal.voice.listening", defaultValue: "Listening… Your words stay in the draft.", bundle: PersonalChatStrings.bundle))
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
        }.font(PersonalChatTypography.body(11.5)).padding(.horizontal, 4)
    }
}
