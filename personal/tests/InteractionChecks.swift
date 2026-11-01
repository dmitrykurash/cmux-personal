import Foundation

private actor InteractionService: PersonalChatServing {
    private var sendGate: CheckedContinuation<Void, Error>?
    private var sendWaiter: CheckedContinuation<Void, Never>?
    private var sending = false
    var sentTexts: [String] = []
    var operations: [String] = []
    let failSend: Bool
    init(failSend: Bool = false) { self.failSend = failSend }
    func setMessages(_ messages: [PersonalChatMessage]) { replyMessages = messages }
    var replyMessages: [PersonalChatMessage] = []

    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        operations.append(request.op)
        if request.op == "send" {
            if failSend { throw PersonalChatError.sshFailed }
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
        model.stopRefresh()
        await model.refresh()
        precondition(model.messages.count == 1 && model.activityText != nil, "A slow transcript must not erase the local echo or working state")
        await service.setMessages([.init(id: "server-user", role: "user", text: "Show me immediately"), .init(id: "server-assistant", role: "assistant", text: "Here is the reply")])
        await model.refresh()
        precondition(model.messages.count == 2 && model.pendingSend == nil, "Acknowledgement must replace the echo without duplication")
        precondition(model.revealingMessageIDs.contains("server-assistant"), "New assistant replies should be revealed")
        model.finishReveal("server-assistant")
        await model.refresh()
        precondition(model.revealingMessageIDs.isEmpty, "Polling must not replay the reveal")

        let failingService = InteractionService(failSend: true)
        let failing = PersonalChatModel(service: failingService, repository: PersonalChatRepository(file: folder.appendingPathComponent("failure.json")))
        failing.projects = [project]; failing.projectID = project.id; failing.selectedID = UUID().uuidString
        failing.connected = true; failing.phase = "ready"; failing.draft = "Preserve on uncertain delivery"
        await failing.send(); failing.stopRefresh()
        precondition(failing.pendingSend?.state == "uncertain" && !failing.canSend, "Uncertain delivery must stay visible and must not auto-retry")
        failing.restorePendingDraft()
        precondition(failing.draft == "Preserve on uncertain delivery" && failing.pendingSend == nil)
        let failedOperations = await failingService.operations
        precondition(failedOperations.filter { $0 == "send" }.count == 1)

        let sidebar = PersonalChatSidebarState()
        precondition(!sidebar.archiveIsExpanded(project.id), "Archive starts closed")
        sidebar.toggleArchive(project.id)
        precondition(sidebar.archiveLimit(project.id) == 20)
        sidebar.loadMore(project.id)
        precondition(sidebar.archiveLimit(project.id) == 40)
        sidebar.toggleArchive(project.id)
        precondition(!sidebar.archiveIsExpanded(project.id) && sidebar.archiveLimit(project.id) == 20)
        sidebar.toggleProject(project.id)
        precondition(!sidebar.projectIsExpanded(project.id), "Collapse is independent from selected project")
        await model.refresh()
        precondition(!sidebar.projectIsExpanded(project.id) && !sidebar.archiveIsExpanded(project.id), "Refresh must not reopen folders")

        try await model.performDeletion(.init(kind: .removeProject, project: project), planID: nil, confirmation: "")
        let operations = await service.operations
        precondition(!operations.contains(where: { $0.hasPrefix("deletion_") }), "Removing from app must never delete remotely")
        precondition(model.projects.isEmpty && model.selectedID == nil)
        do {
            try await failing.performDeletion(.init(kind: .project, project: project), planID: UUID().uuidString, confirmation: "DELETE")
            preconditionFailure("Permanent deletion requires the exact confirmation")
        } catch {}
        let guardedOperations = await failingService.operations
        precondition(!guardedOperations.contains("deletion_commit"))
        print("Interaction checks passed: immediate echo, reconciliation, uncertain delivery, reveal, collapse, pagination, local removal and deletion confirmation.")
    }
}
