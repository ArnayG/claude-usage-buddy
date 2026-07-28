import Foundation

/// The authoritative usage percentage, straight from the endpoint Claude Code uses
/// to render `/usage`.
///
/// Endpoint and response shape were confirmed against Claude Code 2.1.220 (the
/// string `fetchUtilization: GET /api/oauth/usage` appears in the binary) and against
/// a live 200 response. It is still **not** part of Anthropic's public API, so it can
/// change or disappear on any update — every path here fails soft and leaves the
/// local estimate in place. Never let this break the app.
///
/// Observed payload:
/// ```
/// { "five_hour": { "utilization": 29.0, "resets_at": "2026-07-29T01:39:59.091876+00:00" },
///   "seven_day": null,
///   "limits": [ { "kind": "session", "group": "session", "percent": 29,
///                 "resets_at": "...", "is_active": true }, ... ] }
/// ```
enum ServerUsageClient {
    static var endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct Report {
        /// 0...100 for the five-hour session window.
        var sessionPercent: Double?
        var sessionResetsAt: Date?
        var weeklyPercent: Double?
    }

    enum Failure: Error {
        case notEnabled
        case badStatus(Int)
        case unrecognisedShape
    }

    static func fetch() async throws -> Report {
        guard Settings.useServerUsage else { throw Failure.notEnabled }

        let creds = try KeychainReader.load()
        guard !creds.isExpired else { throw Failure.notEnabled }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.badStatus(code) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unrecognisedShape
        }
        return try decode(json)
    }

    private static func decode(_ json: [String: Any]) throws -> Report {
        var report = Report()

        // Preferred: the canonical `limits` array.
        if let limits = json["limits"] as? [[String: Any]] {
            for limit in limits {
                let kind = limit["kind"] as? String ?? ""
                let group = limit["group"] as? String ?? ""
                let percent = number(limit["percent"])
                let reset = (limit["resets_at"] as? String).flatMap(parseTimestamp)

                if kind == "session" || group == "session" {
                    report.sessionPercent = percent ?? report.sessionPercent
                    report.sessionResetsAt = reset ?? report.sessionResetsAt
                } else if group == "weekly", let p = percent {
                    // Several weekly buckets can be present (opus, sonnet, scoped).
                    // The binding one is whichever is highest.
                    report.weeklyPercent = max(report.weeklyPercent ?? 0, p)
                }
            }
        }

        // Fallback: the flat `five_hour` object.
        if report.sessionPercent == nil, let fiveHour = json["five_hour"] as? [String: Any] {
            report.sessionPercent = number(fiveHour["utilization"])
            report.sessionResetsAt = (fiveHour["resets_at"] as? String).flatMap(parseTimestamp)
        }
        if report.weeklyPercent == nil, let sevenDay = json["seven_day"] as? [String: Any] {
            report.weeklyPercent = number(sevenDay["utilization"])
        }

        guard report.sessionPercent != nil else { throw Failure.unrecognisedShape }
        return report
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    /// Timestamps arrive with microsecond precision ("...:59.091876+00:00"), which
    /// ISO8601DateFormatter will not parse — it handles milliseconds at most. Drop
    /// the fractional part entirely; second precision is ample for a countdown.
    static func parseTimestamp(_ raw: String) -> Date? {
        var trimmed = raw
        if let dot = raw.firstIndex(of: "."),
           let tz = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            trimmed = String(raw[raw.startIndex..<dot]) + String(raw[tz...])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}
