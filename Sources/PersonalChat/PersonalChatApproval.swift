import Foundation

struct PersonalChatApproval: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let sessionID: String
    let project: String
    let tool: String
    let detail: String
    let expires: Double
}
