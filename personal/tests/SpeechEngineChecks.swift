// Opt-in integration check: synthetic audio only, never opens a microphone.
import Foundation
@preconcurrency import AVFoundation
import Speech
import os

@main
struct SpeechEngineChecks {
    static func main() async throws {
        guard #available(macOS 26, *) else { return }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
        let locale = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "en-US"
        let pipeline = PersonalChatSpeechPipeline()
        let transcript = OSAllocatedUnfairLock(initialState: "")
        let format = try await pipeline.prepare(locale: locale) { event in
            if case .transcript(let text) = event { transcript.withLock { $0 = text } }
        }
        let converter = try PersonalChatSpeechAudioConverter(from: file.processingFormat, to: format)
        let (input, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
            try file.read(into: buffer)
            let converted = try converter.convert(buffer)
            if converted.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
        continuation.finish()
        do { try await pipeline.run(input) }
        catch { await pipeline.cancel(); throw error }
        await pipeline.cancel()
        let text = transcript.withLock { $0 }
        print("Synthetic transcript: \(text)")
        let expected = locale == "ru-RU" ? ["сообщение", "черновик"] : ["draft", "message"]
        precondition(expected.allSatisfy { text.lowercased().contains($0) }, "The real on-device pipeline must transcribe the synthetic fixture")
        print("On-device audio check passed without microphone access.")
    }
}
