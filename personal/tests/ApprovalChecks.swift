import Foundation

private actor ApprovalService: PersonalChatServing {
    var approvals: [PersonalChatApproval]
    var decisions: [PersonalChatRequest] = []
    private var decisionGate: CheckedContinuation<Void, Never>?
    private var decisionWaiter: CheckedContinuation<Void, Never>?
    private var readGate: CheckedContinuation<Void, Never>?
    private var readWaiter: CheckedContinuation<Void, Never>?
    private var holdRead = false
    var loseReply = false
    var readOptIns: [Bool] = []
    var handoffs = 0
    init(_ approvals: [PersonalChatApproval]) { self.approvals = approvals }
    func setApprovals(_ values: [PersonalChatApproval]) { approvals = values }
    func setLoseReply() { loseReply = true }
    func holdNextRead() { holdRead = true }
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        if request.op == "read" {
            precondition(request.approvalUI != nil)
            readOptIns.append(request.approvalUI == true)
            let snapshot = approvals
            if holdRead {
                holdRead = false
                await withCheckedContinuation { readGate = $0; readWaiter?.resume(); readWaiter = nil }
            }
            return .init(ok: true, messages: [], phase: snapshot.isEmpty ? "busy" : "permission", approvals: snapshot)
        }
        if request.op == "permission_handoff" { handoffs += 1; approvals = [] }
        if request.op == "permission_decide" {
            decisions.append(request)
            await withCheckedContinuation { decisionGate = $0; decisionWaiter?.resume(); decisionWaiter = nil }
            approvals.removeAll { $0.id == request.approvalID }
            if loseReply { throw PersonalChatError.sshFailed }
        }
        return .init(ok: true)
    }
    func waitForDecision() async { if decisionGate == nil { await withCheckedContinuation { decisionWaiter = $0 } } }
    func waitForRead() async { if readGate == nil { await withCheckedContinuation { readWaiter = $0 } } }
    func releaseDecision() { decisionGate?.resume(); decisionGate = nil }
    func releaseRead() { readGate?.resume(); readGate = nil }
}

struct ApprovalChecks {
    @MainActor static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cheatcode-approvals-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sid = UUID().uuidString
        let project = PersonalChatProject(name: "Fixture", path: "/home/developer/projects/fixture")
        let approval = PersonalChatApproval(id: UUID().uuidString, sessionID: sid, project: project.path, tool: "Bash", detail: "{\"command\":\"git --version\"}", expires: Date().timeIntervalSince1970 + 540)
        let service = ApprovalService([approval])
        let model = PersonalChatModel(service: service, repository: PersonalChatRepository(file: folder.appendingPathComponent("config.json")))
        model.projects = [project]; model.projectID = project.id; model.selectedID = sid; model.connected = true
        model.draft = "Keep my draft"
        await model.refresh()
        precondition(model.approvals == [approval] && model.phase == "permission" && !model.canSend && model.activityText == nil)
        await service.holdNextRead()
        let staleRead = Task { await model.refresh() }
        await service.waitForRead()
        let allow = Task { await model.decideApproval(approval, decision: "allow", answers: ["Choose": "Alpha"]) }
        await service.waitForDecision()
        precondition(model.busy && model.approvals == [approval], "Keep the card disabled until SSH acknowledges the decision")
        let duplicate = await model.decideApproval(approval, decision: "allow")
        precondition(!duplicate)
        await service.releaseDecision()
        let allowed = await allow.value
        model.stopRefresh()
        await service.releaseRead(); await staleRead.value
        precondition(allowed && model.approvals.isEmpty && model.draft == "Keep my draft", "A stale read cannot resurrect an answered card or erase the draft")
        let sent = await service.decisions
        precondition(sent.count == 1 && sent[0].id == sid && sent[0].project == project.path && sent[0].approvalID == approval.id && sent[0].decision == "allow")
        precondition(sent[0].answers == ["Choose": "Alpha"], "Question answers travel with the exact request")
        let stale = await model.decideApproval(approval, decision: "allow")
        precondition(!stale)

        await service.setApprovals([approval]); await model.refresh()
        await service.setLoseReply()
        let lost = Task { await model.decideApproval(approval, decision: "deny") }
        await service.waitForDecision(); await service.releaseDecision()
        let confirmed = await lost.value
        model.stopRefresh()
        precondition(!confirmed && model.approvalError != nil && model.approvals.isEmpty && model.connected, "Uncertain delivery re-reads the source, without approving again")
        let afterLoss = await service.decisions
        precondition(afterLoss.count == 2 && afterLoss.last?.decision == "deny")

        // An unseen request still needs an explicit handoff, and subsequent reads
        // must not immediately reclaim it while the user is in Terminal.
        let handedOff = await model.releaseApprovalsToTerminal()
        model.stopRefresh(); await model.refresh()
        let handoffs = await service.handoffs
        let readOptIns = await service.readOptIns
        precondition(handedOff && handoffs == 1 && readOptIns.last == false)

        await service.setApprovals([approval])
        model.selectedID = UUID().uuidString
        await model.refresh()
        precondition(model.approvals.isEmpty, "Wrong-session replies must never create approval buttons")
        let wrongChat = await model.decideApproval(approval, decision: "allow")
        precondition(!wrongChat)
        model.selectedID = sid
        await model.refresh()
        await model.selectProject(project.id)
        precondition(model.approvals.isEmpty && model.approvalError == nil, "Switching projects clears permission state")
        model.stopRefresh()
        print("Approval checks passed: exact scope, busy and duplicate guards, stale read fence, uncertain delivery without retry, draft preservation and selection cleanup.")
    }
}
