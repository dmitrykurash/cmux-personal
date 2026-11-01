import SwiftUI

struct PersonalChatMessageView: View {
    let message: PersonalChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.role == "tool" {
                Label(message.text, systemImage: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(message.role == "user" ? String(localized: "personal.you", defaultValue: "You") : "Claude")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
                    .font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
            }
        }
        .padding(message.role == "user" ? 18 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == "user" ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 14))
    }
}
