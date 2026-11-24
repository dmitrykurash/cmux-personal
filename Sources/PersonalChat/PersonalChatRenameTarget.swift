import Foundation

struct PersonalChatRenameTarget: Identifiable {
    let id = UUID()
    let projectID: UUID
    let session: PersonalChatSession
}
