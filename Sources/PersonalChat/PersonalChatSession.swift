import Foundation

struct PersonalChatSession: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var updated: Double
}
