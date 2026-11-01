import Foundation

protocol PersonalChatServing: Sendable {
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply
}
