import Foundation

/// Asks Claude Code itself, by running `claude -p "/usage"`.
///
/// This replaced an elaborate calibration scheme that tried to *infer* the percentage
/// from local transcripts. It was never going to be right: Anthropic's session window
/// resets on its own schedule, and transcripts cannot see usage from claude.ai or
/// another machine. The CLI already knows the real answer.
///
/// Measured on Claude Code 2.1.220:
/// - takes ~1.1s
/// - **costs nothing** — the request count in `/usage` was identical across three
///   consecutive probes, so polling is free
/// - needs no credentials of our own; the CLI handles its own auth, so there is still
///   no keychain access and no password prompt
///
/// (`--bare` is roughly twice as fast but forces API-key auth, so it does not work
/// for subscription accounts.)
enum UsageProbe {
    struct Result: Equatable {
        var percent: Double
        var resetAt: Date?
    }

    enum Failure: Error, CustomStringConvertible {
        case cliNotFound
        case timedOut
        case unparsable(String)

        var description: String {
            switch self {
            case .cliNotFound: return "claude CLI not found"
            case .timedOut: return "timed out"
            case .unparsable(let s): return "unexpected output: \(s.prefix(80))"
            }
        }
    }

    /// The app is launched from Finder, so `PATH` is minimal and `claude` has to be
    /// found by hand.
    static func locateCLI() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func run(timeout: TimeInterval = 40) throws -> Result {
        guard let binary = locateCLI() else { throw Failure.cliNotFound }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["-p", "/usage"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(binary.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        // Keep the probe cheap and free of anything a project might inject.
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        process.environment = env
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()

        // Read on a background queue so a large or stalled stream cannot deadlock
        // the pipe buffer while we wait.
        var data = Data()
        let lock = NSLock()
        let reader = DispatchQueue(label: "usage-probe-reader")
        reader.async {
            let chunk = pipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); data = chunk; lock.unlock()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw Failure.timedOut
        }
        reader.sync {}

        lock.lock(); let output = String(decoding: data, as: UTF8.self); lock.unlock()
        return try parse(output)
    }

    // MARK: - Parsing

    /// Expects a line shaped like:
    /// `Current session: 57% used · resets Jul 29 at 2:40am (America/Indianapolis)`
    static func parse(_ output: String, now: Date = Date()) throws -> Result {
        guard let line = output
            .split(separator: "\n")
            .first(where: { $0.contains("Current session") })
        else { throw Failure.unparsable(output) }

        let text = String(line)

        guard let percentRange = text.range(of: #"([0-9]+(\.[0-9]+)?)\s*%"#, options: .regularExpression),
              let percent = Double(text[percentRange]
                  .replacingOccurrences(of: "%", with: "")
                  .trimmingCharacters(in: .whitespaces))
        else { throw Failure.unparsable(text) }

        var resetAt: Date?
        if let resetsRange = text.range(of: "resets ") {
            var tail = String(text[resetsRange.upperBound...])
            var zone = TimeZone.current
            // Trailing "(America/Indianapolis)" names the zone the time is given in.
            if let open = tail.lastIndex(of: "("), let close = tail.lastIndex(of: ")"), open < close {
                let name = String(tail[tail.index(after: open)..<close])
                if let z = TimeZone(identifier: name.trimmingCharacters(in: .whitespaces)) { zone = z }
                tail = String(tail[..<open])
            }
            resetAt = parseResetTime(tail.trimmingCharacters(in: .whitespaces), zone: zone, now: now)
        }

        return Result(percent: percent, resetAt: resetAt)
    }

    /// Tolerant of the several shapes this string has taken ("Jul 29 at 2:40am",
    /// "today at 2:40am", a bare "2:40am"). The year is never included, so it is
    /// inferred — and corrected across a New Year boundary.
    private static func parseResetTime(_ raw: String, zone: TimeZone, now: Date) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var dayOffset = 0
        for (prefix, offset) in [("today at ", 0), ("tomorrow at ", 1), ("tmr at ", 1)] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                dayOffset = offset
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        // Absolute forms first — they carry a month and day.
        for format in ["MMM d 'at' h:mma", "MMM d 'at' HH:mm", "MMM d, h:mma", "MMM d h:mma"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = zone
            f.dateFormat = format
            guard let parsed = f.date(from: text) else { continue }

            let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            var build = DateComponents()
            build.month = parts.month; build.day = parts.day
            build.hour = parts.hour; build.minute = parts.minute
            build.year = calendar.component(.year, from: now)

            guard var candidate = calendar.date(from: build) else { continue }
            // A reset is always near-future; a big negative gap means the year rolled.
            if candidate.timeIntervalSince(now) < -12 * 3600 {
                build.year! += 1
                candidate = calendar.date(from: build) ?? candidate
            }
            return candidate
        }

        // Time-only forms: today, or tomorrow if that has already passed.
        for format in ["h:mma", "HH:mm", "h:mm a"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = zone
            f.dateFormat = format
            guard let parsed = f.date(from: text) else { continue }
            let hm = calendar.dateComponents([.hour, .minute], from: parsed)
            guard var candidate = calendar.date(bySettingHour: hm.hour ?? 0,
                                                minute: hm.minute ?? 0,
                                                second: 0,
                                                of: now) else { continue }
            if dayOffset != 0 {
                candidate = calendar.date(byAdding: .day, value: dayOffset, to: candidate) ?? candidate
            } else if candidate <= now {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
        return nil
    }
}
