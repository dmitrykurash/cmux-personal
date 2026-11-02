import Foundation

struct PersonalChatReply: Decodable, Sendable {
    var ok: Bool
    var error: String?
    var code: String?
    var git: Bool?
    var githubCLI: Bool?
    var directories: [String]?
    var parent: String?
    var user: String?
    var claude: Bool?
    var tmux: Bool?
    var id: String?
    var path: String?
    var sessions: [PersonalChatSession]?
    var messages: [PersonalChatMessage]?
    var phase: String?
    var live: Bool?
    var count: Int?
    var githubLogin: PersonalChatGitHubState?
    var approvals: [PersonalChatApproval]?
}
