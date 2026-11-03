import Foundation

actor DictationFixture: PersonalChatSpeechServing {
    private var streams: [UUID: AsyncThrowingStream<PersonalChatSpeechEvent, Error>.Continuation] = [:]
    private(set) var ids: [UUID] = []
    private(set) var languages: [String] = []
    private(set) var stopped: [UUID] = []
    func start(id: UUID, locale: String) -> AsyncThrowingStream<PersonalChatSpeechEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<PersonalChatSpeechEvent, Error>.makeStream()
        streams[id] = continuation; ids.append(id); languages.append(locale)
        continuation.yield(.preparing)
        return stream
    }
    func emit(_ event: PersonalChatSpeechEvent, id: UUID) { streams[id]?.yield(event) }
    func finish(_ id: UUID) { streams[id]?.finish() }
    func stop(id: UUID) { stopped.append(id) }
    // Deliberately retain old streams to test late callbacks after cancellation.
    func cancel(id: UUID) {}
}

private actor DictationChatFixture: PersonalChatServing {
    private(set) var sends = 0
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) -> PersonalChatReply {
        if request.op == "send" { sends += 1 }
        return .init(ok: true, phase: "ready")
    }
}

struct DictationChecks {
    @MainActor static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "DictationChecks.timeout", code: 1) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @MainActor static func run() async throws {
        let service = DictationFixture()
        let speech = PersonalChatDictation(service: service)
        let chat = DictationChatFixture()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let model = PersonalChatModel(service: chat, repository: .init(file: file), dictation: speech)
        model.connected = true; model.phase = "ready"; model.selectedID = "first"
        model.draft = "Existing draft:"
        model.startDictation(); model.startDictation()
        precondition(!model.canSend && speech.phase == .preparing)
        try await wait { await service.ids.count == 1 }
        let first = await service.ids[0]
        await service.emit(.recording, id: first)
        await service.emit(.transcript("hello"), id: first)
        try await wait { model.draft == "Existing draft: hello" }
        await service.emit(.transcript("hello world"), id: first)
        try await wait { model.draft == "Existing draft: hello world" }
        await model.send()
        let sendsWhileRecording = await chat.sends
        precondition(sendsWhileRecording == 0, "Enter/Send must not dispatch a partial dictation")
        speech.stop()
        precondition(speech.phase == .finishing && !model.canSend)
        try await wait { await service.stopped == [first] }
        await service.emit(.transcript("Hello world."), id: first)
        await service.finish(first)
        try await wait { !speech.active }
        precondition(model.draft == "Existing draft: Hello world." && model.canSend)
        let sendsAfterStop = await chat.sends
        precondition(sendsAfterStop == 0, "Stop must leave the transcript editable, never auto-send")

        speech.locale = "ru-RU"
        model.startDictation()
        try await wait { await service.ids.count == 2 }
        let second = await service.ids[1]
        await service.emit(.recording, id: second)
        await service.emit(.transcript("Привет"), id: second)
        try await wait { model.draft.hasSuffix("Привет") }
        speech.cancel()
        precondition(model.draft == "Existing draft: Hello world." && !speech.active)
        let languages = await service.languages
        precondition(languages == ["en-US", "ru-RU"])

        model.startDictation()
        try await wait { await service.ids.count == 3 }
        let third = await service.ids[2]
        await service.emit(.transcript("recognized"), id: third)
        try await wait { model.draft.hasSuffix("recognized") }
        await service.emit(.failed(.microphone), id: third)
        try await wait { !speech.active }
        precondition(speech.issue != nil && model.draft.hasSuffix("recognized"), "Failures preserve recognized text")
        speech.dismissIssue()
        model.startDictation()
        try await wait { await service.ids.count == 4 }
        let fourth = await service.ids[3]
        model.selectSession("another")
        model.stopRefresh()
        precondition(!speech.active && model.draft.isEmpty)
        await service.emit(.transcript("late old words"), id: fourth)
        await service.emit(.transcript("late cancelled words"), id: second)
        await service.finish(fourth); await service.finish(second)
        model.draft = "New chat draft"
        model.startDictation()
        try await wait { await service.ids.count == 5 }
        let fifth = await service.ids[4]
        await service.emit(.recording, id: fifth)
        await service.emit(.transcript("new words"), id: fifth)
        try await wait { model.draft == "New chat draft new words" }
        speech.cancel()
        precondition(model.draft == "New chat draft", "Late callbacks cannot cross into a new chat or recording")
        await service.finish(fifth)
        print("Dictation checks passed: live revisions, existing draft, stop/finalization, cancellation, language choice, recoverable errors, no automatic sending and chat-switch races.")
    }
}
