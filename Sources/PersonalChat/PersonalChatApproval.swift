import Foundation

struct PersonalChatApproval: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let sessionID: String
    let project: String
    let tool: String
    let detail: String
    let expires: Double
    var questions: [PersonalChatQuestion]? = nil
    var plan: String? = nil
}

struct PersonalChatQuestion: Decodable, Equatable, Sendable, Identifiable {
    let question: String
    let options: [Option]
    var multiSelect: Bool? = nil
    var id: String { question }
    struct Option: Decodable, Equatable, Sendable, Identifiable {
        let label: String
        var description: String? = nil
        var id: String { label }
    }
}
