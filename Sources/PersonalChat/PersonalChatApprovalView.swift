import SwiftUI

struct PersonalChatApprovalView: View {
    let approval: PersonalChatApproval
    let disabled: Bool
    let decide: (String, [String: String]?) -> Void
    let openTerminal: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var palette: PersonalChatPalette { PersonalChatPalette(scheme: scheme) }
    @State private var selections: [String: Set<String>] = [:]
    @State private var customAnswers: [String: String] = [:]
    private var answers: [String: String] {
        Dictionary(uniqueKeysWithValues: (approval.questions ?? []).map { question in
            let custom = customAnswers[question.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let selected = selections[question.id, default: []]
            return (question.question, custom.isEmpty ? question.options.filter { selected.contains($0.label) }.map(\.label).joined(separator: ", ") : custom)
        })
    }
    private var title: String {
        if approval.questions != nil { return String(localized: "personal.question.title", defaultValue: "Claude has a question", bundle: PersonalChatStrings.bundle) }
        if approval.plan != nil { return String(localized: "personal.plan.title", defaultValue: "Review the plan", bundle: PersonalChatStrings.bundle) }
        return String(localized: "personal.approval.title", defaultValue: "Permission needed", bundle: PersonalChatStrings.bundle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised").font(.system(size: 15)).foregroundStyle(palette.accent)
                    .frame(width: 32, height: 32).background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(PersonalChatTypography.body(13, weight: .medium))
                    Text(approval.tool).font(PersonalChatTypography.body(11)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(approval.project).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.muted)
                .textSelection(.enabled).lineLimit(2).truncationMode(.middle).help(approval.project)
            if let questions = approval.questions {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(questions) { question in
                            PersonalChatQuestionView(question: question, selected: selections[question.id, default: []], custom: customAnswers[question.id, default: ""], choose: { label in
                                customAnswers[question.id] = ""
                                if question.multiSelect == true {
                                    if selections[question.id, default: []].contains(label) { selections[question.id]?.remove(label) }
                                    else { selections[question.id, default: []].insert(label) }
                                } else { selections[question.id] = [label] }
                            }, editCustom: { customAnswers[question.id] = $0; selections[question.id] = [] })
                        }
                    }
                }.frame(maxHeight: 330).disabled(disabled)
            } else if let plan = approval.plan {
                ScrollView {
                    PersonalChatRevealText(text: plan, animate: false, completed: {})
                        .font(PersonalChatTypography.body(13)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(height: 280).background(palette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            } else {
              GeometryReader { geometry in
                ScrollView([.vertical, .horizontal]) {
                    Text(verbatim: approval.detail).font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                        .frame(minWidth: max(0, geometry.size.width - 24), alignment: .leading).padding(12)
                }
            }.frame(height: min(230, max(72, CGFloat(approval.detail.components(separatedBy: "\n").count) * 17 + 24)))
                .background(palette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border))
            }
            Text(String(localized: "personal.approval.scope", defaultValue: "Only this request. Your permission settings stay unchanged.", bundle: PersonalChatStrings.bundle))
                .font(PersonalChatTypography.body(11)).foregroundStyle(palette.muted)
            HStack(spacing: 8) {
                Button(action: openTerminal) {
                    Label(String(localized: "personal.console.open", defaultValue: "Open console", bundle: PersonalChatStrings.bundle), systemImage: "terminal")
                        .font(PersonalChatTypography.body(11)).padding(.horizontal, 8).frame(height: 32)
                }.buttonStyle(PersonalChatHoverStyle(radius: 8)).foregroundStyle(palette.muted)
                Spacer(minLength: 0)
                Button { decide("deny", nil) } label: {
                    Text(String(localized: "personal.approval.deny", defaultValue: "Deny", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(12, weight: .medium)).padding(.horizontal, 16).frame(height: 32)
                        .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(PersonalChatHoverStyle(radius: 8))
                Button { decide("allow", approval.questions == nil ? nil : answers) } label: {
                    Text(approval.questions != nil ? String(localized: "personal.question.submit", defaultValue: "Send answer", bundle: PersonalChatStrings.bundle) : approval.plan != nil ? String(localized: "personal.plan.approve", defaultValue: "Approve plan", bundle: PersonalChatStrings.bundle) : String(localized: "personal.approval.allow", defaultValue: "Allow once", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(12, weight: .medium)).padding(.horizontal, 16).frame(height: 32)
                        .foregroundStyle(palette.onAccent).background(palette.send, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(PersonalChatHoverStyle(radius: 8)).disabled(approval.questions != nil && answers.values.contains(where: \.isEmpty))
            }.disabled(disabled)
        }.padding(16).foregroundStyle(palette.text)
            .background(palette.composer, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.strongBorder))
            .accessibilityElement(children: .contain)
    }
}
