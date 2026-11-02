import SwiftUI

struct PersonalChatApprovalView: View {
    let approval: PersonalChatApproval
    let disabled: Bool
    let decide: (String) -> Void
    let openTerminal: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var palette: PersonalChatPalette { PersonalChatPalette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised").font(.system(size: 15)).foregroundStyle(palette.accent)
                    .frame(width: 32, height: 32).background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "personal.approval.title", defaultValue: "Permission needed", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(13, weight: .medium))
                    Text(approval.tool).font(PersonalChatTypography.body(11)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(approval.project).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.muted)
                .textSelection(.enabled).lineLimit(2).truncationMode(.middle).help(approval.project)
            GeometryReader { geometry in
                ScrollView([.vertical, .horizontal]) {
                    Text(verbatim: approval.detail).font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                        .frame(minWidth: max(0, geometry.size.width - 24), alignment: .leading).padding(12)
                }
            }.frame(height: min(230, max(72, CGFloat(approval.detail.components(separatedBy: "\n").count) * 17 + 24)))
                .background(palette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border))
            Text(String(localized: "personal.approval.scope", defaultValue: "Only this request. Your permission settings stay unchanged.", bundle: PersonalChatStrings.bundle))
                .font(PersonalChatTypography.body(11)).foregroundStyle(palette.muted)
            HStack(spacing: 8) {
                Button(action: openTerminal) {
                    Label(String(localized: "personal.terminal", defaultValue: "Open terminal", bundle: PersonalChatStrings.bundle), systemImage: "terminal")
                        .font(PersonalChatTypography.body(11)).padding(.horizontal, 8).frame(height: 32)
                }.buttonStyle(PersonalChatHoverStyle(radius: 8)).foregroundStyle(palette.muted)
                Spacer(minLength: 0)
                Button { decide("deny") } label: {
                    Text(String(localized: "personal.approval.deny", defaultValue: "Deny", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(12, weight: .medium)).padding(.horizontal, 16).frame(height: 32)
                        .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(PersonalChatHoverStyle(radius: 8))
                Button { decide("allow") } label: {
                    Text(String(localized: "personal.approval.allow", defaultValue: "Allow once", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(12, weight: .medium)).padding(.horizontal, 16).frame(height: 32)
                        .foregroundStyle(palette.onAccent).background(palette.send, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(PersonalChatHoverStyle(radius: 8))
            }.disabled(disabled)
        }.padding(16).foregroundStyle(palette.text)
            .background(palette.composer, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.strongBorder))
            .accessibilityElement(children: .contain)
    }
}
