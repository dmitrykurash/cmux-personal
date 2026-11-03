import Foundation

struct PersonalChatPendingSend {
    var message: PersonalChatMessage
    let originalDraft: String
    let attachments: [URL]
    let previousMessageIDs: Set<String>
    var wireText: String
    var state = "sending"
}
