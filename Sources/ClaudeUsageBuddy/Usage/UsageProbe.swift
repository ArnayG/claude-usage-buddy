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
        var weekly = Weekly()
    }

    /// Whatever `/usage` is willing to say about the trailing week.
    ///
    /// Every field is optional because the weekly section of `/usage` is not uniform
    /// across plans. On the account this was developed against there is **no weekly
    /// percentage at all** — the only weekly line is
    /// `Last 7d · 1361 requests · 7 sessions`, and the section it sits under is
    /// prefaced with "Approximate, based on local sessions on this machine — does not
    /// include other devices or claude.ai".
    ///
    /// So `percent` stays nil here and the UI must not invent one. It is parsed anyway
    /// because plans with a published weekly cap do exist, and when the CLI reports one
    /// it is authoritative in exactly the way the session percentage is. Nothing in
    /// this type is ever derived from a denominator we guessed.
    struct Weekly: Equatable {
        /// Only ever set from a real `N% used` figure printed by the CLI.
        var percent: Double?
        var resetAt: Date?
        /// The qualifier the CLI attached to the limit, e.g. "all models" or "Opus".
        /// Kept so a per-model sub-limit is never displayed as if it were the overall
        /// one.
        var limitLabel: String?
        /// From the `Last 7d · N requests · M sessions` line. Machine-local and
        /// approximate, per the CLI's own disclaimer — label it as such.
        var requests: Int?
        var sessions: Int?

        var hasPercent: Bool { percent != nil }
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
        // Do NOT set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC here. It looks like a
        // harmless way to keep the probe cheap, but it makes Claude Code skip the
        // fresh utilization fetch and answer from cache — which silently pinned the
        // reported percentage several points below the truth.
        process.environment = env
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let pipe = Pipe()
        process.standardOutput = pipe
        // Discard rather than pipe: an unread stderr pipe deadlocks the child once it
        // fills, and we never look at it anyway.
        process.standardError = FileHandle.nullDevice
        // Without this the CLI waits 3s for stdin that is never coming, tripling the
        // wall time of every probe.
        process.standardInput = FileHandle.nullDevice

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
    ///
    /// The session line is required; everything weekly is best-effort, because most of
    /// it is absent on at least one real plan.
    static func parse(_ output: String, now: Date = Date()) throws -> Result {
        let lines = output.split(separator: "\n").map(String.init)

        guard let text = lines.first(where: { $0.contains("Current session") })
        else { throw Failure.unparsable(output) }

        guard let percent = parsePercent(text) else { throw Failure.unparsable(text) }

        return Result(percent: percent,
                      resetAt: parseResetClause(text, now: now),
                      weekly: parseWeekly(lines, now: now))
    }

    /// First `N%` or `N.N%` in a line.
    private static func parsePercent(_ text: String) -> Double? {
        guard let range = text.range(of: #"([0-9]+(\.[0-9]+)?)\s*%"#, options: .regularExpression)
        else { return nil }
        return Double(text[range]
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces))
    }

    /// Everything after `resets `, resolved against the zone the CLI names in trailing
    /// parentheses.
    private static func parseResetClause(_ text: String, now: Date) -> Date? {
        guard let resetsRange = text.range(of: "resets ") else { return nil }
        var tail = String(text[resetsRange.upperBound...])
        var zone = TimeZone.current
        // Trailing "(America/Indianapolis)" names the zone the time is given in.
        if let open = tail.lastIndex(of: "("), let close = tail.lastIndex(of: ")"), open < close {
            let name = String(tail[tail.index(after: open)..<close])
            if let z = TimeZone(identifier: name.trimmingCharacters(in: .whitespaces)) { zone = z }
            tail = String(tail[..<open])
        }
        return parseResetTime(tail.trimmingCharacters(in: .whitespaces), zone: zone, now: now)
    }

    // MARK: - Weekly

    /// Pulls the weekly figures out of the whole `/usage` block.
    ///
    /// Two independent things are looked for, and either can be missing:
    ///
    /// 1. A **real weekly percentage**, from a line whose *label* mentions a week and
    ///    whose value reads `N% used` — `Current week (all models): 45% used · resets …`.
    ///    Requiring both the label and the literal `% used` is what keeps this away
    ///    from the breakdown bullets in the same block, which are full of percentages
    ///    that are not limit shares at all ("84% of your usage was at >150k context",
    ///    "Top MCP servers: claude-in-chrome 31%"). Reading one of those as a weekly
    ///    limit would be exactly the class of bug this project already deleted once.
    ///
    /// 2. The `Last 7d · N requests · M sessions` counters. Those have no colon, so
    ///    they can never be mistaken for a limit line.
    static func parseWeekly(_ lines: [String], now: Date = Date()) -> Weekly {
        var weekly = Weekly()

        // Take the *highest* of several weekly limits when a plan publishes more than
        // one (an overall cap plus a per-model cap, say). The binding limit is the one
        // closest to being spent, and `limitLabel` carries which one it was so the UI
        // can name it rather than implying it is the total.
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = String(line[line.startIndex..<colon])
            guard label.lowercased().contains("week") else { continue }

            let value = String(line[line.index(after: colon)...])
            guard value.contains("% used"), let percent = parsePercent(value) else { continue }
            guard percent > (weekly.percent ?? -1) else { continue }

            weekly.percent = percent
            weekly.resetAt = parseResetClause(value, now: now)
            // "Current week (all models)" -> "all models".
            if let open = label.firstIndex(of: "("), let close = label.lastIndex(of: ")"), open < close {
                weekly.limitLabel = String(label[label.index(after: open)..<close])
            } else {
                weekly.limitLabel = nil
            }
        }

        // `Last 7d · 1361 requests · 7 sessions`. Also accept "7d"/"7 days" phrasing.
        if let line = lines.first(where: {
            let l = $0.lowercased()
            return !l.contains(":") && (l.contains("last 7d") || l.contains("last 7 d"))
        }) {
            weekly.requests = firstInteger(before: "request", in: line)
            weekly.sessions = firstInteger(before: "session", in: line)
        }

        return weekly
    }

    /// The number immediately preceding a word, e.g. `1361` in "· 1361 requests ·".
    /// Matched by position rather than by index so the two counters cannot be swapped
    /// if the CLI ever reorders them.
    private static func firstInteger(before word: String, in line: String) -> Int? {
        let pattern = "([0-9][0-9,]*)\\s+\(word)"
        guard let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
              let digits = line[range].range(of: #"[0-9][0-9,]*"#, options: .regularExpression)
        else { return nil }
        return Int(line[digits].replacingOccurrences(of: ",", with: ""))
    }

    private static let absoluteFormats = ["MMM d 'at' h:mma", "MMM d 'at' HH:mm",
                                         "MMM d, h:mma", "MMM d h:mma"]
    private static let timeOnlyFormats = ["h:mma", "HH:mm", "h:mm a"]

    /// `DateFormatter` is expensive to build, and these were being constructed inside
    /// the parse loops — up to seven per probe. Cached per time zone instead, which is
    /// the only thing that varies between calls.
    private static let parserCache = NSCache<NSString, NSArray>()

    private static func parsers(_ formats: [String], in zone: TimeZone, tag: String) -> [DateFormatter] {
        let key = "\(tag)|\(zone.identifier)" as NSString
        if let cached = parserCache.object(forKey: key) as? [DateFormatter] { return cached }
        let built = formats.map { format -> DateFormatter in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = zone
            f.dateFormat = format
            return f
        }
        parserCache.setObject(built as NSArray, forKey: key)
        return built
    }

    private static func absoluteParsers(in zone: TimeZone) -> [DateFormatter] {
        parsers(absoluteFormats, in: zone, tag: "abs")
    }

    private static func timeOnlyParsers(in zone: TimeZone) -> [DateFormatter] {
        parsers(timeOnlyFormats, in: zone, tag: "time")
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
        for f in Self.absoluteParsers(in: zone) {
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
        for f in Self.timeOnlyParsers(in: zone) {
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
