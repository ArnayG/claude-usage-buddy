import Foundation

/// Claude's "session" limit is a rolling window, not a calendar period.
///
/// A block starts at the top of the hour containing its first request and runs for
/// five hours. A gap of five hours or more with no requests also opens a new block.
/// This mirrors how the usage window is described in-product and how `ccusage`
/// reconstructs it from transcripts.
enum UsageBlock {
    static let windowLength: TimeInterval = 5 * 3600

    struct Block: Equatable {
        var start: Date
        var counts: TokenCounts
        var end: Date { start.addingTimeInterval(windowLength) }
        func isActive(at now: Date) -> Bool { now < end }
    }

    /// Floors to the top of the hour (UTC boundaries, which line up with local
    /// hour boundaries for every timezone at whole-hour offsets).
    static func floorToHour(_ date: Date) -> Date {
        let t = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / 3600).rounded(.down) * 3600)
    }

    /// Splits entries into blocks. Input need not be sorted.
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
                start = floorToHour(e.timestamp)
                acc = TokenCounts()
            }
            acc += e.counts
            last = e.timestamp
        }
        if let s = start { result.append(Block(start: s, counts: acc)) }
        return result
    }

    /// The block covering `now`, if the window is still open.
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
