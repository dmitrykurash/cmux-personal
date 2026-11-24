import Foundation

enum PersonalChatProjectSource: String, CaseIterable, Identifiable {
    case clone, empty, existing
    var id: Self { self }
    var label: String {
        switch self {
        case .clone: return String(localized: "personal.import.repository", defaultValue: "Repository", bundle: PersonalChatStrings.bundle)
        case .empty: return String(localized: "personal.import.newFolder", defaultValue: "New folder", bundle: PersonalChatStrings.bundle)
        case .existing: return String(localized: "personal.import.existingFolder", defaultValue: "Existing folder", bundle: PersonalChatStrings.bundle)
        }
    }
}
