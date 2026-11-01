import SwiftUI

struct PersonalChatMessageView: View {
    let message: PersonalChatMessage
    @Environment(\.colorScheme) private var scheme
    private var palette: PersonalChatPalette { PersonalChatPalette(scheme: scheme) }

    var body: some View {
        if message.role == "tool" {
            Label(message.text, systemImage: "wrench.and.screwdriver")
                .font(.system(size: 11)).foregroundStyle(palette.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(palette.sidebar.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        } else if message.role == "user" {
            HStack {
                Spacer(minLength: 40)
                messageText.padding(.horizontal, 18).padding(.vertical, 13)
                    .background(palette.bubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }.accessibilityLabel(String(localized: "personal.you", defaultValue: "You") + ": " + message.text)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "asterisk").font(.system(size: 18, weight: .light)).foregroundStyle(palette.accent)
                    Text(verbatim: "Claude").font(.system(size: 13, weight: .semibold, design: .serif))
                }
                messageText
            }.padding(.horizontal, 4)
        }
    }

    private var messageText: some View {
        Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
            .font(.system(size: 15)).lineSpacing(6).foregroundStyle(palette.text).textSelection(.enabled)
    }
}
