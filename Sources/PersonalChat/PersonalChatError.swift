import Foundation

enum PersonalChatError: LocalizedError {
    case invalidConnection, sshFailed, missingDependencies, missingBridge, fileTooLarge
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidConnection: return String(localized: "personal.error.connection", defaultValue: "Check the SSH host, port and key path.", bundle: PersonalChatStrings.bundle)
        case .sshFailed: return String(localized: "personal.error.ssh", defaultValue: "SSH failed. Check the trusted host key and unlock your SSH key with ssh-add, then reconnect.", bundle: PersonalChatStrings.bundle)
        case .missingDependencies: return String(localized: "personal.error.dependencies", defaultValue: "The server needs Claude Code and tmux, running as developer.", bundle: PersonalChatStrings.bundle)
        case .missingBridge: return String(localized: "personal.error.bridge", defaultValue: "The app is missing its remote helper. Rebuild the app.", bundle: PersonalChatStrings.bundle)
        case .fileTooLarge: return String(localized: "personal.error.file", defaultValue: "Choose a regular file smaller than 20 MiB.", bundle: PersonalChatStrings.bundle)
        case .remote(let message): return message
        }
    }
}
