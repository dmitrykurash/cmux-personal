import Foundation
import Observation

@MainActor @Observable
final class PersonalChatModel {
    var connection = PersonalChatConnection()
    var projects: [PersonalChatProject] = []
    var projectID: UUID?
    var sessions: [PersonalChatSession] = []
    var selectedID: String?
    var messages: [PersonalChatMessage] = []
    var draft = ""
    var attachments: [URL] = []
    var phase = "offline"
    var connected = false
    var busy = false
    var error: String?
    var showingSettings = false
    var projectsFolder = "/home/developer/projects"
    var hasGitHubCLI = false
    private let service: any PersonalChatServing
    private let repository: PersonalChatRepository
    private var refreshTask: Task<Void, Never>?
    private var selectionGeneration = UUID()
    private var loaded = false

    init(service: any PersonalChatServing, repository: PersonalChatRepository) {
        self.service = service
        self.repository = repository
    }

    var project: PersonalChatProject? { projects.first { $0.id == projectID } }
    var canSend: Bool { connected && !busy && phase == "ready" && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) }

    func load() async {
        if loaded {
            if connected {
                if selectedID != nil { startRefresh() }
            } else if !connection.host.isEmpty {
                await connect()
            }
            return
        }
        loaded = true
        do {
            let config = try await repository.load()
            connection = config.connection
            projects = config.projects
            projectID = projects.contains { $0.id == config.selectedProjectID } ? config.selectedProjectID : projects.first?.id
            selectedID = config.selectedSessionID
            showingSettings = connection.host.isEmpty
            if !showingSettings { await connect() }
        } catch { self.error = error.localizedDescription }
    }

    func save() async throws {
        try await repository.save(.init(connection: connection, projects: projects, selectedProjectID: projectID, selectedSessionID: selectedID))
    }

    func connect() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let previousSessionID = selectedID
        connected = false
        stopRefresh()
        selectionGeneration = UUID()
        selectedID = nil
        messages = []
        phase = "offline"
        do {
            let result = try await service.request(.init(op: "health"), connection: connection)
            guard result.user == "developer", result.claude == true, result.tmux == true else { throw PersonalChatError.missingDependencies }
            _ = try await service.request(.init(op: "install"), connection: connection)
            projectsFolder = result.path ?? projectsFolder
            hasGitHubCLI = result.githubCLI == true
            connected = true
            error = nil
            showingSettings = false
            await reloadSessions()
            if let previousSessionID, sessions.contains(where: { $0.id == previousSessionID }) {
                activateSession(previousSessionID)
            }
            if error == nil { try await save() }
        } catch {
            selectedID = previousSessionID
            self.error = error.localizedDescription
        }
    }

    func makeProjectImporter() -> PersonalChatProjectImporter {
        PersonalChatProjectImporter(service: service, connection: connection, basePath: projectsFolder, hasGitHubCLI: hasGitHubCLI)
    }

    func addProject(name: String, path: String) async throws {
        guard connected, !busy else { throw PersonalChatError.sshFailed }
        if let existing = projects.first(where: { $0.path == path }) {
            await selectProject(existing.id)
            return
        }
        let project = PersonalChatProject(name: name, path: path)
        let updated = projects + [project]
        // Persist before exposing a new sidebar row; a failed save is retryable.
        try await repository.save(.init(connection: connection, projects: updated, selectedProjectID: project.id, selectedSessionID: nil))
        projects = updated
        await selectProject(project.id)
    }

    func selectProject(_ id: UUID) async {
        guard !busy else { return }
        stopRefresh()
        selectionGeneration = UUID()
        projectID = id
        selectedID = nil
        sessions = []
        messages = []
        draft = ""
        attachments = []
        phase = "offline"
        await reloadSessions()
        do { try await save() } catch { self.error = error.localizedDescription }
    }

    func reloadSessions() async {
        guard connected, let project else { return }
        let generation = selectionGeneration
        do {
            let result = try await service.request(.init(op: "list", project: project.path), connection: connection)
            guard generation == selectionGeneration else { return }
            sessions = result.sessions ?? []
        } catch { self.error = error.localizedDescription }
    }

    func selectSession(_ id: String) {
        guard !busy else { return }
        activateSession(id)
        Task { do { try await save() } catch { self.error = error.localizedDescription } }
    }

    private func activateSession(_ id: String) {
        stopRefresh()
        selectionGeneration = UUID()
        selectedID = id
        messages = []
        draft = ""
        attachments = []
        phase = "offline"
        startRefresh()
    }

    func startSession(resume: Bool = false) async {
        guard connected, !busy, let project else { return }
        busy = true
        defer { busy = false }
        let id = resume ? selectedID ?? UUID().uuidString.lowercased() : UUID().uuidString.lowercased()
        do {
            _ = try await service.request(.init(op: "start", id: id, project: project.path, resume: resume), connection: connection)
            stopRefresh()
            selectionGeneration = UUID()
            selectedID = id
            messages = []
            phase = "starting"
            await reloadSessions()
            try await save()
            startRefresh()
        } catch { self.error = error.localizedDescription }
    }

    func refresh() async {
        guard connected, let id = selectedID, let project else { return }
        let generation = selectionGeneration
        do {
            let result = try await service.request(.init(op: "read", id: id, project: project.path), connection: connection)
            guard generation == selectionGeneration else { return }
            messages = result.messages ?? []
            phase = result.phase ?? "offline"
            if let first = messages.first(where: { $0.role == "user" }), let index = sessions.firstIndex(where: { $0.id == id }) {
                sessions[index].title = String(first.text.prefix(80))
            }
        } catch {
            guard generation == selectionGeneration, !Task.isCancelled else { return }
            connected = false
            phase = "offline"
            self.error = error.localizedDescription
            stopRefresh()
        }
    }

    func startRefresh() {
        stopRefresh()
        refreshTask = Task { [weak self] in
            await self?.refresh()
            // A two-second sampling interval is the deliberate MVP refresh rate.
            // No message retries; cancellation stops polling on window/selection changes.
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard let self, self.connected else { return }
                if !self.busy { await self.refresh() }
            }
        }
    }

    func stopRefresh() { refreshTask?.cancel(); refreshTask = nil }

    func send() async {
        guard canSend, let id = selectedID else { return }
        busy = true
        defer { busy = false }
        do {
            var text = draft
            for url in attachments {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 20 * 1024 * 1024 else { throw PersonalChatError.fileTooLarge }
                let data = try Data(contentsOf: url)
                let result = try await service.request(.init(op: "upload", id: id, name: url.lastPathComponent, data: data.base64EncodedString()), connection: connection)
                if let path = result.path { text += "\n\nAttached file on this server: " + String(reflecting: path) }
            }
            _ = try await service.request(.init(op: "send", id: id, text: text), connection: connection)
            draft = ""
            attachments = []
            phase = "busy"
            error = nil
        } catch { self.error = error.localizedDescription; phase = "attention" }
    }

    func interrupt() async {
        guard let id = selectedID else { return }
        do { _ = try await service.request(.init(op: "interrupt", id: id), connection: connection) }
        catch { self.error = error.localizedDescription }
    }
}
