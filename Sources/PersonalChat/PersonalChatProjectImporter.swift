import Foundation
import Observation

@MainActor @Observable
final class PersonalChatProjectImporter {
    var mode = PersonalChatProjectSource.clone
    var repository = ""
    var name = ""
    var path = ""
    var basePath: String
    var busy = false
    var cancelling = false
    var issue: String?
    var jobID: String?
    var preparedPath: String?
    var nameEdited = false
    var pathEdited = false
    let hasGitHubCLI: Bool
    let connection: PersonalChatConnection
    private let service: any PersonalChatServing

    func makeGitHub() -> PersonalChatGitHub { PersonalChatGitHub(service: service, connection: connection) }

    init(service: any PersonalChatServing, connection: PersonalChatConnection, basePath: String, hasGitHubCLI: Bool) {
        self.service = service
        self.connection = connection
        self.basePath = basePath
        self.hasGitHubCLI = hasGitHubCLI
        self.path = basePath + "/"
    }

    var locked: Bool { busy || jobID != nil || preparedPath != nil }
    var canSubmit: Bool {
        !busy && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && path.hasPrefix("/") &&
        (mode != .clone || !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func suggestName() {
        if !nameEdited {
            let component = repository.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").last.map(String.init) ?? ""
            name = component.hasSuffix(".git") ? String(component.dropLast(4)) : component
        }
        suggestPath()
    }

    func suggestPath() {
        guard !pathEdited, mode != .existing else { return }
        let component = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        path = basePath + "/" + component
    }

    func listFolders(_ path: String) async throws -> PersonalChatReply {
        try await service.request(.init(op: "folders", project: path), connection: connection)
    }

    func submit(onReady: @MainActor (String, String) async throws -> Void) async -> Bool {
        guard canSubmit else { return false }
        busy = true
        issue = nil
        cancelling = false
        defer { busy = false; cancelling = false }
        do {
            if preparedPath == nil {
                if mode == .clone && jobID == nil { jobID = UUID().uuidString.lowercased() }
                var reply = try await service.request(.init(op: "project_prepare", id: jobID, project: path,
                    mode: mode.rawValue, repository: repository.trimmingCharacters(in: .whitespacesAndNewlines)), connection: connection)
                while reply.phase == "cloning", let jobID {
                    // The remote worker wakes this long-poll on completion. No local delay/poll timer.
                    reply = try await service.request(.init(op: "project_wait", id: jobID), connection: connection)
                }
                if reply.phase == "cancelled" {
                    jobID = nil
                    issue = String(localized: "personal.import.cancelled", defaultValue: "Import cancelled. Any partial files remain in the selected folder.", bundle: PersonalChatStrings.bundle)
                    return false
                }
                guard reply.phase == "done", let actualPath = reply.path else {
                    jobID = nil
                    throw PersonalChatProjectError(code: reply.code ?? "import_failed")
                }
                preparedPath = actualPath
            }
            guard let preparedPath else { return false }
            try await onReady(name.trimmingCharacters(in: .whitespacesAndNewlines), preparedPath)
            return true
        } catch {
            if error is PersonalChatProjectError { jobID = nil }
            // Keep the job ID on uncertain SSH delivery. Retry uses the same job,
            // and an already-cloned folder is reused if only local saving failed.
            issue = error.localizedDescription
            return false
        }
    }

    func cancel() async {
        guard let jobID, !cancelling else { return }
        let recovering = !busy
        if recovering { busy = true }
        cancelling = true
        defer { if recovering { busy = false; cancelling = false } }
        do {
            var reply = try await service.request(.init(op: "project_cancel", id: jobID), connection: connection)
            // A lost SSH reply may leave no active submit waiting for the worker.
            // Finish cancellation here in that case, so the sheet stays usable.
            if recovering {
                while reply.phase == "cloning" || reply.phase == "cancelling" {
                    reply = try await service.request(.init(op: "project_wait", id: jobID), connection: connection)
                }
                self.jobID = nil
                if reply.phase == "done" { preparedPath = reply.path; issue = nil }
                else if reply.phase == "cancelled" {
                    issue = String(localized: "personal.import.cancelled", defaultValue: "Import cancelled. Any partial files remain in the selected folder.", bundle: PersonalChatStrings.bundle)
                } else { throw PersonalChatProjectError(code: reply.code ?? "import_failed") }
            }
        } catch { issue = error.localizedDescription; cancelling = false }
    }
}
