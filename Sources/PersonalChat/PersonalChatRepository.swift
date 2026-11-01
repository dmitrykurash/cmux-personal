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
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
