import Foundation

struct PersonalChatRequest: Encodable, Sendable {
    var op: String
    var id: String? = nil
    var project: String? = nil
    var resume: Bool? = nil
    var text: String? = nil
    var name: String? = nil
    var data: String? = nil
    var mode: String? = nil
    var repository: String? = nil
    var source: String? = nil
    var confirmation: String? = nil
    var approvalUI: Bool? = nil
    var approvalID: String? = nil
    var decision: String? = nil
}
