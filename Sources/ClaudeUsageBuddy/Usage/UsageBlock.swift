import Foundation

/// Claude's "session" limit is a rolling window anchored to activity, not a calendar
/// period. A window opens on the first request after a five-hour lull and runs for
/// five hours from that moment.
///
/// The anchor is the request timestamp itself, **not** the top of the hour. Anthropic's
/// own reset times land on precise seconds (a window observed here reset at 21:39:59,
/// i.e. it opened at 16:39:59), so rounding down to the hour would shift the countdown
/// by up to an hour in the wrong direction.
enum UsageBlock {
    static let windowLength: TimeInterval = 5 * 3600

    struct Block: Equatable {
        var start: Date
        var counts: TokenCounts
        var end: Date { start.addingTimeInterval(windowLength) }
        func isActive(at now: Date) -> Bool { now < end }
    }

    /// Splits entries into windows. Input need not be sorted.
    static func blocks(from entries: [UsageEntry]) -> [Block] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }

        var result: [Block] = []
        var start: Date?
        var last: Date?
        var acc = TokenCounts()

        for e in sorted {
            let opensNewBlock: Bool
            if let s = start, let l = last {
                opensNewBlock = e.timestamp >= s.addingTimeInterval(windowLength)
                    || e.timestamp.timeIntervalSince(l) >= windowLength
            } else {
                opensNewBlock = true
            }

            if opensNewBlock {
                if let s = start { result.append(Block(start: s, counts: acc)) }
                start = e.timestamp
                acc = TokenCounts()
            }
            acc += e.counts
            last = e.timestamp
        }
        if let s = start { result.append(Block(start: s, counts: acc)) }
        return result
    }

    /// The window covering `now`, if one is still open.
    static func current(from entries: [UsageEntry], now: Date = Date()) -> Block? {
        guard let last = blocks(from: entries).last, last.isActive(at: now) else { return nil }
        return last
    }

    /// Rolling 7-day total, for the secondary weekly readout.
    static func trailingWeek(from entries: [UsageEntry], now: Date = Date()) -> TokenCounts {
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        return entries.reduce(into: TokenCounts()) { acc, e in
            if e.timestamp >= cutoff { acc += e.counts }
        }
    }
}
