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
    /// When Anthropic last confirmed the real percentage, which is what calibrated
    /// `allowance`. Nil means the allowance is still a guess.
    var serverSyncedAt: Date?

    static let empty = UsageSnapshot(counts: TokenCounts(), allowance: Defaults.allowance,
                                     blockStart: nil, resetAt: nil, source: .local)

    var used: Int { counts.total }
    var remaining: Int { max(allowance - used, 0) }

    /// Always computed locally, from an exact token count and a calibrated
    /// allowance.
    ///
    /// Deliberately *not* the server's percentage held as a stored value: the usage
    /// endpoint is rate limited, so it can only be called every few minutes, and a
    /// stored percentage would sit frozen between calls while tokens kept climbing.
    /// The server's job is to calibrate `allowance`; the percentage then updates
    /// continuously and still agrees with it.
    var fraction: Double {
        guard allowance > 0 else { return 0 }
        return min(max(Double(used) / Double(allowance), 0), 1)
    }

    var percent: Double { fraction * 100 }

    /// True while the allowance is an unverified guess. The UI must say so rather
    /// than imply precision.
    var isEstimated: Bool { serverSyncedAt == nil }

    var timeUntilReset: TimeInterval? {
        guard let resetAt else { return nil }
        return max(resetAt.timeIntervalSinceNow, 0)
    }
}
