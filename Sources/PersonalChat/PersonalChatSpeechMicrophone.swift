#if compiler(>=6.2)
import AppKit
@preconcurrency import AVFoundation
import Speech

@available(macOS 26, *)
@MainActor
final class PersonalChatSpeechMicrophone {
    private let engine = AVAudioEngine()
    private var tapped = false
    private var observer: NSObjectProtocol?
    private var input: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?

    func start(format: AVAudioFormat, emit: @escaping @Sendable (PersonalChatSpeechEvent) -> Void) async throws -> AsyncThrowingStream<AnalyzerInput, Error> {
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
        default: allowed = false
        }
        try Task.checkCancellation()
        guard allowed else { throw PersonalChatSpeechError.microphone }
        guard NSApp.isActive else { throw PersonalChatSpeechError.interrupted }
        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0 else { throw PersonalChatSpeechError.input }
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(128))
        input = continuation
        try Self.installTap(on: node, source: source, format: format, continuation: continuation, emit: emit)
        tapped = true
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
            continuation.finish(throwing: PersonalChatSpeechError.interrupted)
        }
        do { engine.prepare(); try engine.start() }
        catch { stop(); throw PersonalChatSpeechError.input }
        return stream
    }

    // The audio handoff owns the converter and copies every buffer before yielding.
    static func installTap(on node: AVAudioNode, source: AVAudioFormat, format: AVAudioFormat,
                        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
                        emit: @escaping @Sendable (PersonalChatSpeechEvent) -> Void) throws {
        let converter = try PersonalChatSpeechAudioConverter(from: source, to: format)
        node.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            do {
                let converted = try converter.convert(buffer)
                if converted.frameLength > 0 {
                    if case .dropped = continuation.yield(AnalyzerInput(buffer: converted)) {
                        continuation.finish(throwing: PersonalChatSpeechError.interrupted)
                    }
                }
                if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                    var sum: Float = 0
                    for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
                    emit(.level(min(1, sqrt(sum / Float(buffer.frameLength)) * 6)))
                }
            } catch { continuation.finish(throwing: PersonalChatSpeechError.input) }
        }
    }

    func stop() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        input?.finish(); input = nil
    }
}
#endif
