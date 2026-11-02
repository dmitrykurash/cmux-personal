import Foundation

private actor StartupService: PersonalChatServing {
    var operations: [String] = []
    let sessionID: String
    let failHealth: Bool
    init(sessionID: String, failHealth: Bool = false) {
        self.sessionID = sessionID
        self.failHealth = failHealth
    }
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        operations.append(request.op)
        if request.op == "health" {
            if failHealth { throw PersonalChatError.sshFailed }
            return PersonalChatReply(ok: true, user: "developer", claude: true, tmux: true)
        }
        if request.op == "list" {
            return PersonalChatReply(ok: true, sessions: [.init(id: sessionID, title: "Saved session", updated: 1)])
        }
        return PersonalChatReply(ok: true, messages: [], phase: "offline")
    }
}

@main
struct StartupChecks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("personal-startup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.json")
        let repository = PersonalChatRepository(file: file)
        let first = PersonalChatProject(name: "First", path: "/home/developer/first")
        let second = PersonalChatProject(name: "Second", path: "/home/developer/second")
        let sid = UUID().uuidString.lowercased()
        let connection = PersonalChatConnection(host: "example.invalid", identityFile: "/tmp/test-key")
        try await repository.save(.init(connection: connection, projects: [first, second], selectedProjectID: second.id, selectedSessionID: sid))
        let service = StartupService(sessionID: sid)
        let model = PersonalChatModel(service: service, repository: repository)
        await model.load()
        precondition(model.connected, "Existing configuration must connect on launch")
        precondition(model.projectID == second.id && model.selectedID == sid, "Restore the saved project and conversation")
        await model.refresh()
        precondition(model.phase == "offline", "Historical sessions remain read-only until Resume")
        model.stopRefresh()
        let operations = await service.operations
        precondition(!operations.contains("start"), "Opening the app must not start/resume a CLI automatically")
        await model.load()
        let repeated = await service.operations
        precondition(repeated.filter { $0 == "health" }.count == 1, "A repeated SwiftUI task must not reconnect")
        await model.selectProject(first.id)
        let saved = try await repository.load()
        precondition(saved.selectedProjectID == first.id && saved.selectedSessionID == nil)

        model.selectSession(sid)
        model.draft = "Keep this unsent draft"
        let attachment = folder.appendingPathComponent("attachment.txt")
        model.attachments = [attachment]
        await model.setArchived(sid, archived: true, inProject: first.id)
        precondition(model.activeSessions.isEmpty && model.archivedSessions.map(\.id) == [sid], "Archive must move the chat out of the active list")
        precondition(model.selectedID == sid && model.draft == "Keep this unsent draft" && model.attachments == [attachment], "Archiving the open chat must preserve its draft and selection")
        model.stopRefresh()
        await model.reloadSessions()
        precondition(model.activeSessions.isEmpty, "Refreshing server history must not unarchive a chat")

        await model.selectProject(second.id)
        precondition(model.activeSessions.map(\.id) == [sid] && model.archivedSessions.isEmpty, "Archive membership must be scoped to its project")
        await model.setArchived(sid, archived: true, inProject: first.id)
        precondition(model.archivedSessions.isEmpty, "Stale menus must not archive into another project")
        await model.selectProject(first.id)
        let reopened = PersonalChatModel(service: service, repository: repository)
        await reopened.load()
        precondition(reopened.activeSessions.isEmpty && reopened.archivedSessions.map(\.id) == [sid], "Archive membership must survive reopening the app")
        await reopened.setArchived(sid, archived: false, inProject: first.id)
        precondition(reopened.archivedSessions.isEmpty && reopened.activeSessions.map(\.id) == [sid], "Restore must keep the same conversation ID")
        let restoredArchive = try await repository.loadArchive()
        precondition(restoredArchive[first.id.uuidString]?.contains(sid) != true, "Restore must be persisted")

        // A failed local save must leave the visible chat recoverable.
        let archiveURL = file.deletingPathExtension().appendingPathExtension("archive.json")
        try FileManager.default.removeItem(at: archiveURL)
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        await reopened.setArchived(sid, archived: true, inProject: first.id)
        precondition(reopened.error != nil && !reopened.busy && reopened.activeSessions.map(\.id) == [sid], "Save failures must not hide the chat")
        try FileManager.default.removeItem(at: archiveURL)
        let archiveOperations = await service.operations
        precondition(!archiveOperations.contains(where: { ["start", "send", "interrupt"].contains($0) }), "Archive and restore must not mutate the remote CLI")

        // Older 0.3 configurations have no saved selection fields.
        let legacy = "{\"connection\":{\"host\":\"\",\"port\":22,\"identityFile\":\"\"},\"projects\":[]}"
        try legacy.write(to: file, atomically: true, encoding: .utf8)
        let emptyService = StartupService(sessionID: sid)
        let empty = PersonalChatModel(service: emptyService, repository: repository)
        await empty.load()
        let emptyOperations = await emptyService.operations
        precondition(empty.showingSettings && emptyOperations.isEmpty, "Fresh installs should show setup without SSH")

        try await repository.save(.init(connection: connection, projects: [first]))
        let failing = PersonalChatModel(service: StartupService(sessionID: sid, failHealth: true), repository: repository)
        await failing.load()
        precondition(!failing.connected && failing.error != nil && !failing.busy, "Offline launch must remain retryable")
        let args = try connection.arguments(command: "true")
        precondition(args.contains("UseKeychain=yes") && args.contains("StrictHostKeyChecking=yes") && args.contains("ForwardAgent=no"))
        try await InteractionChecks.run()
        try await SessionLoadingChecks.run()
        try await ApprovalChecks.run()
        await GitHubChecks.run()
        print("Startup and archive checks passed: reconnect, selection restore, history-only restore, idempotent load, project isolation, archive persistence, draft preservation, restore, save failure, legacy setup, offline retry and strict SSH with Keychain.")
    }
}
