import Foundation

struct PersonalChatMessage: Codable, Identifiable, Sendable {
    var id: String
    var role: String
    var text: String
}
