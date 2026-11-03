import Foundation
import Observation

/// Owns one attachment to the selected chat, independent of the pane's size.
@MainActor @Observable
final class PersonalChatConsoleState {
    struct Scope: Equatable {
        let session: String
        let project: UUID
        let connection: PersonalChatConnection
    }
    private(set) var presented = false
    private(set) var request: PersonalChatConsoleRequest?
    private(set) var opening = false
    private(set) var failed = false
    private(set) var focusID: UUID?
    private var attached: Scope?
    private var observedScope: Scope?
    private var handoffRequested = false
    private let model: PersonalChatModel
    private let opensForChats: Bool
    private let now: () -> Date
    private var endedRequestID: UUID?
    private var retryAfter = Date.distantPast
    private var retryFailures = 0

    init(model: PersonalChatModel, opensForChats: Bool = true, now: @escaping () -> Date = { Date() }) {
        self.model = model
        self.opensForChats = opensForChats
        self.now = now
    }

    var scope: Scope? {
        guard let session = model.selectedID, let project = model.projectID else { return nil }
        return Scope(session: session, project: project, connection: model.connection)
    }

    func open() {
        presented = true
        failed = false
        focusID = UUID()
        handoffRequested = true
        // A repeated explicit click releases any new native approval, but keeps
        // the same PTY. Ordinary refreshes must not repeatedly release approvals.
        attach()
    }

    func reconcile() {
        if observedScope != scope {
            endedRequestID = nil
            retryFailures = 0
            observedScope = scope
            presented = scope != nil && (opensForChats || presented)
            handoffRequested = false
            focusID = nil
            request = nil
            attached = nil
            failed = false
        }
        if !model.connected || model.phase == "offline" {
            request = nil
            attached = nil
            failed = false
        }
        attach()
    }

    func close() {
        endedRequestID = nil
        retryFailures = 0
        presented = false
        request = nil
        attached = nil
        failed = false
        // If handoff is in flight, its completion restores native routing.
        if !opening { Task { await model.resumeNativeApprovals() } }
    }

    func reconnect() {
        endedRequestID = nil
        retryFailures = 0
        request = nil
        attached = nil
        open()
    }

    func terminalDidEnd(requestID: UUID) {
        guard presented, request?.id == requestID else { return }
        endedRequestID = requestID
        retryFailures = min(retryFailures + 1, 5)
        retryAfter = now().addingTimeInterval(Double(min(30, 2 << (retryFailures - 1))))
    }

    func recoverAfterRead() {
        // A fresh read must confirm the selected remote session is still alive.
        // Passive reattachment never starts Claude, sends input or hands off approval.
        guard presented, !opening, !model.busy, model.connected, !model.isReconnecting,
              model.phase != "offline", attached == scope,
              let endedRequestID, request?.id == endedRequestID, now() >= retryAfter else { return }
        self.endedRequestID = nil
        request = nil
        attached = nil
        handoffRequested = false
        focusID = nil
        failed = false
        attach()
    }

    private func installRequest(for target: Scope) throws {
        if attached != target || request == nil {
            request = .init(command: try target.connection.terminalCommand(sessionID: target.session), cliCommand: model.consoleCommand)
            attached = target
        }
    }

    private func attach() {
        guard presented, !opening, !failed, model.connected, !model.isReconnecting, !model.busy,
              model.phase != "offline", let target = scope else { return }
        guard handoffRequested || request == nil else { return }
        observedScope = scope
        // Default visibility is passive: it must neither steal typing focus nor
        // release a native permission card. Only an explicit handoff does that.
        guard handoffRequested else {
            do { try installRequest(for: target) }
            catch { failed = true; model.error = error.localizedDescription }
            return
        }
        handoffRequested = false
        opening = true
        Task {
            let released = await model.releaseApprovalsToTerminal()
            // Closing or changing chat while SSH is pending cannot reopen the
            // pane or attach the previous chat under the new chat's heading.
            guard presented, target == scope else {
                opening = false
                if !presented { await model.resumeNativeApprovals() }
                reconcile()
                return
            }
            if released {
                do {
                    try installRequest(for: target)
                    focusID = UUID()
                } catch {
                    failed = true
                    model.error = error.localizedDescription
                    await model.resumeNativeApprovals()
                }
            } else { failed = true }
            opening = false
        }
    }
}
