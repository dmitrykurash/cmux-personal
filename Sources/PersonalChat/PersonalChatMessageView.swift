import SwiftUI

struct PersonalChatMessageView: View {
    let message: PersonalChatMessage
    var animate = false
    var completed: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    private var palette: PersonalChatPalette { PersonalChatPalette(scheme: scheme) }

    var body: some View {
        if message.role == "tool" {
            Label(message.text, systemImage: "wrench.and.screwdriver")
                .font(PersonalChatTypography.body(12)).foregroundStyle(palette.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
        } else if message.role == "user" {
            HStack {
                Spacer(minLength: 40)
                messageText.lineSpacing(5).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(palette.bubble, in: UnevenRoundedRectangle(topLeadingRadius: 19, bottomLeadingRadius: 19, bottomTrailingRadius: 8, topTrailingRadius: 19))
            }.accessibilityLabel(String(localized: "personal.you", defaultValue: "You", bundle: PersonalChatStrings.bundle) + ": " + message.text)
        } else {
            messageText.lineSpacing(8).padding(.horizontal, 4).padding(.vertical, 6)
        }
    }

    private var messageText: some View {
        PersonalChatRevealText(text: message.text, animate: animate && message.role == "assistant", completed: completed)
            .font(PersonalChatTypography.body(15)).foregroundStyle(palette.text).textSelection(.enabled)
    }
}
