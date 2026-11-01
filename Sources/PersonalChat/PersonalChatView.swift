import AppKit
import SwiftUI

struct PersonalChatView: View {
    @Bindable var model: PersonalChatModel
    let openTerminal: (String) -> Void
    @State private var addingProject = false
    @State private var projectName = ""
    @State private var projectPath = "/home/developer/projects"

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 220, idealWidth: 250, maxWidth: 310)
            conversation.frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 600)
        .tint(Color(red: 0.73, green: 0.38, blue: 0.25))
        .task { await model.load() }
        .onDisappear { model.stopRefresh() }
        .sheet(isPresented: $model.showingSettings) {
            PersonalChatSettingsView(connection: model.connection, busy: model.busy) { connection in
                model.connection = connection
                Task { await model.connect() }
            }
        }
        .sheet(isPresented: $addingProject) {
            VStack(alignment: .leading, spacing: 18) {
                Text(String(localized: "personal.project.add", defaultValue: "Add project")).font(.title2)
                TextField(String(localized: "personal.project.name", defaultValue: "Name"), text: $projectName)
                TextField(String(localized: "personal.project.path", defaultValue: "Folder on the VPS"), text: $projectPath)
                HStack {
                    Button(String(localized: "personal.cancel", defaultValue: "Cancel")) { addingProject = false }
                    Spacer()
                    Button(String(localized: "personal.project.add", defaultValue: "Add project")) {
                        addingProject = false
                        Task { await model.addProject(name: projectName, path: projectPath) }
                    }.disabled(projectName.isEmpty || !projectPath.hasPrefix("/"))
                }
            }.padding(28).frame(width: 440)
        }
        .alert(String(localized: "personal.attention", defaultValue: "Needs attention"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(String(localized: "personal.ok", defaultValue: "OK")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkle").foregroundStyle(.tint)
                Text(verbatim: "cmux Personal").font(.headline)
            }.padding(.top, 10)
            Button { Task { await model.startSession() } } label: {
                Label(String(localized: "personal.new", defaultValue: "New chat"), systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered).disabled(!model.connected || model.project == nil || model.busy)
            HStack {
                Text(String(localized: "personal.projects", defaultValue: "Projects")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { addingProject = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help(String(localized: "personal.project.add", defaultValue: "Add project"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.projects) { project in
                        Button { Task { await model.selectProject(project.id) } } label: {
                            Label(project.name, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(model.projectID == project.id ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                    Divider().padding(.vertical, 8)
                    ForEach(model.sessions) { session in
                        Button { model.selectSession(session.id) } label: {
                            Text(session.title).font(.callout).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                .background(model.selectedID == session.id ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                }
            }
            Spacer(minLength: 0)
            Divider()
            HStack {
                Circle().fill(model.connected ? .green : .secondary).frame(width: 7, height: 7)
                Text(model.connected ? String(localized: "personal.connected", defaultValue: "Connected") : String(localized: "personal.disconnected", defaultValue: "Disconnected")).font(.caption)
                Spacer()
                Button { model.showingSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help(String(localized: "personal.connection", defaultValue: "Connection"))
            }
            if !model.connected {
                Button(String(localized: "personal.connect", defaultValue: "Connect")) { Task { await model.connect() } }.disabled(model.busy || model.connection.host.isEmpty)
            }
        }.padding(18).background(Color(nsColor: .controlBackgroundColor))
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.project?.name ?? "cmux Personal").font(.headline)
                    Text(String(localized: "personal.engine", defaultValue: "Claude Code · remote session")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.selectedID != nil {
                    Button(String(localized: "personal.terminal", defaultValue: "Open terminal"), systemImage: "terminal") { showTerminal() }
                        .disabled(model.phase == "offline" || !model.connected)
                }
            }.padding(20)
            Divider()
            if model.messages.isEmpty {
                VStack(spacing: 18) {
                    Spacer()
                    Image(systemName: "sparkle").font(.system(size: 40, weight: .light)).foregroundStyle(.tint)
                    Text(String(localized: "personal.welcome", defaultValue: "A quiet place to work with Claude")).font(.system(size: 25, weight: .medium, design: .serif))
                    Text(String(localized: "personal.welcome.detail", defaultValue: "Choose a project, then start or resume a conversation.")).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(model.messages) { message in PersonalChatMessageView(message: message) }
                            Color.clear.frame(height: 1).id("end")
                        }.padding(28).frame(maxWidth: 820).frame(maxWidth: .infinity)
                    }.onChange(of: model.messages.last?.id) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            if model.selectedID != nil {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(statusLabel).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if model.phase == "offline" {
                            Button(String(localized: "personal.resume", defaultValue: "Resume session")) { Task { await model.startSession(resume: true) } }.disabled(!model.connected || model.busy)
                        } else if model.phase != "ready" {
                            Button(String(localized: "personal.terminal", defaultValue: "Open terminal")) { showTerminal() }
                        }
                    }
                    if !model.attachments.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(model.attachments, id: \.self) { url in
                                    Button { model.attachments.removeAll { $0 == url } } label: {
                                        Label(url.lastPathComponent, systemImage: "xmark.circle")
                                    }.disabled(model.busy)
                                }
                            }
                        }
                    }
                    TextEditor(text: $model.draft).font(.body).scrollContentBackground(.hidden).frame(minHeight: 70, maxHeight: 140).disabled(model.busy)
                    HStack {
                        Button { chooseFiles() } label: { Image(systemName: "paperclip") }
                            .help(String(localized: "personal.attach", defaultValue: "Attach files")).disabled(model.busy)
                        Text(String(localized: "personal.files.note", defaultValue: "Files are uploaded to your VPS when you send.")).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        if model.phase == "busy" {
                            Button(String(localized: "personal.stop", defaultValue: "Stop")) { Task { await model.interrupt() } }
                        }
                        Button(String(localized: "personal.send", defaultValue: "Send"), systemImage: "arrow.up") { Task { await model.send() } }
                            .buttonStyle(.borderedProminent).disabled(!model.canSend)
                    }
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18)).padding(20)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusLabel: String {
        switch model.phase {
        case "ready": return String(localized: "personal.ready", defaultValue: "Ready")
        case "busy": return String(localized: "personal.working", defaultValue: "Claude is working…")
        case "offline": return String(localized: "personal.saved", defaultValue: "Saved conversation")
        default: return String(localized: "personal.permission", defaultValue: "Continue in the terminal to review permissions or questions.")
        }
    }

    private func showTerminal() {
        guard let id = model.selectedID else { return }
        do { openTerminal(try model.connection.terminalCommand(sessionID: id)) }
        catch { model.error = error.localizedDescription }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { model.attachments.append(contentsOf: panel.urls) }
    }
}
