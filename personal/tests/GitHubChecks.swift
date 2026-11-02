import Foundation

private actor GitHubService: PersonalChatServing {
    var requests: [PersonalChatRequest] = []
    private var held: CheckedContinuation<PersonalChatReply, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    var failBegin = false
    func failOnce() { failBegin = true }
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        requests.append(request)
        switch request.op {
        case "github_status": return .init(ok: true, githubLogin: .init(phase: "signedOut"))
        case "github_begin":
            if failBegin { failBegin = false; throw PersonalChatError.sshFailed }
            return .init(ok: true, githubLogin: .init(id: request.id, phase: "waiting", deviceCode: "ABCD-1234"))
        case "github_wait":
            return await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil }
        case "github_cancel": return .init(ok: true, githubLogin: .init(id: request.id, phase: "cancelled"))
        default: preconditionFailure("Unexpected operation")
        }
    }
    func waitForPoll() async { if held == nil { await withCheckedContinuation { waiter = $0 } } }
    func release(_ phase: String) { held?.resume(returning: .init(ok: true, githubLogin: .init(phase: phase))); held = nil }
}

struct GitHubChecks {
    @MainActor static func run() async {
        let service = GitHubService()
        let model = PersonalChatGitHub(service: service, connection: .init(host: "example.invalid"))
        await model.load()
        precondition(model.state.phase == "signedOut")
        await service.failOnce()
        await model.signIn()
        precondition(model.issue != nil && model.state.id != nil)
        let firstID = model.state.id
        let pending = Task { await model.signIn() }
        await service.waitForPoll()
        precondition(model.state.deviceCode == "ABCD-1234" && !model.busy)
        let requests = await service.requests
        precondition(requests.filter { $0.op == "github_begin" }.allSatisfy { $0.id == firstID }, "Retry must reuse an uncertain job ID")
        await model.cancel()
        await service.release("connected"); await pending.value
        precondition(model.state.phase == "cancelled" && model.state.deviceCode == nil, "An old long poll cannot overwrite Cancel")
        let closing = Task { await model.signIn() }
        await service.waitForPoll()
        model.stop()
        await service.release("connected"); await closing.value
        precondition(model.state.phase == "waiting", "A closed sheet must ignore outstanding replies")
        print("GitHub checks passed: device-code state, recoverable start, cancellation races and sheet lifetime.")
    }
}
