import Foundation

actor PersonalChatSpeechService: PersonalChatSpeechServing {
    #if compiler(>=6.2)
    private var current: (id: UUID, session: AnyObject)?
    #endif
    func start(id: UUID, locale: String) async throws -> AsyncThrowingStream<PersonalChatSpeechEvent, Error> {
        try Task.checkCancellation()
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let old = current?.session as? PersonalChatSpeechSession
            let session = PersonalChatSpeechSession()
            current = (id, session)
            await old?.cancel()
            guard !Task.isCancelled, current?.id == id else {
                await session.cancel()
                throw CancellationError()
            }
            return await session.start(locale: locale)
        }
        #endif
        throw PersonalChatSpeechError.requiresSystem
    }
    func stop(id: UUID) async {
        #if compiler(>=6.2)
        if #available(macOS 26, *), current?.id == id, let session = current?.session as? PersonalChatSpeechSession { await session.stop() }
        #endif
    }
    func cancel(id: UUID) async {
        #if compiler(>=6.2)
        if #available(macOS 26, *), current?.id == id, let session = current?.session as? PersonalChatSpeechSession {
            current = nil
            await session.cancel()
        }
        #endif
    }
}
