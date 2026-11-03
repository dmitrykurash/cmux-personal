import Foundation

private actor ConsolePaneService: PersonalChatServing {
    private var gate: CheckedContinuation<Void, Never>?
    private var hold = false
    private(set) var handoffs = 0
    private(set) var optIns: [Bool] = []
    func holdNext() { hold = true }
    func release() { gate?.resume(); gate = nil }
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async -> PersonalChatReply {
        if request.op == "permission_handoff" {
            handoffs += 1
            if hold { hold = false; await withCheckedContinuation { gate = $0 } }
        }
        if request.op == "read" { optIns.append(request.approvalUI == true) }
        return .init(ok: true, phase: "ready")
    }
}

struct ConsolePaneChecks {
    @MainActor static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("console-pane-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = ConsolePaneService()
        let model = PersonalChatModel(service: service, repository: .init(file: folder.appendingPathComponent("config.json")))
        let project = PersonalChatProject(name: "Fixture", path: "/home/developer/projects/fixture")
        model.projects = [project]; model.projectID = project.id
        model.selectedID = UUID().uuidString; model.connected = true; model.phase = "ready"
        model.connection = .init(host: "example.invalid")
        model.draft = "Preserve this draft."
        let pane = PersonalChatConsoleState(model: model, opensForChats: false)
        pane.open()
        try await DictationChecks.wait { !pane.opening }
        model.stopRefresh()
        let firstID = pane.request?.id
        precondition(firstID != nil && pane.presented)
        pane.reconcile(); pane.reconcile()
        precondition(pane.request?.id == firstID && !pane.opening, "Refresh and layout keep the same terminal identity")
        pane.open()
        try await DictationChecks.wait { !pane.opening }
        model.stopRefresh()
        precondition(pane.request?.id == firstID, "Opening an existing pane focuses it without replacing its PTY")
        let repeatedHandoffs = await service.handoffs
        precondition(repeatedHandoffs == 2, "An explicit approval handoff still runs for an open pane")

        pane.close()
        await service.holdNext()
        pane.open()
        try await DictationChecks.wait { await service.handoffs == 3 }
        pane.close()
        await service.release()
        try await DictationChecks.wait { !pane.opening }
        model.stopRefresh()
        await model.refresh(); model.stopRefresh()
        let optIns = await service.optIns
        precondition(!pane.presented && pane.request == nil && optIns.last == true, "Closing during handoff cannot reopen the pane or leave native approvals disabled")

        await service.holdNext()
        pane.open()
        try await DictationChecks.wait { await service.handoffs == 4 }
        model.selectedID = UUID().uuidString
        pane.reconcile()
        await service.release()
        try await DictationChecks.wait { !pane.opening && pane.request != nil }
        model.stopRefresh()
        precondition(pane.request?.command.contains("cmp-" + model.selectedID!.lowercased()) == true, "Late handoff must follow the current chat")
        let changedID = pane.request?.id
        precondition(changedID != firstID && model.draft == "Preserve this draft.")

        model.phase = "offline"; pane.reconcile()
        precondition(pane.presented && pane.request == nil && !pane.opening, "Saved chats need explicit Resume; do not start them automatically")
        model.phase = "ready"; pane.reconcile()
        try await DictationChecks.wait { !pane.opening }
        model.stopRefresh()
        precondition(pane.request != nil)
        pane.close()
        // Let the close task restore routing before shutting the fixture down.
        await Task.yield(); model.stopRefresh()
        let beforeAutomatic = await service.handoffs
        let automatic = PersonalChatConsoleState(model: model)
        automatic.reconcile()
        precondition(automatic.presented && automatic.request != nil && automatic.focusID == nil)
        let automaticID = automatic.request?.id
        automatic.reconcile()
        precondition(automatic.request?.id == automaticID)
        await model.refresh(); model.stopRefresh()
        let automaticOptIns = await service.optIns
        let afterAutomatic = await service.handoffs
        precondition(beforeAutomatic == afterAutomatic && automaticOptIns.last == true, "Default opening must preserve native approvals without a permission handoff")
        automatic.close()
        automatic.reconcile(); automatic.reconcile()
        precondition(!automatic.presented && automatic.request == nil, "Closing must stick through subsequent refreshes")
        model.selectedID = UUID().uuidString
        automatic.reconcile()
        precondition(automatic.presented && automatic.request != nil && automatic.focusID == nil, "A different chat opens its console by default without taking keyboard focus")
        model.selectedID = nil
        automatic.reconcile()
        precondition(!automatic.presented && automatic.request == nil)
        let unsupported = PersonalChatConsoleState(model: model, opensForChats: false)
        model.selectedID = UUID().uuidString
        unsupported.reconcile()
        precondition(!unsupported.presented && unsupported.request == nil, "A build with another terminal provider must not show an empty pane")
        await Task.yield(); model.stopRefresh()
        print("Console pane checks passed: passive default opening, close persistence, focus intent, stable PTY identity, explicit handoffs, close/selection races, saved-session resume and draft preservation.")
    }
}
