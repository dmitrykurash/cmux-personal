import CmuxNextCompat
import Foundation

/// One progress line of `cmux link seed push` (stderr, `{"progress":{...}}`; cmux-tui
/// `link/seed_cli.rs`), as the fields the start card's clone row takes. The CLI and the page own
/// the words; this only forwards numbers.
nonisolated struct SeedProgress: Sendable, Equatable {
    /// `upload`, `clone`, `fetch`, `bundle`, `checkout`, `submodules`, `lfs`, or `copy` for the
    /// streamed copy (its lines carry files).
    var phase: String
    var bytesDone: Int?
    var bytesTotal: Int?
    var objects: Int?
    var objectsTotal: Int?
    var filesDone: Int?
    var filesTotal: Int?
    /// A seed that copied instead: why, and the cmux GitHub App's install link for `seed.needs_github`.
    var fallbackCode: String?
    var installURL: String?

    /// The line's progress; nil for any other line.
    static func parse(_ line: String) -> SeedProgress? {
        guard line.hasPrefix("{"),
              let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let fields = object["progress"] as? [String: Any] else { return nil }
        let int = { (key: String) in (fields[key] as? NSNumber)?.intValue }
        let filesTotal = int("files_total")
        guard let phase = fields["phase"] as? String ?? (filesTotal != nil ? "copy" : nil) else { return nil }
        return SeedProgress(phase: phase, bytesDone: int("bytes_done"), bytesTotal: int("bytes_total"), objects: int("objects"),
                            objectsTotal: int("objects_total"), filesDone: int("files_done"), filesTotal: filesTotal,
                            fallbackCode: fields["fallback_code"] as? String, installURL: fields["install_url"] as? String)
    }

    /// Least time between two progress values handed on (about 4 a second).
    static let every: Duration = .milliseconds(250)

    /// A stderr line reader that hands `handle` each progress line, at most one per ``every``,
    /// except a phase change or a fallback, which always goes. A fallback's install link stays on
    /// the copy's lines after it.
    static func reader(_ handle: @escaping @Sendable (SeedProgress) -> Void) -> @Sendable (String) -> Void {
        let state = Mutex<(last: ContinuousClock.Instant?, phase: String?, installURL: String?, fallbackCode: String?)>((nil, nil, nil, nil))
        return { line in
            guard var progress = parse(line) else { return }
            let now = ContinuousClock.now
            let send = state.withLock { state -> Bool in
                if progress.fallbackCode != nil { (state.fallbackCode, state.installURL) = (progress.fallbackCode, progress.installURL) }
                (progress.fallbackCode, progress.installURL) = (state.fallbackCode, state.installURL)
                let due = state.phase != progress.phase || state.last.map { now - $0 >= every } ?? true
                if due { (state.last, state.phase) = (now, progress.phase) }
                return due
            }
            if send { handle(progress) }
        }
    }
}
