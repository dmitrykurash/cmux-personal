import Foundation

protocol PersonalChatSpeechServing: Sendable {
    func start(id: UUID, locale: String) async throws -> AsyncThrowingStream<PersonalChatSpeechEvent, Error>
    func stop(id: UUID) async
    func cancel(id: UUID) async
}

enum PersonalChatSpeechEvent: Sendable {
    case preparing, recording
    case transcript(String)
    case level(Float)
    case failed(PersonalChatSpeechError)
}
