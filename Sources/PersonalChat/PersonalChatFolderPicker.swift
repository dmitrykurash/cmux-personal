import SwiftUI

struct PersonalChatFolderPicker: View {
    let importer: PersonalChatProjectImporter
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var parent = ""
    @State private var folders: [String] = []
    @State private var busy = false
    @State private var issue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "personal.import.chooseFolder", defaultValue: "Choose folder on VPS", bundle: PersonalChatStrings.bundle)).font(.headline)
            HStack {
                Button { Task { await load(parent) } } label: { Image(systemName: "arrow.up") }
                    .disabled(busy || parent.isEmpty || parent == current)
                    .help(String(localized: "personal.import.parentFolder", defaultValue: "Parent folder", bundle: PersonalChatStrings.bundle))
                    .accessibilityLabel(String(localized: "personal.import.parentFolder", defaultValue: "Parent folder", bundle: PersonalChatStrings.bundle))
                Text(current).font(.system(size: 11, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(folders, id: \.self) { folder in
                        Button { Task { await load((current as NSString).appendingPathComponent(folder)) } } label: {
                            HStack {
                                Label(folder, systemImage: "folder")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(9).contentShape(Rectangle())
                        }.buttonStyle(PersonalChatHoverStyle()).disabled(busy)
                    }
                }
            }.frame(height: 240)
            HStack {
                Button(String(localized: "personal.cancel", defaultValue: "Cancel", bundle: PersonalChatStrings.bundle)) { dismiss() }
                Spacer()
                Button(String(localized: "personal.import.useFolder", defaultValue: "Use this folder", bundle: PersonalChatStrings.bundle)) { choose(current); dismiss() }
                    .buttonStyle(.borderedProminent).disabled(busy || current.isEmpty || issue != nil)
            }
        }.padding(24).frame(width: 480)
            .task { await load(importer.basePath) }
    }

    private func load(_ path: String) async {
        guard !busy else { return }
        busy = true
        issue = nil
        defer { busy = false }
        do {
            let reply = try await importer.listFolders(path)
            current = reply.path ?? path
            parent = reply.parent ?? path
            folders = reply.directories ?? []
        } catch { issue = error.localizedDescription }
    }
}
