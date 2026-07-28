import Foundation

/// Incrementally reads token usage out of `~/.claude/projects/**/*.jsonl`.
///
/// Transcripts are append-only and get large, so each file is tailed from a stored
/// byte offset rather than re-parsed. Records are de-duplicated by `uuid`, which
/// also neutralises the overlap between a session transcript and the per-subagent
/// transcripts written alongside it.
final class TranscriptScanner {
    private let root: URL
    private let retention: TimeInterval

    private var offsets: [String: UInt64] = [:]
    private var seen: Set<String> = []
    private(set) var entries: [UsageEntry] = []

    init(root: URL? = nil, retention: TimeInterval = 8 * 24 * 3600) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        self.retention = retention
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    /// Ingests anything new and returns the retained entry set.
    @discardableResult
    func scan() -> [UsageEntry] {
        for url in transcriptURLs() { ingest(url) }
        prune()
        return entries
    }

    private func transcriptURLs() -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private func ingest(_ url: URL) {
        let path = url.path
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        var offset = offsets[path] ?? 0
        // File shrank — rotated or rewritten. Start over rather than read garbage.
        if size < offset { offset = 0; }
        guard size > offset else { offsets[path] = size; return }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }

        // Only consume up to the last newline; a trailing partial line means the
        // file is mid-write and will be picked up on the next pass.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return }
        let complete = data[data.startIndex...lastNewline]
        offsets[path] = offset + UInt64(complete.count)

        for line in complete.split(separator: 0x0A) where !line.isEmpty {
            if let entry = parse(Data(line)) {
                entries.append(entry)
            }
        }
    }

    private func parse(_ data: Data) -> UsageEntry? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "assistant",
            let uuid = obj["uuid"] as? String,
            !seen.contains(uuid),
            let message = obj["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any],
            let stamp = obj["timestamp"] as? String,
            let date = Self.parseDate(stamp)
        else { return nil }

        seen.insert(uuid)

        var counts = TokenCounts()
        counts.input = usage["input_tokens"] as? Int ?? 0
        counts.output = usage["output_tokens"] as? Int ?? 0
        counts.cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        counts.cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

        // A record with no tokens at all carries no signal.
        guard counts.total > 0 else { return nil }

        return UsageEntry(uuid: uuid, timestamp: date, counts: counts,
                          model: message["model"] as? String)
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        guard entries.contains(where: { $0.timestamp < cutoff }) else { return }
        entries.removeAll { $0.timestamp < cutoff }
        // `seen` intentionally keeps its keys: dropping them would let an old record
        // be re-counted if a file were ever re-read from offset zero.
    }
}
