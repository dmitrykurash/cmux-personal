import Foundation
import Testing

/// Throwaway diagnostic (not for merge): what one git process costs on a fleet host.
struct GitSpawnTimingDiagTests {
    private static func time(_ executable: String, _ arguments: [String], environment: [String: String]?) throws -> (Duration, String) {
        let started = ContinuousClock.now
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (ContinuousClock.now - started, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func gitSpawnCost() throws {
        let env = ProcessInfo.processInfo.environment
        print("DIAG-GIT DEVELOPER_DIR=\(env["DEVELOPER_DIR"] ?? "unset") TMPDIR=\(env["TMPDIR"] ?? "unset") HOME=\(env["HOME"] ?? "unset")")
        let real = try Self.time("/usr/bin/xcrun", ["--find", "git"], environment: nil).1
        print("DIAG-GIT xcrun --find git -> \(real)")
        let minimal = ["PATH": "/usr/bin:/bin", "HOME": NSTemporaryDirectory(), "GIT_CONFIG_NOSYSTEM": "1"]
        for (label, executable, environment) in [("shim inherited", "/usr/bin/git", nil as [String: String]?),
                                                 ("shim minimal", "/usr/bin/git", minimal),
                                                 ("real inherited", real, nil), ("real minimal", real, minimal),
                                                 ("sh", "/bin/sh", nil)] {
            var times: [String] = []
            for _ in 0..<5 {
                let (took, _) = try Self.time(executable, executable == "/bin/sh" ? ["-c", "true"] : ["--version"], environment: environment)
                times.append("\(took.components.attoseconds / 1_000_000_000_000_000 + took.components.seconds * 1000)ms")
            }
            print("DIAG-GIT \(label): \(times)")
        }
    }
}
