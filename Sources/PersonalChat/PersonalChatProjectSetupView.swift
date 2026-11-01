import SwiftUI

struct PersonalChatProjectSetupView: View {
    @State private var importer: PersonalChatProjectImporter
    let addProject: @MainActor (String, String) async throws -> Void
    let openTerminal: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var browsing = false

    init(importer: PersonalChatProjectImporter, addProject: @escaping @MainActor (String, String) async throws -> Void, openTerminal: @escaping (String) -> Void) {
        _importer = State(initialValue: importer)
        self.addProject = addProject
        self.openTerminal = openTerminal
    }

    var body: some View {
        let palette = PersonalChatPalette(scheme: scheme)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.plus").font(.system(size: 22)).foregroundStyle(palette.accent)
                Text(String(localized: "personal.project.add", defaultValue: "Add project", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.display(30))
                Spacer()
            }
            Picker(String(localized: "personal.import.source", defaultValue: "Project source", bundle: PersonalChatStrings.bundle), selection: $importer.mode) {
                ForEach(PersonalChatProjectSource.allCases) { source in Text(source.label).tag(source) }
            }.pickerStyle(.segmented).disabled(importer.locked)
                .onChange(of: importer.mode) { importer.issue = nil; importer.pathEdited = false; importer.suggestPath() }
            if importer.mode == .clone {
                field(String(localized: "personal.import.url", defaultValue: "Repository URL", bundle: PersonalChatStrings.bundle)) {
                    TextField("", text: $importer.repository, prompt: Text(verbatim: "https://github.com/owner/repository"))
                        .accessibilityLabel(String(localized: "personal.import.url", defaultValue: "Repository URL", bundle: PersonalChatStrings.bundle))
                        .onChange(of: importer.repository) { importer.suggestName() }
                }
                Text(String(localized: "personal.import.privateNote", defaultValue: "Private repositories use Git access on the VPS. Sign in once, then import by URL.", bundle: PersonalChatStrings.bundle))
                    .font(PersonalChatTypography.body(11)).foregroundStyle(palette.secondary)
                if importer.hasGitHubCLI {
                    Button {
                        do { openTerminal(try importer.connection.githubSignInCommand()) }
                        catch { importer.issue = error.localizedDescription }
                    } label: {
                        Label(String(localized: "personal.import.githubLogin", defaultValue: "Sign in to GitHub…", bundle: PersonalChatStrings.bundle), systemImage: "arrow.up.right.square")
                    }.buttonStyle(.plain).font(PersonalChatTypography.body(12)).disabled(importer.busy)
                }
            }
            field(String(localized: "personal.project.name", defaultValue: "Name", bundle: PersonalChatStrings.bundle)) {
                TextField("", text: Binding(get: { importer.name }, set: { importer.name = $0; importer.nameEdited = true; importer.suggestPath() }))
                    .accessibilityLabel(String(localized: "personal.project.name", defaultValue: "Name", bundle: PersonalChatStrings.bundle))
            }
            field(String(localized: "personal.project.path", defaultValue: "Folder on the VPS", bundle: PersonalChatStrings.bundle)) {
                HStack {
                    TextField("", text: Binding(get: { importer.path }, set: { importer.path = $0; importer.pathEdited = true }))
                        .accessibilityLabel(String(localized: "personal.project.path", defaultValue: "Folder on the VPS", bundle: PersonalChatStrings.bundle))
                        .font(.system(size: 12, design: .monospaced))
                    Button { browsing = true } label: { Image(systemName: "folder") }
                        .buttonStyle(.plain).help(String(localized: "personal.import.chooseFolder", defaultValue: "Choose folder on VPS", bundle: PersonalChatStrings.bundle))
                        .accessibilityLabel(String(localized: "personal.import.chooseFolder", defaultValue: "Choose folder on VPS", bundle: PersonalChatStrings.bundle))
                }
            }
            Text(String(localized: "personal.import.folderNote", defaultValue: "Chats in this project share this folder. Existing files are never replaced by an import.", bundle: PersonalChatStrings.bundle))
                .font(PersonalChatTypography.body(11)).foregroundStyle(palette.secondary)
            if let issue = importer.issue {
                Label(issue, systemImage: "exclamationmark.circle").font(PersonalChatTypography.body(12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if importer.busy {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "personal.import.working", defaultValue: "Preparing project…", bundle: PersonalChatStrings.bundle)).font(PersonalChatTypography.body(12)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Button(String(localized: "personal.cancel", defaultValue: "Cancel", bundle: PersonalChatStrings.bundle)) {
                    if importer.jobID != nil { Task { await importer.cancel() } }
                    else { dismiss() }
                }.disabled((importer.busy && importer.jobID == nil) || importer.cancelling)
                Button(importer.jobID == nil && importer.preparedPath == nil ? String(localized: "personal.project.add", defaultValue: "Add project", bundle: PersonalChatStrings.bundle) : String(localized: "personal.import.check", defaultValue: "Check import", bundle: PersonalChatStrings.bundle)) {
                    Task { if await importer.submit(onReady: addProject) { dismiss() } }
                }.buttonStyle(.borderedProminent).disabled(!importer.canSubmit)
            }.padding(.top, 4)
        }.padding(28).frame(width: 540).background(palette.canvas)
            .interactiveDismissDisabled(importer.busy || importer.jobID != nil)
            .sheet(isPresented: $browsing) {
                PersonalChatFolderPicker(importer: importer) { folder in
                    if importer.mode == .existing {
                        importer.path = folder
                        if !importer.nameEdited { importer.name = (folder as NSString).lastPathComponent }
                        importer.pathEdited = true
                    } else {
                        importer.basePath = folder
                        importer.pathEdited = false
                        importer.suggestPath()
                    }
                }
            }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let palette = PersonalChatPalette(scheme: scheme)
        return VStack(alignment: .leading, spacing: 7) {
            Text(title).font(PersonalChatTypography.body(11, weight: .medium)).foregroundStyle(palette.secondary)
            content().textFieldStyle(.plain).padding(11)
                .background(palette.composer, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border.opacity(0.6), lineWidth: 1))
                .disabled(importer.locked)
        }
    }
}
