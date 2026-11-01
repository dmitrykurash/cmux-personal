import SwiftUI

struct PersonalChatSettingsView: View {
    @State var connection: PersonalChatConnection
    let busy: Bool
    let connect: (PersonalChatConnection) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "personal.connection", defaultValue: "Connection", bundle: PersonalChatStrings.bundle)).font(.title2)
            Text(String(localized: "personal.ssh.detail", defaultValue: "Connect as developer using a trusted SSH host and an unlocked key. Passwords are never stored in this app.", bundle: PersonalChatStrings.bundle)).foregroundStyle(.secondary)
            TextField(String(localized: "personal.host", defaultValue: "SSH host or alias", bundle: PersonalChatStrings.bundle), text: $connection.host)
            TextField(String(localized: "personal.port", defaultValue: "Port", bundle: PersonalChatStrings.bundle), value: $connection.port, format: .number.grouping(.never))
            TextField(String(localized: "personal.key", defaultValue: "SSH key path (optional)", bundle: PersonalChatStrings.bundle), text: $connection.identityFile)
            HStack {
                Button(String(localized: "personal.cancel", defaultValue: "Cancel", bundle: PersonalChatStrings.bundle)) { dismiss() }
                Spacer()
                Button(String(localized: "personal.connect", defaultValue: "Connect", bundle: PersonalChatStrings.bundle)) { connect(connection); dismiss() }
                    .buttonStyle(.borderedProminent).disabled(busy || connection.host.isEmpty)
            }
        }.padding(30).frame(width: 460)
    }
}
