import Foundation

private actor RenameService: PersonalChatServing {
    let sid = "00000000-0000-4000-8000-000000000001"
    private(set) var operations: [String] = []
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) -> PersonalChatReply {
        operations.append(request.op)
        return .init(ok: true, user: "developer", claude: true, tmux: true,
                     sessions: [.init(id: sid, title: "Automatic title", updated: 1)], phase: "ready")
    }
}

struct RenameChecks {
    @MainActor static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cheatcode-rename-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.json")
        let repository = PersonalChatRepository(file: file)
        let service = RenameService()
        let first = PersonalChatProject(name: "First", path: "/home/developer/projects/first")
        let second = PersonalChatProject(name: "Second", path: "/home/developer/projects/second")
        try await repository.save(.init(connection: .init(host: "example.invalid"), projects: [first, second], selectedProjectID: first.id))
        let model = PersonalChatModel(service: service, repository: repository)
        await model.load()
        let sid = service.sid
        model.selectedID = sid; model.draft = "Keep this draft"; model.phase = "busy"
        try await model.renameSession(sid, to: "  Research 🔎  ", inProject: first.id)
        precondition(model.activeSessions.first?.title == "Research 🔎")
        precondition(model.selectedID == sid && model.draft == "Keep this draft" && model.phase == "busy", "Renaming cannot change the CLI turn, selection or draft")
        await model.reloadSessions()
        precondition(model.activeSessions.first?.title == "Research 🔎", "A server refresh must not overwrite a personal name")
        await model.setArchived(sid, archived: true, inProject: first.id)
        try await model.renameSession(sid, to: "Archived research", inProject: first.id)
        precondition(model.archivedSessions.first?.title == "Archived research")
        let reopened = PersonalChatModel(service: service, repository: repository)
        await reopened.load()
        precondition(reopened.archivedSessions.first?.title == "Archived research", "Names must survive reopening, including Archive")
        await reopened.setArchived(sid, archived: false, inProject: first.id)
        precondition(reopened.activeSessions.first?.title == "Archived research")
        await model.selectProject(second.id)
        precondition(model.activeSessions.first?.title == "Automatic title", "The same session ID in another project must not inherit a name")
        do { try await model.renameSession(sid, to: "Stale action", inProject: first.id); preconditionFailure("Stale rename must fail") }
        catch PersonalChatRenameError.unavailable {}
        for invalid in ["   ", "line\nbreak", String(repeating: "x", count: 121), "control\u{001b}"] {
            do { try await model.renameSession(sid, to: invalid, inProject: second.id); preconditionFailure("Invalid name accepted") }
            catch PersonalChatRenameError.invalidName {}
        }
        let titleFile = file.deletingPathExtension().appendingPathExtension("titles.json")
        let savedTitles = try Data(contentsOf: titleFile)
        try FileManager.default.removeItem(at: titleFile)
        try FileManager.default.createDirectory(at: titleFile, withIntermediateDirectories: false)
        do { try await model.renameSession(sid, to: "Unsaved", inProject: second.id); preconditionFailure("A failed save must be reported") }
        catch { precondition(model.activeSessions.first?.title == "Automatic title" && !model.busy) }
        try FileManager.default.removeItem(at: titleFile)
        try savedTitles.write(to: titleFile)
        try await model.renameSession(sid, to: "Second name", inProject: second.id)
        precondition(model.activeSessions.first?.title == "Second name", "Retry succeeds after storage recovers")
        try await model.performDeletion(.init(kind: .removeProject, project: second), planID: nil, confirmation: "")
        let remaining = try await repository.loadTitles()
        precondition(remaining[second.id.uuidString] == nil && remaining[first.id.uuidString]?[sid] == "Archived research", "Project removal cleans only that project's local names")
        let operations = await service.operations
        precondition(!operations.contains(where: { ["send", "start", "interrupt", "rename"].contains($0) }), "Personal names must not submit CLI commands or restart a session")
        model.stopRefresh(); reopened.stopRefresh()
        print("Rename checks passed: persistence, reload, archive/restore, project isolation, stale actions, validation, save failure/retry, scoped cleanup and no remote CLI mutation.")
    }
}
