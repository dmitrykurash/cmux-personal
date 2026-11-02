import AppKit
import SwiftUI

// Isolated UI fixture: no SSH, no real projects and no user configuration.
private actor UIService: PersonalChatServing {
    private var gate: CheckedContinuation<Void, Never>?
    private var messages: [PersonalChatMessage] = []
    private var phase = "ready"
    private var approvals: [PersonalChatApproval] = []
    static let sessions = (1...43).map { PersonalChatSession(id: String(format: "00000000-0000-4000-8000-%012d", $0), title: "Fixture chat \($0)", updated: Double(44 - $0)) }
    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        switch request.op {
        case "github_status": return .init(ok: true, githubLogin: .init(phase: "signedOut"))
        case "github_begin": return .init(ok: true, githubLogin: .init(id: request.id, phase: "waiting", deviceCode: "TEST-1234"))
        case "github_wait":
            try await Task.sleep(for: .seconds(30))
            return .init(ok: true, githubLogin: .init(phase: "connected"))
        case "github_cancel": return .init(ok: true, githubLogin: .init(phase: "cancelled"))
        case "health": return PersonalChatReply(ok: true, user: "developer", claude: true, tmux: true)
        case "list": return PersonalChatReply(ok: true, sessions: Self.sessions)
        case "send":
            messages = [.init(id: "user", role: "user", text: request.text ?? "")]
            phase = "busy"
            await withCheckedContinuation { gate = $0 }
        case "permission_handoff": approvals = []; phase = "permission"
        case "permission_decide":
            approvals.removeAll { $0.id == request.approvalID }
            messages.append(.init(id: UUID().uuidString, role: "assistant", text: request.answers.map { "Submitted: " + $0.keys.sorted().map { $0 + " = " + request.answers![$0]! }.joined(separator: "; ") } ?? (request.decision == "allow" ? "The command was approved once." : "The command was declined.")))
            phase = "ready"
        case "deletion_prepare": return PersonalChatReply(ok: true, id: UUID().uuidString, path: request.project, count: 43)
        case "deletion_commit": return PersonalChatReply(ok: true, phase: "done")
        default: break
        }
        return PersonalChatReply(ok: true, messages: messages, phase: phase, approvals: approvals)
    }
    func showApproval() {
        messages = [.init(id: "permission-user", role: "user", text: "Check the installed GitHub CLI version.")]
        approvals = [.init(id: UUID().uuidString, sessionID: Self.sessions[0].id, project: "/home/developer/projects/ui-fixture", tool: "Bash", detail: "{\n  \"command\": \"gh --version\",\n  \"description\": \"Check the installed GitHub CLI version\"\n}", expires: Date().timeIntervalSince1970 + 540)]
        phase = "permission"
    }
    func showQuestions() {
        approvals = [.init(id: UUID().uuidString, sessionID: Self.sessions[0].id, project: "/home/developer/projects/ui-fixture", tool: "AskUserQuestion", detail: "{}", expires: Date().timeIntervalSince1970 + 540,
                           questions: [.init(question: "Choose a style", options: [.init(label: "Minimal", description: "A clean starting point"), .init(label: "Detailed", description: "More information on screen")], multiSelect: false),
                                       .init(question: "Choose features", options: [.init(label: "Search"), .init(label: "History")], multiSelect: true)])]
        phase = "permission"
    }
    func showPlan() {
        approvals = [.init(id: UUID().uuidString, sessionID: Self.sessions[0].id, project: "/home/developer/projects/ui-fixture", tool: "ExitPlanMode", detail: "{}", expires: Date().timeIntervalSince1970 + 540, plan: "# A clear plan\n\n1. Inspect the current repository.\n2. Make the requested changes.\n3. Run the relevant checks.\n\nNo deployment is included.")]
        phase = "permission"
    }
    func release() {
        messages.append(.init(id: "assistant", role: "assistant", text: "Your message appeared immediately. This response is revealed smoothly after the server reply arrives, using the real chat view and the same message reconciliation code."))
        phase = "ready"
        gate?.resume(); gate = nil
    }
}

@main
struct UIHarness: App {
    private let service = UIService()
    @State private var model: PersonalChatModel
    @State private var console = false
    init() {
        PersonalChatTypography.register()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cheatcode-ui-fixture-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let project = PersonalChatProject(name: "UI fixture", path: "/home/developer/projects/ui-fixture")
        let config = PersonalChatRepository.Configuration(connection: .init(host: "example.invalid"), projects: [project], selectedProjectID: project.id, selectedSessionID: UIService.sessions[0].id)
        let file = folder.appendingPathComponent("config.json")
        try! JSONEncoder().encode(config).write(to: file)
        try! JSONEncoder().encode([project.id.uuidString: Set(UIService.sessions.dropFirst(2).map(\.id))]).write(to: folder.appendingPathComponent("config.archive.json"))
        _model = State(initialValue: PersonalChatModel(service: service, repository: PersonalChatRepository(file: file)))
    }
    var body: some Scene {
        WindowGroup("CheatCode UI Check") {
            VStack(spacing: 0) {
                HStack {
                    Button("Release fixture reply") { Task { await service.release() } }
                    Button("Show permission request") { Task { await service.showApproval(); await model.refresh() } }
                    Button("Show questions") { Task { await service.showQuestions(); await model.refresh() } }
                    Button("Show plan") { Task { await service.showPlan(); await model.refresh() } }
                    Button("Test console") { console = true }
                }.padding(12)
                PersonalChatView(model: model, openTerminal: { _ in })
            }
                    .sheet(isPresented: $console) { PersonalChatConsoleSheet(request: .init(command: "/bin/cat")) }
        }.defaultSize(width: 1200, height: 850)
    }
}
