import Foundation

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
                    "-o", "StrictHostKeyChecking=yes", "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes",
                    "-o", "PermitLocalCommand=no", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
                    "-o", "ServerAliveCountMax=2", "-o", "BatchMode=yes", "-p", String(port), "-l", "developer"]
        if !identityFile.isEmpty {
            args += ["-o", "IdentitiesOnly=yes", "-i", NSString(string: identityFile).expandingTildeInPath]
        }
        args += [terminal ? "-tt" : "-T", "--", host, command]
        return args
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
