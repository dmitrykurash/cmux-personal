import Foundation

enum PersonalChatError: LocalizedError {
    case invalidConnection, sshFailed, missingDependencies, missingBridge, fileTooLarge
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidConnection: return String(localized: "personal.error.connection", defaultValue: "Check the SSH host, port and key path.")
        case .sshFailed: return String(localized: "personal.error.ssh", defaultValue: "SSH failed. Check the trusted host key and unlock your SSH key with ssh-add, then reconnect.")
        case .missingDependencies: return String(localized: "personal.error.dependencies", defaultValue: "The server needs Claude Code and tmux, running as developer.")
        case .missingBridge: return String(localized: "personal.error.bridge", defaultValue: "The app is missing its remote helper. Rebuild the app.")
        case .fileTooLarge: return String(localized: "personal.error.file", defaultValue: "Choose a regular file smaller than 20 MiB.")
        case .remote(let message): return message
        }
    }
}
