import SwiftUI

struct PersonalChatRenameView: View {
    let rename: (String) async throws -> Void
    @State private var name: String
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(target: PersonalChatRenameTarget, rename: @escaping (String) async throws -> Void) {
        _name = State(initialValue: target.session.title)
        self.rename = rename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(localized: "personal.rename.title", defaultValue: "Rename chat", bundle: PersonalChatStrings.bundle))
                .font(PersonalChatTypography.body(20, weight: .medium))
            TextField(String(localized: "personal.rename.name", defaultValue: "Chat name", bundle: PersonalChatStrings.bundle), text: $name)
                .textFieldStyle(.roundedBorder).focused($focused).disabled(saving)
                .accessibilityIdentifier("personal.rename.name")
            Text(String(localized: "personal.rename.note", defaultValue: "This name is saved in CheatCode on this Mac.", bundle: PersonalChatStrings.bundle))
                .font(PersonalChatTypography.body(12)).foregroundStyle(.secondary)
            if let error {
                Text(error).font(PersonalChatTypography.body(12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if !name.isEmpty && PersonalChatRenameError.normalized(name) == nil {
                Text(PersonalChatRenameError.invalidName.localizedDescription)
                    .font(PersonalChatTypography.body(12)).foregroundStyle(.secondary)
            }
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button(String(localized: "personal.cancel", defaultValue: "Cancel", bundle: PersonalChatStrings.bundle)) { dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(saving)
                Button(String(localized: "personal.rename.save", defaultValue: "Rename", bundle: PersonalChatStrings.bundle)) {
                    Task {
                        saving = true; error = nil
                        do { try await rename(name); dismiss() }
                        catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }.keyboardShortcut(.defaultAction).disabled(saving || PersonalChatRenameError.normalized(name) == nil)
            }
        }.padding(26).frame(width: 420)
            .interactiveDismissDisabled(saving)
            .onAppear { focused = true }
    }
}
