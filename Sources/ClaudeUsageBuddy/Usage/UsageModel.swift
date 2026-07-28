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

enum UsageSource: String, Equatable {
    /// Derived from ~/.claude/projects transcripts. Always available.
    case local
    /// Reported by Anthropic. Authoritative when reachable.
    case server
}

/// Everything the notch needs to render, in one value.
struct UsageSnapshot: Equatable {
    var counts: TokenCounts
    var allowance: Int
    var blockStart: Date?
    var resetAt: Date?
    var source: UsageSource
    /// Set only when the server hands us an authoritative percentage.
    var serverPercent: Double?

    static let empty = UsageSnapshot(counts: TokenCounts(), allowance: Defaults.allowance,
                                     blockStart: nil, resetAt: nil, source: .local)

    var used: Int { counts.total }
    var remaining: Int { max(allowance - used, 0) }

    /// 0...1, clamped. Prefers the server number when we have one.
    var fraction: Double {
        if let p = serverPercent { return min(max(p / 100, 0), 1) }
        guard allowance > 0 else { return 0 }
        return min(max(Double(used) / Double(allowance), 0), 1)
    }

    var percent: Double { fraction * 100 }

    /// True when the percentage is inferred from a configured allowance rather
    /// than reported by Anthropic. The UI must say so rather than imply precision.
    var isEstimated: Bool { serverPercent == nil }

    var timeUntilReset: TimeInterval? {
        guard let resetAt else { return nil }
        return max(resetAt.timeIntervalSinceNow, 0)
    }
}
