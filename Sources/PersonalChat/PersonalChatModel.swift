import Foundation
import Observation

@MainActor @Observable
final class PersonalChatModel {
    var connection = PersonalChatConnection()
    var projects: [PersonalChatProject] = []
    var projectID: UUID?
    var sessions: [PersonalChatSession] = []
    private(set) var isLoadingSessions = false
    private(set) var sessionsLoadError: String?
    private var sessionListRequestID: UUID?
    private(set) var archivedSessionIDs: [String: Set<String>] = [:]
    private(set) var sessionTitles: [String: [String: String]] = [:]
    var selectedID: String?
    var messages: [PersonalChatMessage] = []
    private(set) var approvals: [PersonalChatApproval] = []
    private(set) var approvalError: String?
    private var nativeApprovalsEnabled = true
    private(set) var pendingSend: PersonalChatPendingSend?
    private(set) var revealingMessageIDs: Set<String> = []
    private var remoteMessageIDs: Set<String> = []
    private var transcriptLoaded = false
    private var awaitingReply = false
    private(set) var consoleCommand: String?
    var consolePresentationID: UUID?
    var draft = ""
    let dictation: PersonalChatDictation?
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

    func makeGitHub() -> PersonalChatGitHub { PersonalChatGitHub(service: service, connection: connection) }

    init(service: any PersonalChatServing, repository: PersonalChatRepository, dictation: PersonalChatDictation? = nil) {
        self.service = service
        self.repository = repository
        self.dictation = dictation
    }

