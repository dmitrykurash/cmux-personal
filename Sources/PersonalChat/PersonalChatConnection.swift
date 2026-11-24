import Foundation
import CryptoKit

struct PersonalChatConnection: Codable, Equatable, Sendable {
    var host = ""
    var port = 22
    var identityFile = ""

    func arguments(command: String, terminal: Bool = false) throws -> [String] {
        guard !host.isEmpty, host.first != "-", host.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil,
              (1...65535).contains(port), !identityFile.contains("\n") else {
            throw PersonalChatError.invalidConnection
        }
        var args = ["-o", "UseKeychain=yes", "-o", "AddKeysToAgent=yes",
                    "-o", "StrictHostKeyChecking=yes", "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ClearAllForwardings=yes",
                    "-o", "PermitLocalCommand=no", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
                    "-o", "ServerAliveCountMax=2", "-o", "BatchMode=yes", "-p", String(port), "-l", "developer"]
        if !identityFile.isEmpty {
            args += ["-o", "IdentitiesOnly=yes", "-i", NSString(string: identityFile).expandingTildeInPath]
        }
        args += ["-o", "ControlMaster=auto", "-o", "ControlPersist=60", "-o", "ControlPath=" + (try controlPath())]
        args += [terminal ? "-tt" : "-T", "--", host, command]
        return args
    }

    private func controlPath() throws -> String {
        // Use a short path for macOS's Unix socket limit. The directory is private
        // to this user; host, port and identity select separate authenticated links.
        let directory = "/private/tmp/cheatcode-ssh-" + String(getuid())
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory) {
            do {
                try manager.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            } catch CocoaError.fileWriteFileExists {
                // Another request may have created the same private directory.
            }
        }
        let attributes = try manager.attributesOfItem(atPath: directory)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw PersonalChatError.invalidConnection
        }
        let identity = NSString(string: identityFile).expandingTildeInPath
        let data = try JSONEncoder().encode([host, String(port), identity])
        let digest = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory + "/" + digest
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func githubSignInCommand() throws -> String {
        let remote = "export PATH=\"$HOME/.local/bin:$PATH\"; " +
            "gh auth login --hostname github.com --git-protocol https --web && gh auth setup-git --hostname github.com"
        return try (["/usr/bin/ssh"] + arguments(command: remote, terminal: true)).map(Self.quote).joined(separator: " ")
    }

    func terminalCommand(sessionID: String) throws -> String {
        guard UUID(uuidString: sessionID) != nil else { throw PersonalChatError.invalidConnection }
        let remote = "exec \"$HOME/.local/bin/tmux\" -L cmux-personal attach-session -t " + Self.quote("=cmp-" + sessionID.lowercased())
        // Use PATH fallback on hosts with system tmux.
        let command = "if [ -x \"$HOME/.local/bin/tmux\" ]; then " + remote +
            "; else exec tmux -L cmux-personal attach-session -t " + Self.quote("=cmp-" + sessionID.lowercased()) + "; fi"
        return try (["/usr/bin/ssh"] + arguments(command: command, terminal: true)).map(Self.quote).joined(separator: " ")
    }
}
