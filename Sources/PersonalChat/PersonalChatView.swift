import AppKit
import SwiftUI

struct PersonalChatView: View {
    @Bindable var model: PersonalChatModel
    let openTerminal: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sidebarVisible = true
    @State private var search = ""
    @State private var addingProject = false
    @State private var projectName = ""
    @State private var projectPath = "/home/developer/projects"
    private var palette: PersonalChatPalette { PersonalChatPalette(scheme: scheme) }
    private var newChatLabel: String { String(localized: "personal.new", defaultValue: "New chat") }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar.frame(width: 236)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                palette.divider.frame(width: 1)
            }
            conversation.frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 740, minHeight: 560)
        .background(palette.canvas).foregroundStyle(palette.text).tint(palette.accent)
        .task { await model.load() }
        .onDisappear { model.stopRefresh() }
        .sheet(isPresented: $model.showingSettings) {
            PersonalChatSettingsView(connection: model.connection, busy: model.busy) { connection in
                model.connection = connection
                Task { await model.connect() }
            }
        }
        .sheet(isPresented: $addingProject) { projectSheet }
        .alert(String(localized: "personal.attention", defaultValue: "Needs attention"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(String(localized: "personal.ok", defaultValue: "OK")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(verbatim: "cmux").font(.system(size: 24, weight: .semibold, design: .serif))
                Text(verbatim: "PERSONAL").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(palette.muted)
                Spacer()
            }.padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 24)
            Button { Task { await model.startSession() } } label: {
                Label(newChatLabel, systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 11)
            }.buttonStyle(PersonalChatHoverStyle()).disabled(!model.connected || model.project == nil || model.busy)
                .foregroundStyle(palette.accent)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(palette.muted)
                TextField(String(localized: "personal.search", defaultValue: "Search chats"), text: $search)
                    .textFieldStyle(.plain).font(.system(size: 12))
            }.padding(.horizontal, 12).padding(.vertical, 10).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        sectionLabel(String(localized: "personal.projects", defaultValue: "Projects"))
                        Spacer()
                        Button { addingProject = true } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                            .buttonStyle(PersonalChatHoverStyle()).foregroundStyle(palette.secondary)
                            .help(String(localized: "personal.project.add", defaultValue: "Add project"))
                            .accessibilityLabel(String(localized: "personal.project.add", defaultValue: "Add project"))
                    }.padding(.trailing, 6).padding(.bottom, 4)
                    ForEach(model.projects) { project in
                        Button { Task { await model.selectProject(project.id) } } label: {
                            Label(project.name, systemImage: "folder")
                                .font(.system(size: 13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }.buttonStyle(PersonalChatHoverStyle(selected: model.projectID == project.id)).disabled(model.busy)
                    }
                    sectionLabel(String(localized: "personal.recents", defaultValue: "Recent chats"))
                        .padding(.top, 24).padding(.bottom, 7)
                    ForEach(model.sessions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { session in
                        Button { model.selectSession(session.id) } label: {
                            Text(session.title == "New chat" ? newChatLabel : session.title)
                                .font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                        }.buttonStyle(PersonalChatHoverStyle(selected: model.selectedID == session.id))
                            .disabled(model.busy).help(session.title)
                    }
                }
            }.scrollIndicators(.hidden)
            connectionFooter
        }.padding(.horizontal, 12).background(palette.sidebar)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted).padding(.leading, 12)
    }

    private var connectionFooter: some View {
        HStack(spacing: 8) {
            Circle().fill(model.connected ? Color(red: 0.48, green: 0.66, blue: 0.51) : palette.muted).frame(width: 6, height: 6)
            if model.connected {
                Text(String(localized: "personal.connected", defaultValue: "Connected"))
            } else {
                Button(String(localized: "personal.connect", defaultValue: "Connect")) { Task { await model.connect() } }
                    .buttonStyle(.plain).disabled(model.busy || model.connection.host.isEmpty)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.mini) }
            Button { model.showingSettings = true } label: { Image(systemName: "gearshape").frame(width: 28, height: 28) }
                .buttonStyle(PersonalChatHoverStyle())
                .help(String(localized: "personal.connection", defaultValue: "Connection"))
                .accessibilityLabel(String(localized: "personal.connection", defaultValue: "Connection"))
        }.font(.system(size: 11)).foregroundStyle(palette.secondary)
            .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 14)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            header
            if model.messages.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 30) {
                            HStack(spacing: 13) {
                                Image(systemName: "asterisk").font(.system(size: 34, weight: .light)).foregroundStyle(palette.accent)
                                Text(String(localized: "personal.welcome.short", defaultValue: "What can we work on?"))
                                    .font(.system(size: 32, weight: .regular, design: .serif)).tracking(-0.7)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.padding(.horizontal, 4)
                            composer
                        }.frame(maxWidth: 680).padding(.horizontal, 36)
                            .padding(.top, max(38, geometry.size.height * 0.23)).padding(.bottom, 30)
                            .frame(maxWidth: .infinity)
                    }.scrollIndicators(.hidden)
                }
            } else {
                messageList
                composer.frame(maxWidth: 720).padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 18)
                    .frame(maxWidth: .infinity)
            }
        }.background(palette.canvas)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { sidebarVisible.toggle() }
            } label: { Image(systemName: "sidebar.left").frame(width: 28, height: 28) }
                .buttonStyle(PersonalChatHoverStyle()).foregroundStyle(palette.secondary)
                .help(String(localized: "personal.sidebar", defaultValue: "Toggle sidebar"))
                .accessibilityLabel(String(localized: "personal.sidebar", defaultValue: "Toggle sidebar"))
            Text(model.project?.name ?? "cmux Personal").font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer()
            if model.selectedID != nil {
                Button(action: showTerminal) {
                    Label(String(localized: "personal.terminal", defaultValue: "Open terminal"), systemImage: "terminal")
                        .font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 7)
                }.buttonStyle(PersonalChatHoverStyle()).foregroundStyle(palette.secondary)
                    .disabled(model.phase == "offline" || !model.connected)
            }
        }.padding(.horizontal, 20).frame(height: 58)
    }

    private var composer: some View {
        PersonalChatComposer(model: model, openTerminal: showTerminal)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(model.messages) { message in PersonalChatMessageView(message: message) }
                    Color.clear.frame(height: 1).id("end")
                }.frame(maxWidth: 720).padding(.horizontal, 36).padding(.top, 24).padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.messages.last?.id) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    private var projectSheet: some View {
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

    private func showTerminal() {
        guard let id = model.selectedID else { return }
        do { openTerminal(try model.connection.terminalCommand(sessionID: id)) }
        catch { model.error = error.localizedDescription }
    }
}
