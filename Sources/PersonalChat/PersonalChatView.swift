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
    @State private var sidebarState = PersonalChatSidebarState()
    @State private var showingGitHub = false
    @State private var console: PersonalChatConsoleState
    @State private var contentWidth: CGFloat = 1320
    @State private var sidebarHiddenForConsole = false
    @State private var renameTarget: PersonalChatRenameTarget?
    @State private var deletionTarget: PersonalChatDeletionTarget?
    private var palette: PersonalChatPalette { PersonalChatPalette(scheme: scheme) }
    private var isConversationEmpty: Bool { model.messages.isEmpty && model.approvals.isEmpty }
    private var modalPresented: Bool { model.showingSettings || addingProject || showingGitHub || deletionTarget != nil || renameTarget != nil }
    private var newChatLabel: String { String(localized: "personal.new", defaultValue: "New chat", bundle: PersonalChatStrings.bundle) }
    private var motion: Animation? { reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.3) }

    init(model: PersonalChatModel, openTerminal: @escaping (String) -> Void) {
        self.model = model
        self.openTerminal = openTerminal
        _console = State(initialValue: PersonalChatConsoleState(model: model, opensForChats: PersonalChatConsolePane.supported))
    }

    private var mainLayout: some View {
        HStack(spacing: sidebarVisible ? 10 : 0) {
            sidebar.frame(width: 250).frame(width: sidebarVisible ? 250 : 0, alignment: .leading)
                .opacity(sidebarVisible ? 1 : 0).clipped().accessibilityHidden(!sidebarVisible)
                .padding(.leading, 10).padding(.vertical, 10)
            HSplitView {
                conversation.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, sidebarVisible ? 10 : 38).padding(.bottom, 10)
                    // The native divider supplies the final point of the gutter.
                    .padding(.trailing, console.presented ? 7 : 10)
                if console.presented {
                    PersonalChatConsolePane(state: console, model: model)
                        .frame(minWidth: 320, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: console.presented && sidebarVisible ? 1010 : 750, minHeight: 560)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .background {
            ZStack {
                LinearGradient(colors: [palette.canvasTop, palette.canvasBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.07 : 0.7), .clear], center: UnitPoint(x: 0.12, y: -0.08), startRadius: 0, endRadius: 650)
                RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.035 : 0.35), .clear], center: UnitPoint(x: 0.88, y: 0.04), startRadius: 0, endRadius: 500)
            }
        }
        .foregroundStyle(palette.text).tint(palette.accent).font(PersonalChatTypography.body(13))
        .ignoresSafeArea()
    }

    var body: some View {
        mainLayout
        .task { await model.load(); console.reconcile() }
        .onDisappear { model.stopRefresh(); model.dictation?.cancel(restore: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if model.dictation?.phase == .recording { model.dictation?.stop() }
        }
        .onChange(of: modalPresented) {
            if modalPresented { model.dictation?.cancel(restore: false) }
        }
        .sheet(isPresented: $model.showingSettings) {
            PersonalChatSettingsView(connection: model.connection, busy: model.busy) { connection in
                model.connection = connection
                Task { await model.connect() }
            }
        }
        .sheet(isPresented: $addingProject) {
            PersonalChatProjectSetupView(importer: model.makeProjectImporter(), addProject: model.addProject)
        }
        .sheet(item: $renameTarget) { target in
            PersonalChatRenameView(target: target) { name in
                try await model.renameSession(target.session.id, to: name, inProject: target.projectID)
            }
        }
        .sheet(item: $deletionTarget) { target in
            PersonalChatDeletionView(target: target, prepare: { try await model.prepareDeletion(target) }, commit: { planID, confirmation in
                try await model.performDeletion(target, planID: planID, confirmation: confirmation)
            })
        }
        .sheet(isPresented: $showingGitHub) { PersonalChatGitHubView(model: model.makeGitHub()) }
        .onChange(of: console.scope) { console.reconcile() }
        .onChange(of: model.connected) { console.reconcile() }
        .onChange(of: model.busy) { if !model.busy { console.reconcile() } }
        .onChange(of: model.phase) { console.reconcile() }
        .onChange(of: model.successfulReadRevision) { console.recoverAfterRead() }
        .onChange(of: console.presented) {
            if console.presented && sidebarVisible && contentWidth < 1100 {
                sidebarHiddenForConsole = true
                sidebarVisible = false
            } else if !console.presented && sidebarHiddenForConsole {
                sidebarVisible = true
                sidebarHiddenForConsole = false
            }
        }
        .onChange(of: model.consolePresentationID) {
            if model.consolePresentationID != nil {
                model.consolePresentationID = nil
                showTerminal()
            }
        }
        .onChange(of: search) { sidebarState.resetPages() }
        .alert(String(localized: "personal.attention", defaultValue: "Needs attention", bundle: PersonalChatStrings.bundle), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(String(localized: "personal.ok", defaultValue: "OK", bundle: PersonalChatStrings.bundle)) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); sidebarToggle }.frame(height: 30).padding(.bottom, 12)
            Button { Task { await model.startSession() } } label: {
                Label(newChatLabel, systemImage: "plus.circle")
                    .font(PersonalChatTypography.body(13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 34)
            }.buttonStyle(PersonalChatHoverStyle(radius: 9))
                .disabled(!model.connected || model.project == nil || model.busy)
            HStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(palette.muted)
                    TextField(String(localized: "personal.search", defaultValue: "Search chats", bundle: PersonalChatStrings.bundle), text: $search)
                        .textFieldStyle(.plain).font(PersonalChatTypography.body(12))
                }.padding(.horizontal, 10).frame(height: 30)
                    .background(palette.hover, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border))
                Button { addingProject = true } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 14)).frame(width: 30, height: 30)
                }.buttonStyle(PersonalChatHoverStyle()).foregroundStyle(palette.secondary)
                    .help(String(localized: "personal.project.add", defaultValue: "Add project", bundle: PersonalChatStrings.bundle))
                    .accessibilityLabel(String(localized: "personal.project.add", defaultValue: "Add project", bundle: PersonalChatStrings.bundle))
                    .disabled(!model.connected || model.busy)
            }.padding(.top, 12).padding(.bottom, 22)
            sectionLabel(String(localized: "personal.projects", defaultValue: "Projects", bundle: PersonalChatStrings.bundle)).padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(model.projects) { project in
                        projectRow(project)
                        if model.projectID == project.id && sidebarState.projectIsExpanded(project.id) {
                            projectChats(project)
                        }
                    }
                }
            }.scrollIndicators(.hidden)
            connectionFooter
        }.padding(.horizontal, 4)
    }

    private var loadingChats: Bool { model.isLoadingSessions || (model.busy && !model.connected) }

    private func projectChats(_ project: PersonalChatProject) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if loadingChats {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(String(localized: "personal.sessions.loading", defaultValue: "Loading chats…", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(11.5)).foregroundStyle(palette.muted)
                }.frame(height: 30).padding(.leading, 32)
                    .accessibilityElement(children: .combine).transition(.opacity)
            }
            ForEach(matching(model.activeSessions)) { session in
                sessionRow(session, projectID: project.id, archived: false).padding(.leading, 20).transition(.opacity)
            }
            if let error = model.sessionsLoadError {
                HStack(spacing: 8) {
                    Text(String(localized: "personal.sessions.failed", defaultValue: "Couldn’t load chats", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(11.5)).foregroundStyle(palette.muted)
                    Button(String(localized: "personal.sessions.retry", defaultValue: "Retry", bundle: PersonalChatStrings.bundle)) { Task { await model.reloadSessions() } }
                        .buttonStyle(PersonalChatHoverStyle(radius: 6)).font(PersonalChatTypography.body(11.5))
                        .disabled(model.busy || loadingChats || !model.connected)
                }.padding(.leading, 32).padding(.vertical, 6).help(error)
            } else if model.connected && !loadingChats && model.sessions.isEmpty {
                Text(String(localized: "personal.sessions.empty", defaultValue: "No chats yet", bundle: PersonalChatStrings.bundle))
                    .font(PersonalChatTypography.body(11.5)).foregroundStyle(palette.muted)
                    .padding(.leading, 32).padding(.vertical, 6).transition(.opacity)
            }
            archiveSection(projectID: project.id)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.isLoadingSessions)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.sessions.map(\.id))
    }

    private func matching(_ sessions: [PersonalChatSession]) -> [PersonalChatSession] {
        sessions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func sessionRow(_ session: PersonalChatSession, projectID: UUID, archived: Bool) -> some View {
        PersonalChatSessionRow(session: session, selected: model.selectedID == session.id, archived: archived) {
            model.selectSession(session.id)
        } rename: {
            renameTarget = .init(projectID: projectID, session: session)
        } toggleArchive: {
            Task {
                await model.setArchived(session.id, archived: !archived, inProject: projectID)
            }
        } delete: {
            if let project = model.projects.first(where: { $0.id == projectID }) {
                deletionTarget = .init(kind: .chat, project: project, session: session)
            }
        }.disabled(model.busy)
    }

    private func archiveSection(projectID: UUID) -> some View {
        let expanded = sidebarState.archiveIsExpanded(projectID)
        let sessions = matching(model.archivedSessions)
        let limit = sidebarState.archiveLimit(projectID)
        return VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(motion) {
                    sidebarState.toggleArchive(projectID)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold))
                    Label(String(localized: "personal.archive.title", defaultValue: "Archive", bundle: PersonalChatStrings.bundle), systemImage: "archivebox")
                        .font(PersonalChatTypography.body(12))
                    Spacer(minLength: 0)
                }.padding(.horizontal, 10).frame(height: 32)
            }.buttonStyle(PersonalChatHoverStyle(radius: 9)).foregroundStyle(palette.muted)
                .help(String(localized: "personal.archive.help", defaultValue: "Archived chats stay on your VPS. Running sessions keep working.", bundle: PersonalChatStrings.bundle))
            if expanded && !(loadingChats && model.sessions.isEmpty) {
                if model.archivedSessions.isEmpty {
                    Text(String(localized: "personal.archive.empty", defaultValue: "No archived chats", bundle: PersonalChatStrings.bundle))
                        .font(PersonalChatTypography.body(11)).foregroundStyle(palette.muted)
                        .padding(.leading, 27).padding(.vertical, 6)
                } else {
                    ForEach(Array(sessions.prefix(limit))) { session in
                        sessionRow(session, projectID: projectID, archived: true).padding(.leading, 12)
                    }
                    if sessions.count > limit {
                        Button(String(localized: "personal.archive.more", defaultValue: "Load more", bundle: PersonalChatStrings.bundle)) { sidebarState.loadMore(projectID) }
                            .buttonStyle(PersonalChatHoverStyle(radius: 7)).font(PersonalChatTypography.body(11.5))
                            .foregroundStyle(palette.secondary).padding(.leading, 27).padding(.vertical, 5)
                    }
                }
            }
        }.padding(.leading, 20)
    }

    private func projectRow(_ project: PersonalChatProject) -> some View {
        HStack(spacing: 0) {
            Button {
                if model.projectID == project.id { withAnimation(motion) { sidebarState.toggleProject(project.id) } }
                else {
                    sidebarState.openProject(project.id)
                    Task { await model.selectProject(project.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.projectID == project.id && sidebarState.projectIsExpanded(project.id) ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold))
                    Image(systemName: "folder").font(.system(size: 13))
                    Text(project.name).font(PersonalChatTypography.body(12.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 32)
            }.buttonStyle(PersonalChatHoverStyle(radius: 9)).help(project.path)
            PersonalChatActionsMenu(label: String(localized: "personal.delete.projectActions", defaultValue: "Project actions", bundle: PersonalChatStrings.bundle)) { projectActions(project) }.padding(.trailing, 4)
        }.disabled(model.busy)
            .foregroundStyle(model.projectID == project.id ? palette.text : palette.secondary)
            .contextMenu { projectActions(project) }
    }

    @ViewBuilder private func projectActions(_ project: PersonalChatProject) -> some View {
        Button(String(localized: "personal.delete.remove", defaultValue: "Remove from app", bundle: PersonalChatStrings.bundle)) { deletionTarget = .init(kind: .removeProject, project: project) }
        Divider()
        Button(String(localized: "personal.delete.project", defaultValue: "Delete project from server…", bundle: PersonalChatStrings.bundle), role: .destructive) { deletionTarget = .init(kind: .project, project: project) }.disabled(!model.connected)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased()).font(PersonalChatTypography.body(10.5, weight: .medium)).tracking(1.35)
            .foregroundStyle(palette.muted).padding(.leading, 10)
    }

    private var connectionFooter: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(palette.text).frame(width: 30, height: 30)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(palette.canvas))
                Circle().fill(model.connected && !model.isReconnecting ? palette.success : palette.faint).frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(palette.canvas, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "CheatCode").font(PersonalChatTypography.body(12, weight: .medium))
                if model.connected || model.isReconnecting {
                    Text(model.connectionStatusText)
                } else {
                    Button(String(localized: "personal.connect", defaultValue: "Connect", bundle: PersonalChatStrings.bundle)) { Task { await model.connect() } }
                        .buttonStyle(.plain).disabled(model.busy || model.connection.host.isEmpty)
                }
            }.font(PersonalChatTypography.body(10.5)).foregroundStyle(palette.secondary)
            Spacer()
            if model.busy || model.isReconnecting { ProgressView().controlSize(.mini) }
            Button { model.showingSettings = true } label: { Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).frame(width: 26, height: 30) }
                .buttonStyle(PersonalChatHoverStyle()).foregroundStyle(palette.muted)
                .help(String(localized: "personal.connection", defaultValue: "Connection", bundle: PersonalChatStrings.bundle))
                .accessibilityLabel(String(localized: "personal.connection", defaultValue: "Connection", bundle: PersonalChatStrings.bundle))
        }.padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 8)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 0) {
                if isConversationEmpty {
                    Spacer(minLength: 20)
                    PersonalChatWelcomeHeading().padding(.horizontal, 24).padding(.bottom, 36)
                    if !model.connected || model.project == nil { setupCard.padding(.bottom, 12) }
                } else {
                    messageList
                }
                PersonalChatComposer(model: model, openTerminal: showTerminal)
                    .frame(maxWidth: 760).padding(.horizontal, 24)
                    .padding(.top, isConversationEmpty ? 0 : 12).padding(.bottom, isConversationEmpty ? 0 : 14)
                    .frame(maxWidth: .infinity)
                if isConversationEmpty { Spacer(minLength: 20) }
            }
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.38), value: isConversationEmpty)
        }
        .background {
            ZStack {
                palette.stage
                if isConversationEmpty { PersonalChatBackdrop().transition(.opacity) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.border))
        .shadow(color: .black.opacity(scheme == .dark ? 0.14 : 0.035), radius: 18, y: 5)
    }

    private var setupCard: some View {
        HStack(spacing: 12) {
            Image(systemName: model.connected ? "folder.badge.plus" : "network")
                .font(.system(size: 17)).frame(width: 36, height: 36)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 10))
            Text(model.connected ? String(localized: "personal.project.add", defaultValue: "Add project", bundle: PersonalChatStrings.bundle) : String(localized: "personal.connection", defaultValue: "Connection", bundle: PersonalChatStrings.bundle))
                .font(PersonalChatTypography.body(13, weight: .medium))
            Spacer()
            Button(model.connected ? String(localized: "personal.project.add", defaultValue: "Add project", bundle: PersonalChatStrings.bundle) : String(localized: "personal.connect", defaultValue: "Connect", bundle: PersonalChatStrings.bundle)) {
                if model.connected { addingProject = true }
                else if model.connection.host.isEmpty { model.showingSettings = true }
                else { Task { await model.connect() } }
            }.buttonStyle(.plain).font(PersonalChatTypography.body(11.5, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(palette.text, in: Capsule()).foregroundStyle(palette.canvas).disabled(model.busy)
        }.padding(12).background(palette.composer, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border))
            .frame(maxWidth: 760).padding(.horizontal, 24).frame(maxWidth: .infinity)
    }

    private var sidebarToggle: some View {
        Button { withAnimation(motion) { sidebarVisible.toggle() } } label: {
            Image(systemName: "sidebar.left").font(.system(size: 13)).frame(width: 28, height: 28)
        }.buttonStyle(PersonalChatHoverStyle()).foregroundStyle(palette.muted)
            .help(String(localized: "personal.sidebar", defaultValue: "Toggle sidebar", bundle: PersonalChatStrings.bundle))
            .accessibilityLabel(String(localized: "personal.sidebar", defaultValue: "Toggle sidebar", bundle: PersonalChatStrings.bundle))
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !sidebarVisible { sidebarToggle }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.project?.name ?? "CheatCode").font(PersonalChatTypography.body(12.5, weight: .medium)).lineLimit(1)
                if let path = model.project?.path {
                    Text(path).font(PersonalChatTypography.body(10)).foregroundStyle(palette.muted).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled).help(path)
                }
            }
            Spacer()
            Button { showingGitHub = true } label: {
                Text(String(localized: "personal.brand.github", defaultValue: "GitHub", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.body(11)).padding(.horizontal, 10).padding(.vertical, 6)
            }.buttonStyle(PersonalChatHoverStyle(radius: 7)).foregroundStyle(palette.secondary).disabled(!model.connected)
            if model.selectedID != nil {
                Button(action: showTerminal) {
                    Label(String(localized: "personal.console.open", defaultValue: "Open console", bundle: PersonalChatStrings.bundle), systemImage: "terminal")
                        .font(PersonalChatTypography.body(11)).padding(.horizontal, 10).padding(.vertical, 6)
                }.buttonStyle(PersonalChatHoverStyle(radius: 7)).foregroundStyle(palette.secondary)
                    .disabled(model.phase == "offline" || !model.connected)
            }
        }.padding(.horizontal, 16).frame(height: 44)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(model.messages) { message in
                        PersonalChatMessageView(message: message, animate: model.revealingMessageIDs.contains(message.id)) { model.finishReveal(message.id) }
                    }
                    ForEach(model.approvals) { approval in
                        PersonalChatApprovalView(approval: approval, disabled: model.busy || !model.connected, decide: { decision, answers in
                            Task { await model.decideApproval(approval, decision: decision, answers: answers) }
                        }, openTerminal: showTerminal)
                        .transition(.opacity)
                    }
                    if let approvalError = model.approvalError {
                        Text(approvalError).font(PersonalChatTypography.body(12)).foregroundStyle(palette.secondary)
                    }
                    if let activity = model.activityText {
                        HStack(spacing: 10) {
                            if model.pendingSend?.state != "uncertain" { ProgressView().controlSize(.small) }
                            Text(activity).font(PersonalChatTypography.body(12)).foregroundStyle(palette.secondary)
                            if model.pendingSend?.state == "uncertain" {
                                Button(String(localized: "personal.delivery.restore", defaultValue: "Restore draft", bundle: PersonalChatStrings.bundle)) { model.restorePendingDraft() }.buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 4).padding(.vertical, 8)
                    }
                    Color.clear.frame(height: 1).id("end")
                }.frame(maxWidth: 760).padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.approvals.map(\.id))
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.messages.last?.text) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: model.approvals.map(\.id)) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    private func showTerminal() {
        guard let id = model.selectedID else { return }
        model.dictation?.cancel(restore: false)
        if PersonalChatConsolePane.supported {
            console.open()
        } else {
            Task {
                guard await model.releaseApprovalsToTerminal(), model.selectedID == id else { return }
                do { openTerminal(try model.connection.terminalCommand(sessionID: id)) }
                catch { model.error = error.localizedDescription }
            }
        }
    }
}
