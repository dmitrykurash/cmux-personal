import Foundation
import Observation

struct PersonalChatGitHubState: Decodable, Sendable {
    var id: String? = nil
    var phase: String
    var deviceCode: String? = nil
}

@MainActor @Observable
final class PersonalChatGitHub {
    private(set) var state = PersonalChatGitHubState(phase: "checking")
    private(set) var busy = false
    private(set) var issue: String?
    private let service: any PersonalChatServing
    private let connection: PersonalChatConnection
    private var generation = UUID()
    init(service: any PersonalChatServing, connection: PersonalChatConnection) {
        self.service = service; self.connection = connection
    }
    func load() async { await call("github_status", token: generation) }
    func stop() { generation = UUID(); busy = false }
    func signIn() async {
        guard !busy else { return }
        let token = UUID(); generation = token
        // Preserve the ID on uncertain delivery so Retry cannot create two jobs.
        let id = state.id ?? UUID().uuidString.lowercased()
        state.id = id
        busy = true
        await call("github_begin", id: id, token: token)
        if generation == token { busy = false }
        await wait(token: token)
    }
    private func wait(token: UUID) async {
        while generation == token, !Task.isCancelled, issue == nil,
              ["starting", "waiting", "cancelling"].contains(state.phase), let id = state.id {
            await call("github_wait", id: id, token: token)
        }
    }
    func cancel() async {
        guard !busy, let id = state.id else { return }
        let token = UUID(); generation = token // Ignore an older long-poll reply.
        busy = true
        state.deviceCode = nil
        await call("github_cancel", id: id, token: token)
        if generation == token { busy = false }
        await wait(token: token)
    }
    private func call(_ op: String, id: String? = nil, token: UUID) async {
        do {
            let reply = try await service.request(.init(op: op, id: id), connection: connection)
            guard generation == token, !Task.isCancelled else { return }
            guard let result = reply.githubLogin else { throw PersonalChatError.sshFailed }
            state = result; issue = nil
            if ["failed", "cancelled", "connected"].contains(result.phase) { state.id = nil }
        } catch {
            if generation == token, !Task.isCancelled { issue = error.localizedDescription }
        }
    }
}
