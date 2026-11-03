import Foundation

enum PersonalChatSpeechError: Error, LocalizedError {
    case requiresSystem, microphone, language, input, interrupted, recognition
    var errorDescription: String? {
        switch self {
        case .requiresSystem: return String(localized: "personal.voice.system", defaultValue: "On-device dictation requires macOS 26 or later.", bundle: PersonalChatStrings.bundle)
        case .microphone: return String(localized: "personal.voice.permission", defaultValue: "Allow microphone access for CheatCode in System Settings → Privacy & Security → Microphone, then try again.", bundle: PersonalChatStrings.bundle)
        case .language: return String(localized: "personal.voice.unavailable", defaultValue: "This language is not available for on-device dictation on this Mac. Choose another language.", bundle: PersonalChatStrings.bundle)
        case .input: return String(localized: "personal.voice.input", defaultValue: "The microphone is unavailable. Check your input device and try again.", bundle: PersonalChatStrings.bundle)
        case .interrupted: return String(localized: "personal.voice.interrupted", defaultValue: "Dictation was interrupted. The text already recognized is kept in your draft.", bundle: PersonalChatStrings.bundle)
        case .recognition: return String(localized: "personal.voice.failed", defaultValue: "Dictation could not finish. Check your connection if the language model needs downloading, then try again. Recognized text is kept in your draft.", bundle: PersonalChatStrings.bundle)
        }
    }
}
