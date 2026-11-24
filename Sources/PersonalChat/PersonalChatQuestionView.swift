import SwiftUI

struct PersonalChatQuestionView: View {
    let question: PersonalChatQuestion
    let selected: Set<String>
    let custom: String
    let choose: (String) -> Void
    let editCustom: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = PersonalChatPalette(scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            Text(question.question).font(PersonalChatTypography.body(14, weight: .medium))
            ForEach(question.options) { option in
                Button { choose(option.label) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected.contains(option.label) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(option.label) ? palette.accent : palette.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.label).font(PersonalChatTypography.body(12, weight: .medium))
                            if let description = option.description, !description.isEmpty {
                                Text(description).font(PersonalChatTypography.body(11)).foregroundStyle(palette.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected.contains(option.label) ? palette.selection : palette.chip, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(PersonalChatHoverStyle(radius: 9))
            }
            TextField(String(localized: "personal.question.other", defaultValue: "Or type your own answer", bundle: PersonalChatStrings.bundle), text: Binding(get: { custom }, set: { editCustom($0) }))
                .textFieldStyle(.plain).font(PersonalChatTypography.body(12)).padding(10)
                .background(palette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.border))
        }
    }
}
