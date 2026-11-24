import SwiftUI

struct PersonalChatDeletionView: View {
    let target: PersonalChatDeletionTarget
    let prepare: () async throws -> PersonalChatReply
    let commit: (String?, String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var planID: String?
    @State private var confirmation = ""
    @State private var working = false
    @State private var error: String?

    private var title: String {
        switch target.kind {
        case .chat: return String(localized: "personal.delete.chat", defaultValue: "Delete permanently", bundle: PersonalChatStrings.bundle)
        case .project: return String(localized: "personal.delete.project", defaultValue: "Delete project from server…", bundle: PersonalChatStrings.bundle)
        case .removeProject: return String(localized: "personal.delete.remove", defaultValue: "Remove from app", bundle: PersonalChatStrings.bundle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: target.permanent ? "trash" : "folder.badge.minus")
                .font(PersonalChatTypography.body(20, weight: .medium))
            Text(verbatim: target.name).font(PersonalChatTypography.body(14, weight: .medium)).lineLimit(3)
            Text(verbatim: target.project.path).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled)
            Text(explanation).font(PersonalChatTypography.body(13)).fixedSize(horizontal: false, vertical: true)
            if target.permanent {
                TextField(String(localized: "personal.delete.confirm", defaultValue: "Type delete to confirm", bundle: PersonalChatStrings.bundle), text: $confirmation)
                    .textFieldStyle(.roundedBorder).disabled(working)
            }
            if let error {
                Text(error).font(PersonalChatTypography.body(12)).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button(String(localized: "personal.cancel", defaultValue: "Cancel", bundle: PersonalChatStrings.bundle)) { dismiss() }.disabled(working)
                Button(title, role: target.permanent ? .destructive : nil) {
                    Task {
                        working = true
                        error = nil
                        do { try await commit(planID, confirmation); dismiss() }
                        catch { self.error = error.localizedDescription }
                        working = false
                    }
                }.disabled(working || (target.permanent && (planID == nil || confirmation != "delete")))
            }
        }.padding(26).frame(width: 460)
            .interactiveDismissDisabled(working)
            .task {
                guard target.permanent else { return }
                working = true
                do { planID = try await prepare().id }
                catch { self.error = error.localizedDescription }
                working = false
            }
    }

    private var explanation: String {
        switch target.kind {
        case .chat:
            return String(localized: "personal.delete.chatNote", defaultValue: "Stops this session and permanently deletes its transcript and uploaded attachments. Project files stay. This cannot be undone.", bundle: PersonalChatStrings.bundle)
        case .project:
            return String(localized: "personal.delete.projectNote", defaultValue: "Permanently deletes this folder on the VPS, including its files, subfolders and chat transcripts. Running sessions will stop. This cannot be undone.", bundle: PersonalChatStrings.bundle)
        case .removeProject:
            return String(localized: "personal.delete.removeNote", defaultValue: "Removes this project from the sidebar. Files, chats and running sessions stay on the VPS. You can add the folder again later. Any unsent draft in this project will be discarded.", bundle: PersonalChatStrings.bundle)
        }
    }
}
