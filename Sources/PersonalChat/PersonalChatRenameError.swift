import Foundation

enum PersonalChatRenameError: Error, LocalizedError {
    case invalidName, unavailable

    static func normalized(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, !name.contains(where: \.isNewline),
              !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else { return nil }
        return name
    }

    var errorDescription: String? {
        switch self {
        case .invalidName: return String(localized: "personal.rename.invalid", defaultValue: "Enter a name of 1–120 characters without line breaks.", bundle: PersonalChatStrings.bundle)
        case .unavailable: return String(localized: "personal.rename.unavailable", defaultValue: "This chat is no longer available. Close this dialog and try again.", bundle: PersonalChatStrings.bundle)
        }
    }
}
