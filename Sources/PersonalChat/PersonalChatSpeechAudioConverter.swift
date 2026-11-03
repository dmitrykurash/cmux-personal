#if compiler(>=6.2)
@preconcurrency import AVFoundation
import os

/// Used only by one serial audio callback. Every result owns its sample storage.
final class PersonalChatSpeechAudioConverter: @unchecked Sendable {
    private var converter: AVAudioConverter
    private let format: AVAudioFormat

    init(from input: AVAudioFormat, to output: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else { throw PersonalChatSpeechError.input }
        self.converter = converter
        format = output
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        // The engine can negotiate its tap format after the graph starts. Use
        // the delivered buffer's format, not an earlier node-format snapshot.
        if converter.inputFormat != input.format {
            guard let updated = AVAudioConverter(from: input.format, to: format) else { throw PersonalChatSpeechError.input }
            converter = updated
        }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw PersonalChatSpeechError.input }
        let supply = OSAllocatedUnfairLock(initialState: (buffer: input, supplied: false))
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            let next: AVAudioPCMBuffer? = supply.withLockUnchecked { value in
                if value.supplied { return nil }
                value.supplied = true
                return value.buffer
            }
            state.pointee = next == nil ? .noDataNow : .haveData
            return next
        }
        guard status != .error, error == nil else { throw PersonalChatSpeechError.input }
        return output
    }
}
#endif
