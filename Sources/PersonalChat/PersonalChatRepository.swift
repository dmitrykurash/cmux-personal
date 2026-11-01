import Foundation

actor PersonalChatRepository {
    struct Configuration: Codable, Sendable {
        var connection = PersonalChatConnection()
        var projects: [PersonalChatProject] = []
        var selectedProjectID: UUID?
        var selectedSessionID: String?
    }
    private let file: URL

    init(file: URL) { self.file = file }

    func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: file.path) else { return Configuration() }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
    }

    func save(_ value: Configuration) throws {
        try write(JSONEncoder().encode(value), to: file)
    }

    // Separate from connection settings so an older preview cannot erase the archive.
    private var archiveFile: URL { file.deletingPathExtension().appendingPathExtension("archive.json") }

    func loadArchive() throws -> [String: Set<String>] {
        guard FileManager.default.fileExists(atPath: archiveFile.path) else { return [:] }
        return try JSONDecoder().decode([String: Set<String>].self, from: Data(contentsOf: archiveFile))
    }

    func saveArchive(_ value: [String: Set<String>]) throws {
        try write(JSONEncoder().encode(value), to: archiveFile)
    }

    private func write(_ data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
