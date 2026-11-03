import Foundation
@preconcurrency import AVFoundation
import Speech
import os

@main
struct MicrophoneCallbackChecks {
    @MainActor static func main() async throws {
        guard #available(macOS 26, *) else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let source = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let target = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: source)
        // Offline rendering drives Apple's real tap queue without a microphone,
        // speakers, TCC permission, or uploading any audio.
        try engine.enableManualRenderingMode(.offline, format: source, maximumFrameCount: 4096)
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
        let level = OSAllocatedUnfairLock(initialState: Float.zero)
        try PersonalChatSpeechMicrophone.installTap(on: engine.mainMixerNode, source: source, format: target, continuation: continuation) { event in
            dispatchPrecondition(condition: .notOnQueue(.main))
            if case .level(let value) = event { level.withLock { $0 = value }; continuation.finish() }
        }
        defer { engine.stop(); engine.mainMixerNode.removeTap(onBus: 0) }
        let fixture = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 8192)!
        fixture.frameLength = 8192
        for index in 0..<8192 { fixture.floatChannelData![0][index] = 0.1 }
        player.scheduleBuffer(fixture, completionHandler: nil)
        try engine.start()
        player.play()
        let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        for _ in 0..<2 {
            let status = try engine.renderOffline(4096, to: output)
            precondition(status == .success, "Offline audio must actually render")
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            continuation.finish(throwing: PersonalChatSpeechError.interrupted)
        }
        defer { timeout.cancel() }
        var frames = 0
        for try await input in stream {
            frames += Int(input.buffer.frameLength)
            precondition(input.buffer.format.sampleRate == 16000)
            if let samples = input.buffer.floatChannelData?[0] {
                precondition((0..<Int(input.buffer.frameLength)).contains { abs(samples[$0]) > 0.01 }, "The handoff must contain converted synthetic audio")
            }
        }
        precondition(frames > 0 && level.withLock { $0 } > 0, "Apple's real tap callback must deliver audio and meter events off MainActor")
        print("Microphone callback check passed: production tap runs on Apple's audio queue and delivers converted synthetic audio, without microphone access.")
    }
}
