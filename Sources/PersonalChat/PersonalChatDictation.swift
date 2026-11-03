import Foundation
import Observation

/// Owns one draft insertion; late speech events never cross chat boundaries.
@MainActor @Observable
final class PersonalChatDictation {
    enum Phase { case idle, preparing, recording, finishing }
    private(set) var phase = Phase.idle
    private(set) var level: Float = 0
    private(set) var issue: String?
    var locale = "en-US"
    var active: Bool { phase != .idle }
    private let service: any PersonalChatSpeechServing
    private var task: Task<Void, Never>?
    private var id: UUID?
    private var original = ""
    private var lastDraft = ""
    private var update: ((String) -> Void)?
    init(service: any PersonalChatSpeechServing) { self.service = service }

    func start(draft: String, update: @escaping (String) -> Void) {
        guard !active else { return }
        let token = UUID(); id = token
        original = draft; lastDraft = draft; self.update = update
        phase = .preparing; issue = nil; level = 0
        let locale = self.locale
        task = Task { [weak self, service] in
            do {
                let events = try await service.start(id: token, locale: locale)
                for try await event in events {
                    guard !Task.isCancelled, let self, self.id == token else { break }
                    switch event {
                    case .preparing: if self.phase != .finishing { self.phase = .preparing }
                    case .recording: if self.phase != .finishing { self.phase = .recording }
                    case .level(let value): self.level = value
                    case .failed(let error): throw error
                    case .transcript(let text):
                        let separator = self.original.isEmpty || self.original.last?.isWhitespace == true || text.isEmpty ? "" : " "
                        self.lastDraft = self.original + separator + text
                        self.update?(self.lastDraft)
                    }
                }
            } catch {
                if !Task.isCancelled, let self, self.id == token {
                    self.issue = (error as? PersonalChatSpeechError ?? .recognition).localizedDescription
                }
            }
            await service.cancel(id: token)
            guard let self, self.id == token else { return }
            self.phase = .idle; self.level = 0; self.id = nil; self.update = nil; self.task = nil
        }
    }

    func stop() {
        guard phase == .recording, let id else { return }
        phase = .finishing; level = 0
        Task { await service.stop(id: id) }
    }

    func cancel(restore: Bool = true) {
        guard let token = id else { return }
        id = nil; task?.cancel(); task = nil
        if restore { update?(original) }
        update = nil; phase = .idle; level = 0; issue = nil
        Task { await service.cancel(id: token) }
    }

    func dismissIssue() { issue = nil }
}
