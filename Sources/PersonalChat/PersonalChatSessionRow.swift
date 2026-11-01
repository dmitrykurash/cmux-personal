import SwiftUI

struct PersonalChatSessionRow: View {
    let session: PersonalChatSession
    let selected: Bool
    let archived: Bool
    let select: () -> Void
    let toggleArchive: () -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var actionTitle: String {
        archived
            ? String(localized: "personal.archive.restore", defaultValue: "Restore chat", bundle: PersonalChatStrings.bundle)
            : String(localized: "personal.archive.move", defaultValue: "Archive chat", bundle: PersonalChatStrings.bundle)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                Text(session.title == "New chat" ? String(localized: "personal.new", defaultValue: "New chat", bundle: PersonalChatStrings.bundle) : session.title)
                    .font(PersonalChatTypography.body(12.5)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12).padding(.trailing, 4).frame(height: 32)
            }.buttonStyle(PersonalChatHoverStyle(radius: 9)).help(session.title)
            PersonalChatActionsMenu(label: String(localized: "personal.archive.actions", defaultValue: "Chat actions", bundle: PersonalChatStrings.bundle)) { actions }
                .padding(.trailing, 4)
        }
        .background(selected ? PersonalChatPalette(scheme: scheme).selection : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        Button(action: toggleArchive) {
            Label(actionTitle, systemImage: archived ? "arrow.uturn.backward" : "archivebox")
        }
        if archived {
            Divider()
            Button(role: .destructive, action: delete) {
                Label(String(localized: "personal.delete.chat", defaultValue: "Delete permanently", bundle: PersonalChatStrings.bundle), systemImage: "trash")
            }
        }
    }
}
