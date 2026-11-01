import Foundation

private actor InteractionService: PersonalChatServing {
    private var sendGate: CheckedContinuation<Void, Error>?
    private var sendWaiter: CheckedContinuation<Void, Never>?
    private var sending = false
    var sentTexts: [String] = []
    var replyMessages: [PersonalChatMessage] = []

    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        if request.op == "send" {
            sentTexts.append(request.text ?? "")
            try await withCheckedThrowingContinuation { continuation in
                sendGate = continuation
                sending = true
                sendWaiter?.resume()
                sendWaiter = nil
            }
        }
        return PersonalChatReply(ok: true, messages: replyMessages, phase: "ready")
    }
    func waitForSend() async {
        if sending { return }
        await withCheckedContinuation { sendWaiter = $0 }
    }
    func completeSend() { sendGate?.resume(); sendGate = nil }
}

struct InteractionChecks {
    @MainActor static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cheatcode-interactions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = InteractionService()
        let model = PersonalChatModel(service: service, repository: PersonalChatRepository(file: folder.appendingPathComponent("config.json")))
        let project = PersonalChatProject(name: "Test", path: "/home/developer/projects/test")
        model.projects = [project]
        model.projectID = project.id
        model.selectedID = UUID().uuidString.lowercased()
        model.connected = true
        model.phase = "ready"
        model.draft = "Show me immediately"
        let task = Task { await model.send() }
        await service.waitForSend()
        guard model.messages.contains(where: { $0.role == "user" && $0.text == "Show me immediately" }), model.draft.isEmpty else {
            await service.completeSend()
            await task.value
            throw NSError(domain: "InteractionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sending must immediately show the user bubble and clear the composer before SSH replies"])
        }
        await service.completeSend()
        await task.value
        print("Immediate-send behavior passed.")
    }
}
