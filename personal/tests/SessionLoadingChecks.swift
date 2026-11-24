import Foundation

private actor SessionListService: PersonalChatServing {
    private var gates: [String: CheckedContinuation<PersonalChatReply, Error>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        guard request.op == "list", let path = request.project else { return PersonalChatReply(ok: true, messages: [], phase: "offline") }
        return try await withCheckedThrowingContinuation { continuation in
            gates[path] = continuation
            waiters.removeValue(forKey: path)?.resume()
        }
    }
    func waitForList(_ path: String) async {
        if gates[path] != nil { return }
        await withCheckedContinuation { waiters[path] = $0 }
    }
    func finish(_ path: String, sessions: [PersonalChatSession]) {
        gates.removeValue(forKey: path)?.resume(returning: PersonalChatReply(ok: true, sessions: sessions))
    }
    func fail(_ path: String) { gates.removeValue(forKey: path)?.resume(throwing: PersonalChatError.sshFailed) }
}

struct SessionLoadingChecks {
    @MainActor static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cheatcode-list-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = SessionListService()
        let model = PersonalChatModel(service: service, repository: PersonalChatRepository(file: folder.appendingPathComponent("config.json")))
        let first = PersonalChatProject(name: "First", path: "/home/developer/projects/first")
        let second = PersonalChatProject(name: "Second", path: "/home/developer/projects/second")
        model.projects = [first, second]; model.connected = true
        let firstLoad = Task { await model.selectProject(first.id) }
        await service.waitForList(first.path)
        precondition(model.isLoadingSessions && model.sessions.isEmpty, "Opening a project exposes loading before the server replies")
        let secondLoad = Task { await model.selectProject(second.id) }
        await service.waitForList(second.path)
        await service.finish(first.path, sessions: [.init(id: "old", title: "Wrong project", updated: 0)])
        await firstLoad.value
        precondition(model.projectID == second.id && model.isLoadingSessions && model.sessions.isEmpty, "A stale reply must neither display rows nor clear the current spinner")
        let chat = PersonalChatSession(id: "current", title: "Current project", updated: 1)
        await service.finish(second.path, sessions: [chat]); await secondLoad.value
        precondition(!model.isLoadingSessions && model.sessions.map(\.id) == [chat.id] && model.sessionsLoadError == nil)

        let failedLoad = Task { await model.reloadSessions() }
        await service.waitForList(second.path)
        precondition(model.isLoadingSessions && model.sessions.count == 1, "Refreshing retains usable existing rows")
        await service.fail(second.path); await failedLoad.value
        precondition(!model.isLoadingSessions && model.sessionsLoadError != nil && model.sessions.count == 1, "Failure stops loading, exposes retry and retains cached rows")
        let retry = Task { await model.reloadSessions() }
        await service.waitForList(second.path)
        precondition(model.sessionsLoadError == nil && model.isLoadingSessions)
        model.selectSession(chat.id) // Chat selection must not invalidate a project-list request.
        await service.finish(second.path, sessions: []); await retry.value
        model.stopRefresh()
        precondition(!model.isLoadingSessions && model.sessions.isEmpty && model.sessionsLoadError == nil, "An empty successful response is distinct from loading or failure")
        print("Session loading checks passed: pending state, stale reply isolation, retained rows, failure, retry, chat selection and empty results.")
    }
}
