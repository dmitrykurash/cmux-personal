import Foundation

struct PersonalChatReply: Decodable, Sendable {
    var ok: Bool
    var error: String?
    var user: String?
    var claude: Bool?
    var tmux: Bool?
    var id: String?
    var path: String?
    var sessions: [PersonalChatSession]?
    var messages: [PersonalChatMessage]?
    var phase: String?
    var live: Bool?
}
