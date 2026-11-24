import SwiftUI

struct PersonalChatGitHubView: View {
    @State var model: PersonalChatGitHub
    @State private var attempt = 0
    @State private var cancellation: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = PersonalChatPalette(scheme: scheme)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(String(localized: "personal.brand.github", defaultValue: "GitHub", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.display(28))
                Spacer()
                if model.state.phase == "checking" || model.state.phase == "starting" { ProgressView().controlSize(.small) }
            }
            Text(String(localized: "personal.github.note", defaultValue: "Connect GitHub on your VPS to clone private repositories and push changes. Sign in in your browser; CheatCode never receives your password or access token.", bundle: PersonalChatStrings.bundle))
                .font(PersonalChatTypography.body(13)).foregroundStyle(palette.secondary)
            if let code = model.state.deviceCode {
                Text(String(localized: "personal.github.code", defaultValue: "Enter this one-time code on GitHub:", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.body(12))
                Text(code).font(.system(size: 30, weight: .medium, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity).padding(18).background(palette.chip, in: RoundedRectangle(cornerRadius: 12))
                Link(String(localized: "personal.github.open", defaultValue: "Open GitHub in browser", bundle: PersonalChatStrings.bundle), destination: URL(string: "https://github.com/login/device")!)
                    .font(PersonalChatTypography.body(13, weight: .medium))
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(String(localized: "personal.github.waiting", defaultValue: "Waiting for you to finish signing in…", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.body(12)).foregroundStyle(palette.muted)
                }
            } else if model.state.phase == "connected" {
                Label(String(localized: "personal.github.connected", defaultValue: "GitHub is connected on your VPS", bundle: PersonalChatStrings.bundle), systemImage: "checkmark.circle.fill").foregroundStyle(palette.success)
            } else if model.state.phase == "unavailable" {
                Text(String(localized: "personal.github.missing", defaultValue: "GitHub CLI is not installed on the VPS yet. Ask Claude to install it, then return here.", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.body(12))
            } else if model.state.phase == "failed" {
                Text(String(localized: "personal.github.failed", defaultValue: "Sign-in did not finish. Try again to get a new code.", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.body(12)).foregroundStyle(palette.secondary)
            }
            if let issue = model.issue { Text(issue).font(PersonalChatTypography.body(12)).foregroundStyle(.red) }
            HStack {
                if model.state.id != nil && model.state.phase != "connected" {
                    Button(String(localized: "personal.cancel", defaultValue: "Cancel", bundle: PersonalChatStrings.bundle)) { cancellation = Task { await model.cancel() } }.disabled(model.busy)
                }
                Spacer()
                Button(String(localized: "personal.console.done", defaultValue: "Back to chat", bundle: PersonalChatStrings.bundle)) { dismiss() }
                if !["connected", "checking", "unavailable", "starting", "waiting", "cancelling"].contains(model.state.phase) || model.issue != nil {
                    Button(String(localized: "personal.github.signIn", defaultValue: "Sign in", bundle: PersonalChatStrings.bundle)) { attempt += 1 }
                        .buttonStyle(.borderedProminent).disabled(model.busy)
                }
            }
        }.padding(28).frame(width: 490).background(palette.canvas).foregroundStyle(palette.text)
            .task(id: attempt) {
                if attempt == 0 { await model.load() } else { await model.signIn() }
            }
            .onDisappear { cancellation?.cancel(); model.stop() }
    }
}
