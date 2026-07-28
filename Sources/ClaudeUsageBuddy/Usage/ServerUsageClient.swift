import Foundation

/// Optional, opt-in path to the authoritative usage percentage.
///
/// IMPORTANT: this endpoint is not part of Anthropic's public API. It is whatever
/// Claude Code itself calls to render `/usage`, and it can change or disappear on
/// any update. Everything here is written to fail soft — any error at all leaves
/// the local estimate in place. Never let this path break the app.
///
/// To confirm or correct the endpoint, run `claude --debug api`, invoke `/usage`,
/// and read the request it makes.
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
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.badStatus(code) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unrecognisedShape
        }
        return try decode(json)
    }

    /// Deliberately shape-tolerant: walks the payload looking for the numbers we
    /// need instead of hard-binding to a schema that is not ours to depend on.
    private static func decode(_ json: [String: Any]) throws -> Report {
        var report = Report()

        func visit(_ node: Any, path: String) {
            guard let dict = node as? [String: Any] else {
                if let arr = node as? [Any] {
                    for item in arr { visit(item, path: path) }
                }
                return
            }
            let isWeekly = path.contains("7d") || path.contains("week")
            let isSession = path.contains("5h") || path.contains("session")

            for (key, value) in dict {
                let lower = key.lowercased()
                let childPath = path + "." + lower

                if let number = value as? Double ?? (value as? Int).map(Double.init) {
                    if lower.contains("utilization") || lower.contains("percent") || lower.contains("pct") {
                        // Some payloads express utilisation as 0...1.
                        let pct = number <= 1.0 ? number * 100 : number
                        if isWeekly { report.weeklyPercent = pct }
                        else if isSession || report.sessionPercent == nil { report.sessionPercent = pct }
                    }
                    if lower.contains("reset"), number > 1_000_000 {
                        let seconds = number > 1e11 ? number / 1000 : number
                        if !isWeekly { report.sessionResetsAt = Date(timeIntervalSince1970: seconds) }
                    }
                } else if let s = value as? String, lower.contains("reset"),
                          let date = ISO8601DateFormatter().date(from: s) {
                    if !isWeekly { report.sessionResetsAt = date }
                } else {
                    visit(value, path: childPath)
                }
            }
        }

        visit(json, path: "")
        guard report.sessionPercent != nil else { throw Failure.unrecognisedShape }
        return report
    }
}
