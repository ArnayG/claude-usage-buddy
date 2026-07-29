import Foundation

/// Raw token counts as reported by the API in `message.usage`.
struct TokenCounts: Equatable {
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0

    /// Every token the request touched. This is the headline "tokens used" number.
    var total: Int { input + output + cacheCreation + cacheRead }

    static func + (l: TokenCounts, r: TokenCounts) -> TokenCounts {
        TokenCounts(input: l.input + r.input,
                    output: l.output + r.output,
                    cacheCreation: l.cacheCreation + r.cacheCreation,
                    cacheRead: l.cacheRead + r.cacheRead)
    }

    static func += (l: inout TokenCounts, r: TokenCounts) { l = l + r }
}

/// One assistant response parsed out of a transcript.
struct UsageEntry {
    let uuid: String
    let timestamp: Date
    let counts: TokenCounts
    let model: String?
}

/// Everything the notch needs to render.
///
/// The percentage and reset time come from `claude -p "/usage"` — Claude Code's own
/// answer, so there is nothing to calibrate. Local transcripts supply only the token
/// count, which `/usage` does not report.
struct UsageSnapshot: Equatable {
    /// Tokens seen on this Mac within the authoritative window.
    var counts = TokenCounts()
    /// Straight from `/usage`.
    var percent: Double = 0
    var resetAt: Date?
    var windowStart: Date?
    /// When the probe last succeeded. Nil means we have never had a real answer.
    var probedAt: Date?
    /// Set when the last probe failed, for an honest footer.
    var probeError: String?

    static let empty = UsageSnapshot()

    var used: Int { counts.total }
    var fraction: Double { min(max(percent / 100, 0), 1) }

    /// True before the first successful probe — the numbers on screen are not yet
    /// authoritative and the UI should say so.
    var isUnverified: Bool { probedAt == nil }

    /// `/usage` is cheap, so anything this old means probing is broken.
    func isStale(now: Date = Date()) -> Bool {
        guard let probedAt else { return true }
        return now.timeIntervalSince(probedAt) > 15 * 60
    }
}
