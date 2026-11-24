#if compiler(>=6.2)
import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

/// One on-device recognizer; accepts converted audio without owning a microphone.
@available(macOS 26, *)
actor PersonalChatSpeechPipeline {
    private var analyzer: SpeechAnalyzer?
    private var results: Task<Void, Error>?
    private var installation: AssetInstallationRequest?
    private var reserved: Locale?
    private var cancelled = false

    func prepare(locale identifier: String, emit: @escaping @Sendable (PersonalChatSpeechEvent) -> Void) async throws -> AVAudioFormat {
        let requested = Locale(identifier: identifier)
        let module: any SpeechModule
        let locale: Locale
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested),
           await AssetInventory.status(forModules: [SpeechTranscriber(locale: supported, preset: .progressiveTranscription)]) != .unsupported {
            let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
            module = transcriber; locale = supported
            results = Task {
                do {
                var finalized = ""
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let text = String(result.text.characters)
                    emit(.transcript(finalized + text))
                    if result.isFinal { finalized += text }
                }
                } catch {
                    if !Task.isCancelled { emit(.failed(.recognition)) }
                    throw error
                }
            }
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
            let transcriber = DictationTranscriber(locale: supported, preset: .progressiveLongDictation)
            guard await AssetInventory.status(forModules: [transcriber]) != .unsupported else { throw PersonalChatSpeechError.language }
            module = transcriber; locale = supported
            results = Task {
                do {
                var finalized = ""
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let text = String(result.text.characters)
                    emit(.transcript(finalized + text))
                    if result.isFinal { finalized += text }
                }
                } catch {
                    if !Task.isCancelled { emit(.failed(.recognition)) }
                    throw error
                }
            }
        } else { throw PersonalChatSpeechError.language }
        try checkCancellation()
        if !(await AssetInventory.reservedLocales).contains(locale) {
            guard try await AssetInventory.reserve(locale: locale) else { throw PersonalChatSpeechError.language }
            reserved = locale
        }
        try checkCancellation()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            installation = request
            try await request.downloadAndInstall()
            installation = nil
        }
        try checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw PersonalChatSpeechError.input }
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)
        try checkCancellation()
        return format
    }

    func run(_ input: AsyncThrowingStream<AnalyzerInput, Error>) async throws {
        try checkCancellation()
        guard let analyzer else { throw PersonalChatSpeechError.recognition }
        if let end = try await analyzer.analyzeSequence(input) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            results?.cancel()
            await analyzer.cancelAndFinishNow()
            await releaseReservation()
            return
        }
        try await results?.value
        await releaseReservation()
    }
    func cancel() async {
        cancelled = true
        installation?.progress.cancel(); installation = nil
        results?.cancel(); results = nil
        await analyzer?.cancelAndFinishNow(); analyzer = nil
        await releaseReservation()
    }
    private func checkCancellation() throws {
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
    }
    private func releaseReservation() async {
        if let locale = reserved { reserved = nil; _ = await AssetInventory.release(reservedLocale: locale) }
    }
}
#endif
