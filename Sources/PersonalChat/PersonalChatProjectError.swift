import Foundation

struct PersonalChatProjectError: LocalizedError {
    let code: String
    var errorDescription: String? {
        switch code {
        case "repository_url": return String(localized: "personal.import.urlError", defaultValue: "Use an HTTPS or SSH repository URL without passwords or tokens.", bundle: PersonalChatStrings.bundle)
        case "destination_exists": return String(localized: "personal.import.exists", defaultValue: "This folder already exists. Open it as an existing folder, or choose a different name.", bundle: PersonalChatStrings.bundle)
        case "project_path": return String(localized: "personal.import.pathError", defaultValue: "Choose an accessible folder on the VPS. The parent folder must already exist.", bundle: PersonalChatStrings.bundle)
        case "git_missing": return String(localized: "personal.import.gitMissing", defaultValue: "Git is not installed on this VPS. Install Git, then reconnect.", bundle: PersonalChatStrings.bundle)
        case "git_access": return String(localized: "personal.import.accessError", defaultValue: "Git could not access this repository. Check the URL and sign in to GitHub for private repositories. SSH repositories need a trusted host and a key on the VPS.", bundle: PersonalChatStrings.bundle)
        case "import_timeout": return String(localized: "personal.import.timeout", defaultValue: "The download exceeded ten minutes. Any partial files remain in the selected folder.", bundle: PersonalChatStrings.bundle)
        default: return String(localized: "personal.import.failed", defaultValue: "Could not import the repository. Check the URL, network and free disk space. Existing files were not replaced.", bundle: PersonalChatStrings.bundle)
        }
    }
}
