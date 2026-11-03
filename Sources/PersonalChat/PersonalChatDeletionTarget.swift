import Foundation

struct PersonalChatDeletionTarget: Identifiable {
    enum Kind { case chat, project, removeProject }
    let id = UUID()
    let kind: Kind
    let project: PersonalChatProject
    var session: PersonalChatSession?
    var permanent: Bool { kind != .removeProject }
    var name: String { session?.title ?? project.name }
}
