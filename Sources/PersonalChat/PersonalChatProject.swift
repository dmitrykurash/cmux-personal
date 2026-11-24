import Foundation

struct PersonalChatProject: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var path: String
}
