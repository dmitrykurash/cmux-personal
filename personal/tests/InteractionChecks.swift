import Foundation

private actor InteractionService: PersonalChatServing {
    private var sendGate: CheckedContinuation<Void, Error>?
    private var sendWaiter: CheckedContinuation<Void, Never>?
    private var sending = false
    var sentTexts: [String] = []
    var operations: [String] = []
    let localCommand: Bool
    let failSend: Bool
    init(failSend: Bool = false, localCommand: Bool = false) { self.failSend = failSend; self.localCommand = localCommand }
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
        return PersonalChatReply(ok: true, messages: replyMessages, phase: localCommand ? "console" : "ready")
    }
    func waitForSend() async {
        if sending { return }
        await withCheckedContinuation { sendWaiter = $0 }
    }
    func completeSend() { sendGate?.resume(); sendGate = nil }
}

private actor RecoveryService: PersonalChatServing {
    var reads = 0
    var operations: [String] = []
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        operations.append(request.op)
        reads += 1
        if reads == 1 { throw PersonalChatError.sshFailed }
        return PersonalChatReply(ok: true, messages: [.init(id: "recovered", role: "assistant", text: "Recovered reply")], phase: "ready")
    }
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

        let commandService = InteractionService(localCommand: true)
        let commandModel = PersonalChatModel(service: commandService, repository: PersonalChatRepository(file: folder.appendingPathComponent("command.json")))
        commandModel.projects = [project]; commandModel.projectID = project.id; commandModel.selectedID = UUID().uuidString
        commandModel.connected = true; commandModel.phase = "ready"; commandModel.draft = "/usage"
        let commandTask = Task { await commandModel.send() }
        await commandService.waitForSend(); await commandService.completeSend(); await commandTask.value
        commandModel.stopRefresh(); await commandModel.refresh()
        precondition(commandModel.consolePresentationID != nil, "The acknowledged slash command opens its existing CLI screen automatically")
        precondition(commandModel.pendingSend == nil && commandModel.activityText == nil, "A local CLI screen must not wait forever for a chat transcript or show Claude working")
        commandModel.stopRefresh()

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

        let recoveryService = RecoveryService()
        let recovering = PersonalChatModel(service: recoveryService, repository: PersonalChatRepository(file: folder.appendingPathComponent("recovery.json")))
        recovering.projects = [project]; recovering.projectID = project.id; recovering.selectedID = UUID().uuidString
        recovering.connected = true; recovering.phase = "ready"; recovering.draft = "Keep my unsent draft"
        recovering.messages = [.init(id: "cached", role: "assistant", text: "Cached reply")]
        await recovering.refresh()
        precondition(!recovering.canSend && recovering.messages.first?.id == "cached", "A failed poll preserves cached messages and disables sends")
        await recovering.refresh()
        precondition(recovering.connected && recovering.phase == "ready" && recovering.messages.first?.id == "recovered", "The next successful poll must recover without manual Connect")
        precondition(recovering.error == nil && recovering.draft == "Keep my unsent draft", "Transient SSH failures must not leave a modal or erase the draft")
        let recoveryOperations = await recoveryService.operations
        precondition(recoveryOperations == ["read", "read"], "Recovery only reads; it never repeats a send, resumes Claude or reinstalls the bridge")
        recovering.stopRefresh()

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
