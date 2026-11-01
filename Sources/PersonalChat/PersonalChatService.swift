import Foundation

actor PersonalChatService: PersonalChatServing {
    private let source: String

    init(source: String) {
        self.source = source
    }

    func request(_ request: PersonalChatRequest, connection: PersonalChatConnection) async throws -> PersonalChatReply {
        guard !source.isEmpty else { throw PersonalChatError.missingBridge }
        var request = request
        if request.op == "install" || (request.op == "project_prepare" && request.mode == "clone") { request.source = source }
        let input = try JSONEncoder().encode(request)
        let command = "python3 -c " + PersonalChatConnection.quote(source)
        let arguments = try connection.arguments(command: command)
        return try await Self.run(arguments: arguments, input: input, timeout: request.op == "deletion_commit" ? 300_000_000_000 : 45_000_000_000)
    }

    private static func run(arguments: [String], input: Data, timeout: UInt64) async throws -> PersonalChatReply {
        // Files avoid pipe deadlocks for attachments and large transcripts. The
        // private directory is removed on every exit; no command/output logging.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-personal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let inputURL = folder.appendingPathComponent("input")
        let outputURL = folder.appendingPathComponent("output")
        try input.write(to: inputURL)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let stdin = try FileHandle(forReadingFrom: inputURL)
        let stdout = try FileHandle(forWritingTo: outputURL)
        defer { try? stdin.close(); try? stdout.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            let deadline = Task {
                try await Task.sleep(nanoseconds: timeout)
                if process.isRunning { process.terminate() }
            }
            defer { deadline.cancel() }
            let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
            try Task.checkCancellation()
            let output = try Data(contentsOf: outputURL)
            guard let reply = try? JSONDecoder().decode(PersonalChatReply.self, from: output) else { throw PersonalChatError.sshFailed }
            guard reply.ok, status == 0 else {
                if let code = reply.code { throw PersonalChatProjectError(code: code) }
                throw PersonalChatError.remote(reply.error ?? "SSH failed")
            }
            return reply
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
