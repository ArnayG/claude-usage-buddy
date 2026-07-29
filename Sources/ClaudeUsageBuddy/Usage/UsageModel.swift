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

/// Where the reset time came from, which determines how confidently to show it.
enum ResetSource: Equatable {
    /// Copied from `/usage` — exact for the current window.
    case pinned
    /// Derived from the first transcript entry in the window. Approximate, because
    /// transcripts only cover Claude Code on this Mac.
    case inferred
    case unknown
}

/// Everything the notch needs to render, in one value.
struct UsageSnapshot: Equatable {
    var counts: TokenCounts
    var allowance: Int
    var blockStart: Date?
    var resetAt: Date?
    var resetSource: ResetSource = .unknown
    /// Nil until the allowance has been measured against `/usage`.
    var calibratedAt: Date?

    static let empty = UsageSnapshot(counts: TokenCounts(), allowance: Defaults.allowance,
                                     blockStart: nil, resetAt: nil)

    var used: Int { counts.total }
    var remaining: Int { max(allowance - used, 0) }

    var fraction: Double {
        guard allowance > 0 else { return 0 }
        return min(max(Double(used) / Double(allowance), 0), 1)
    }

    var percent: Double { fraction * 100 }

    /// True while the allowance is an unverified guess. The UI must say so rather
    /// than imply precision.
    var isEstimated: Bool { calibratedAt == nil }
}
