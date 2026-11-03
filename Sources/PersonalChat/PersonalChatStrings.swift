import Foundation

/// The personal UI is explicitly English, independent of the host app/system.
/// Keep the full catalog for upstream tooling and use its English bundle here.
enum PersonalChatStrings {
    static var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let english = Bundle(path: path) else { return .main }
        return english
    }
}
