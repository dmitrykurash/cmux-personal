#if compiler(>=6.2)
import Foundation

@available(macOS 26, *)
actor PersonalChatSpeechSession {
    private let pipeline = PersonalChatSpeechPipeline()
    private var microphone: PersonalChatSpeechMicrophone?
    private var output: AsyncThrowingStream<PersonalChatSpeechEvent, Error>.Continuation?
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var cancelled = false

    func start(locale: String) -> AsyncThrowingStream<PersonalChatSpeechEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<PersonalChatSpeechEvent, Error>.makeStream()
        guard !cancelled else { continuation.finish(throwing: CancellationError()); return stream }
        output = continuation
        continuation.yield(.preparing)
        task = Task {
            do {
                let format = try await pipeline.prepare(locale: locale) { continuation.yield($0) }
                try Task.checkCancellation()
                let microphone = await PersonalChatSpeechMicrophone()
                self.microphone = microphone
                let input = try await microphone.start(format: format) { continuation.yield($0) }
                try Task.checkCancellation()
                continuation.yield(.recording)
                try await pipeline.run(input)
                await finish()
            } catch {
                await finish(error: error is CancellationError ? nil : (error as? PersonalChatSpeechError ?? .recognition))
            }
        }
        return stream
    }

    func stop() async {
        guard !cancelled, output != nil else { return }
        await microphone?.stop()
        guard !cancelled, output != nil else { return }
        deadline = Task {
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            await finish(error: PersonalChatSpeechError.interrupted)
        }
    }

    func cancel() async { await finish() }

    private func finish(error: Error? = nil) async {
        cancelled = true
        task?.cancel(); task = nil
        deadline?.cancel(); deadline = nil
        // Stop capture before waiting for the recognizer to release its models.
        await microphone?.stop(); microphone = nil
        if let error { output?.finish(throwing: error) } else { output?.finish() }
        output = nil
        await pipeline.cancel()
    }
}
#endif