    var project: PersonalChatProject? { projects.first { $0.id == projectID } }
    var activeSessions: [PersonalChatSession] { namedSessions.filter { !isArchived($0.id) } }
    var archivedSessions: [PersonalChatSession] { namedSessions.filter { isArchived($0.id) } }
    var canSend: Bool { connected && !busy && dictation?.active != true && pendingSend == nil && phase == "ready" && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) }

    func startDictation() {
        guard !busy, selectedID != nil else { return }
        dictation?.start(draft: draft) { [weak self] text in self?.draft = text }
    }

    private var namedSessions: [PersonalChatSession] {
        let names = projectID.flatMap { sessionTitles[$0.uuidString] } ?? [:]
        return sessions.map { session in
            var named = session
            if let title = names[session.id] { named.title = title }
            return named
        }
    }

    func renameSession(_ id: String, to title: String, inProject targetProjectID: UUID) async throws {
        guard !busy, projectID == targetProjectID, sessions.contains(where: { $0.id == id }) else {
            throw PersonalChatRenameError.unavailable
        }
        guard let name = PersonalChatRenameError.normalized(title) else { throw PersonalChatRenameError.invalidName }
        busy = true
        defer { busy = false }
        var updated = sessionTitles
        updated[targetProjectID.uuidString, default: [:]][id] = name
        // Commit before updating the sidebar; a failed write leaves the old name.
        try await repository.saveTitles(updated)
        sessionTitles = updated
    }

    func isArchived(_ id: String) -> Bool {
        guard let projectID else { return false }
        return archivedSessionIDs[projectID.uuidString]?.contains(id) == true
    }

    func setArchived(_ id: String, archived: Bool, inProject idOfProject: UUID) async {
        guard !busy, projectID == idOfProject, sessions.contains(where: { $0.id == id }) else { return }
        busy = true
        defer { busy = false }
        var updated = archivedSessionIDs
        if archived { updated[idOfProject.uuidString, default: []].insert(id) }
        else { updated[idOfProject.uuidString]?.remove(id) }
        do {
            try await repository.saveArchive(updated)
            archivedSessionIDs = updated
            // Keep the current conversation and unsent draft intact. Archiving only
            // organizes the sidebar; it never stops a CLI or edits server history.
        } catch { self.error = error.localizedDescription }
    }

    var activityText: String? {
        if !approvals.isEmpty || (phase == "console" && pendingSend?.state != "uncertain") { return nil }
        if let pendingSend {
            if pendingSend.state == "uncertain" { return String(localized: "personal.delivery.uncertain", defaultValue: "Delivery unconfirmed. Check the terminal before sending again.", bundle: PersonalChatStrings.bundle) }
            if pendingSend.state == "sending" {
                return pendingSend.attachments.isEmpty
                    ? String(localized: "personal.delivery.sending", defaultValue: "Sending…", bundle: PersonalChatStrings.bundle)
                    : String(localized: "personal.delivery.uploading", defaultValue: "Uploading attachments…", bundle: PersonalChatStrings.bundle)
            }
        }
        guard phase == "busy" || awaitingReply else { return nil }
        if let lastUser = messages.lastIndex(where: { $0.role == "user" }),
           let tool = messages.suffix(from: lastUser).last(where: { $0.role == "tool" }) {
            return String(format: String(localized: "personal.delivery.tool", defaultValue: "Using %@…", bundle: PersonalChatStrings.bundle), tool.text)
        }
        return String(localized: "personal.working", defaultValue: "Claude is working…", bundle: PersonalChatStrings.bundle)
    }

    func finishReveal(_ id: String) { if revealingMessageIDs.contains(id) { revealingMessageIDs.remove(id) } }

    func restorePendingDraft() {
        guard let pendingSend, pendingSend.state == "uncertain", !busy else { return }
        draft = pendingSend.originalDraft
        attachments = pendingSend.attachments
        messages.removeAll { $0.id == pendingSend.message.id }
        self.pendingSend = nil
        awaitingReply = false
    }

    private func clearConversation() {
        dictation?.cancel(restore: false)
        messages = []
        approvals = []
        approvalError = nil
        nativeApprovalsEnabled = true
        pendingSend = nil
        revealingMessageIDs = []
        remoteMessageIDs = []
        transcriptLoaded = false
        awaitingReply = false
        consoleCommand = nil
        consolePresentationID = nil
    }

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
            archivedSessionIDs = try await repository.loadArchive()
            sessionTitles = try await repository.loadTitles()
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
        sessionListRequestID = nil
        isLoadingSessions = false
        sessionsLoadError = nil
        stopRefresh()
        selectionGeneration = UUID()
        selectedID = nil
        clearConversation()
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
            if error == nil && sessionsLoadError == nil { try await save() }
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
        sessionListRequestID = nil
        isLoadingSessions = false
        sessionsLoadError = nil
        clearConversation()
        draft = ""
        attachments = []
        phase = "offline"
        await reloadSessions()
        do { try await save() } catch { self.error = error.localizedDescription }
    }

    func reloadSessions() async {
        guard connected, let project else { return }
        let requestID = UUID()
        sessionListRequestID = requestID
        isLoadingSessions = true
        sessionsLoadError = nil
        defer {
            if sessionListRequestID == requestID { isLoadingSessions = false }
        }
        do {
            let result = try await service.request(.init(op: "list", project: project.path), connection: connection)
            guard projectID == project.id, sessionListRequestID == requestID else { return }
            sessions = result.sessions ?? []
        } catch {
            guard projectID == project.id, sessionListRequestID == requestID, !Task.isCancelled else { return }
            sessionsLoadError = error.localizedDescription
        }
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
        clearConversation()
        draft = ""
        attachments = []
        phase = "offline"
        startRefresh()
    }

    func startSession(resume: Bool = false) async {
        guard connected, !busy, let project else { return }
        dictation?.cancel(restore: false)
        busy = true
        defer { busy = false }
        let id = resume ? selectedID ?? UUID().uuidString.lowercased() : UUID().uuidString.lowercased()
        do {
            _ = try await service.request(.init(op: "start", id: id, project: project.path, resume: resume), connection: connection)
            stopRefresh()
            selectionGeneration = UUID()
            selectedID = id
            clearConversation()
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
            let result = try await service.request(.init(op: "read", id: id, project: project.path, approvalUI: nativeApprovalsEnabled), connection: connection)
            guard generation == selectionGeneration else { return }
            approvals = (result.approvals ?? []).filter { $0.sessionID == id && $0.project == project.path }
            let received = result.messages ?? []
            let newIDs = Set(received.map(\.id)).subtracting(remoteMessageIDs)
            if transcriptLoaded || awaitingReply {
                revealingMessageIDs.formUnion(received.filter { $0.role == "assistant" && newIDs.contains($0.id) }.map(\.id))
            }
            remoteMessageIDs = Set(received.map(\.id))
            transcriptLoaded = true
            if let pendingSend, received.contains(where: { $0.role == "user" && !pendingSend.previousMessageIDs.contains($0.id) && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == pendingSend.wireText.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                self.pendingSend = nil
            }
            messages = received
            if let pendingSend { messages.append(pendingSend.message) }
            phase = result.phase ?? "offline"
            consoleCommand = result.consoleCommand
            if phase == "console", pendingSend?.state == "sent" {
                messages.removeAll { $0.id == pendingSend?.message.id }
                pendingSend = nil
                awaitingReply = false
            }
            if pendingSend == nil && phase != "busy" { awaitingReply = false }
            if pendingSend?.state == "sent" && phase == "ready" { phase = "busy" }
            if let first = messages.first(where: { $0.role == "user" }), let index = sessions.firstIndex(where: { $0.id == id }) {
                sessions[index].title = String(first.text.prefix(80))
            }
        } catch {
            guard generation == selectionGeneration, !Task.isCancelled else { return }
            connected = false
            approvals = []
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

    @discardableResult
    func decideApproval(_ approval: PersonalChatApproval, decision: String, answers: [String: String]? = nil) async -> Bool {
        guard connected, !busy, ["allow", "deny", "terminal"].contains(decision),
              selectedID == approval.sessionID, project?.path == approval.project,
              approvals.contains(approval) else { return false }
        busy = true
        approvalError = nil
        stopRefresh()
        selectionGeneration = UUID() // Discard reads that predate this decision.
        defer { busy = false; startRefresh() }
        do {
            _ = try await service.request(.init(op: "permission_decide", id: approval.sessionID, project: approval.project, approvalID: approval.id, decision: decision, answers: answers), connection: connection)
            approvals.removeAll { $0.id == approval.id }
            if approvals.isEmpty && decision != "terminal" { phase = "busy" }
            return true
        } catch {
            // A network failure can happen after delivery. Re-read state; never
            // repeat the approval automatically or assume the command ran.
            approvalError = String(localized: "personal.approval.unconfirmed", defaultValue: "Decision unconfirmed. Refreshing the request; nothing will be sent again automatically.", bundle: PersonalChatStrings.bundle)
            await refresh()
            return false
        }
    }

    func resumeNativeApprovals() async {
        nativeApprovalsEnabled = true
        guard connected, !busy, let id = selectedID, let project else { startRefresh(); return }
        let generation = selectionGeneration
        if phase == "console" {
            do {
                _ = try await service.request(.init(op: "console_return", id: id, project: project.path), connection: connection)
            } catch {
                if generation == selectionGeneration { self.error = error.localizedDescription }
            }
        }
        if generation == selectionGeneration { startRefresh() }
    }

    func releaseApprovalsToTerminal() async -> Bool {
        guard connected, !busy, let id = selectedID, let project else { return false }
        busy = true
        stopRefresh()
        selectionGeneration = UUID()
        let generation = selectionGeneration
        let targetConnection = connection
        defer { busy = false; startRefresh() }
        do {
            // Release even requests not seen by the most recent UI snapshot.
            _ = try await service.request(.init(op: "permission_handoff", id: id, project: project.path), connection: connection)
            guard generation == selectionGeneration, selectedID == id, self.project?.id == project.id, connection == targetConnection else { return false }
            nativeApprovalsEnabled = false
            approvals = []
            approvalError = nil
            return true
        } catch {
            if generation == selectionGeneration { self.error = error.localizedDescription }
            return false
        }
    }

    func send() async {
        guard canSend, let id = selectedID else { return }
        busy = true
        nativeApprovalsEnabled = true
        stopRefresh()
        selectionGeneration = UUID() // Discard reads that began before this send.
        let originalDraft = draft
        let originalAttachments = attachments
        let displayText = ([originalDraft] + originalAttachments.map { "📎 " + $0.lastPathComponent }).filter { !$0.isEmpty }.joined(separator: "\n")
        let echo = PersonalChatMessage(id: UUID().uuidString, role: "user", text: displayText)
        pendingSend = PersonalChatPendingSend(message: echo, originalDraft: originalDraft, attachments: originalAttachments, previousMessageIDs: remoteMessageIDs, wireText: originalDraft)
        messages.append(echo)
        draft = ""
        attachments = []
        phase = "busy"
        awaitingReply = true
        var deliveryAttempted = false
        defer { busy = false; startRefresh() }
        do {
            var text = originalDraft
            for url in originalAttachments {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 20 * 1024 * 1024 else { throw PersonalChatError.fileTooLarge }
                let data = try Data(contentsOf: url)
                let result = try await service.request(.init(op: "upload", id: id, name: url.lastPathComponent, data: data.base64EncodedString()), connection: connection)
                if let path = result.path { text += "\n\nAttached file on this server: " + String(reflecting: path) }
            }
            pendingSend?.wireText = text
            deliveryAttempted = true
            let reply = try await service.request(.init(op: "send", id: id, text: text, approvalUI: true), connection: connection)
            if reply.phase == "console" {
                messages.removeAll { $0.id == echo.id }
                pendingSend = nil
                awaitingReply = false
                phase = "console"
                consoleCommand = reply.consoleCommand
                consolePresentationID = UUID()
            } else {
                pendingSend?.state = "sent"
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
            if deliveryAttempted {
                pendingSend?.state = "uncertain"
                phase = "attention"
            } else {
                messages.removeAll { $0.id == echo.id }
                pendingSend = nil
                draft = originalDraft
                attachments = originalAttachments
                awaitingReply = false
                phase = "ready"
            }
        }
    }

    func prepareDeletion(_ target: PersonalChatDeletionTarget) async throws -> PersonalChatReply {
        guard connected, !busy else { throw PersonalChatError.sshFailed }
        busy = true
        defer { busy = false }
        return try await service.request(.init(op: "deletion_prepare", id: target.session?.id, project: target.project.path, mode: target.kind == .chat ? "chat" : "project"), connection: connection)
    }

    func performDeletion(_ target: PersonalChatDeletionTarget, planID: String?, confirmation: String) async throws {
        guard !busy else { throw PersonalChatError.sshFailed }
        busy = true
        defer { busy = false }
        if target.permanent {
            guard connected, let planID, confirmation == "delete" else { throw PersonalChatError.sshFailed }
            let result = try await service.request(.init(op: "deletion_commit", id: planID, confirmation: confirmation), connection: connection)
            guard result.phase == "done" else { throw PersonalChatError.sshFailed }
        }
        if target.kind == .chat, let sessionID = target.session?.id {
            if projectID == target.project.id {
                sessions.removeAll { $0.id == sessionID }
                if selectedID == sessionID {
                    stopRefresh()
                    selectionGeneration = UUID()
                    selectedID = nil
                    clearConversation()
                    draft = ""
                    attachments = []
                    phase = "offline"
                }
            }
            archivedSessionIDs[target.project.id.uuidString]?.remove(sessionID)
            sessionTitles[target.project.id.uuidString]?.removeValue(forKey: sessionID)
            try await save()
        } else {
            let removed = projects.filter { $0.id == target.project.id || (target.permanent && $0.path.hasPrefix(target.project.path + "/")) }
            let remaining = projects.filter { candidate in !removed.contains(where: { $0.id == candidate.id }) }
            let changeSelection = removed.contains { $0.id == projectID }
            let nextProjectID = changeSelection ? remaining.first?.id : projectID
            try await repository.save(.init(connection: connection, projects: remaining, selectedProjectID: nextProjectID, selectedSessionID: changeSelection ? nil : selectedID))
            projects = remaining
            for project in removed {
                archivedSessionIDs.removeValue(forKey: project.id.uuidString)
                sessionTitles.removeValue(forKey: project.id.uuidString)
            }
            if changeSelection {
                stopRefresh()
                selectionGeneration = UUID()
                projectID = nextProjectID
                selectedID = nil
                sessions = []
                sessionListRequestID = nil
                isLoadingSessions = false
                sessionsLoadError = nil
                clearConversation()
                draft = ""
                attachments = []
                phase = "offline"
                await reloadSessions()
            }
        }
        try await repository.saveArchive(archivedSessionIDs)
        try await repository.saveTitles(sessionTitles)
    }

    func interrupt() async {
        guard let id = selectedID else { return }
        do { _ = try await service.request(.init(op: "interrupt", id: id), connection: connection) }
        catch { self.error = error.localizedDescription }
    }
}
