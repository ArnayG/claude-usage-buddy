import Foundation

enum Defaults {
    /// Placeholder 5-hour token allowance, used only until the first calibration.
    ///
    /// Anthropic does not publish a token cap for a rolling session window, and it
    /// varies by plan and tier, so this cannot be looked up — it has to be measured
    /// once against `/usage`.
    static let allowance = 250_000_000
}

/// Small UserDefaults wrapper.
///
/// Nothing here requires a password or touches the keychain: the app reads only the
/// transcripts you already have on disk, plus whatever you type into calibration.
enum Settings {
    private static let d = UserDefaults.standard

    private enum Key {
        static let allowance = "allowance"
        static let showHairline = "showHairlineGauge"
        static let calibrationSamples = "calibrationSamples"
        static let overrideResetAt = "overrideResetAt"
        static let promptedForCalibration = "promptedForCalibration"
        static let lastPoint = "lastCalibrationPoint"
        static let calibratedAt = "calibratedAt"
        static let isTwoPoint = "isTwoPointCalibration"
        static let hiddenTokens = "hiddenTokens"
        static let hiddenWindow = "hiddenTokensWindowStart"
    }

    static var allowance: Int {
        get {
            let v = d.integer(forKey: Key.allowance)
            return v > 0 ? v : Defaults.allowance
        }
        set { d.set(max(newValue, 1), forKey: Key.allowance) }
    }

    static var showHairlineGauge: Bool {
        get { d.object(forKey: Key.showHairline) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.showHairline) }
    }

    /// How many measurements have fed into `allowance`.
    static var calibrationSamples: Int {
        get { d.integer(forKey: Key.calibrationSamples) }
        set { d.set(max(newValue, 0), forKey: Key.calibrationSamples) }
    }

    static var hasCalibrated: Bool { calibrationSamples > 0 }

    /// Set once so the first-run prompt does not reappear if it is dismissed.
    static var promptedForCalibration: Bool {
        get { d.bool(forKey: Key.promptedForCalibration) }
        set { d.set(newValue, forKey: Key.promptedForCalibration) }
    }

    /// An exact reset time copied from `/usage`.
    ///
    /// Local transcripts only cover Claude Code on this Mac, so a window may have
    /// opened earlier than anything on disk — usage from claude.ai, the desktop app,
    /// or another machine is invisible here. Entering the real reset time pins the
    /// current window exactly. It expires on its own once it passes, after which the
    /// countdown reverts to being derived from transcripts.
    static var overrideResetAt: Date? {
        get {
            let t = d.double(forKey: Key.overrideResetAt)
            guard t > 0 else { return nil }
            let date = Date(timeIntervalSince1970: t)
            guard date > Date() else { return nil }
            return date
        }
        set { d.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.overrideResetAt) }
    }

    // MARK: - Calibration

    /// A single (tokens, percent) reading taken from `/usage`.
    struct Point: Codable {
        var rawTokens: Int
        var percent: Double
        var windowStart: Date
        var takenAt: Date
    }

    static var lastPoint: Point? {
        get {
            guard let data = d.data(forKey: Key.lastPoint) else { return nil }
            return try? JSONDecoder().decode(Point.self, from: data)
        }
        set { d.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.lastPoint) }
    }

    static var calibratedAt: Date? {
        get {
            let t = d.double(forKey: Key.calibratedAt)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { d.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.calibratedAt) }
    }

    /// True when the allowance came from two readings rather than one, which means
    /// hidden usage has been solved for rather than absorbed.
    static var isTwoPoint: Bool {
        get { d.bool(forKey: Key.isTwoPoint) }
        set { d.set(newValue, forKey: Key.isTwoPoint) }
    }

    /// Tokens consumed in the current window that this Mac cannot see — usage from
    /// claude.ai, the desktop app, or another machine. Solved for by two-point
    /// calibration; meaningless outside the window it was measured in.
    static var hiddenTokens: Int {
        get { d.integer(forKey: Key.hiddenTokens) }
        set { d.set(max(newValue, 0), forKey: Key.hiddenTokens) }
    }

    static var hiddenTokensWindowStart: Date? {
        get {
            let t = d.double(forKey: Key.hiddenWindow)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { d.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.hiddenWindow) }
    }

    /// Hidden usage belongs to one window only, so it is discarded when the window
    /// rolls over rather than silently inflating the next one.
    static func hiddenTokens(forWindowStarting start: Date?) -> Int {
        guard let start, let recorded = hiddenTokensWindowStart,
              abs(recorded.timeIntervalSince(start)) < 120 else { return 0 }
        return hiddenTokens
    }

    enum CalibrationResult {
        case singlePoint(allowance: Int)
        case twoPoint(allowance: Int, hidden: Int)
        case rejected(reason: String)
    }

    /// Records a reading and recomputes the allowance.
    ///
    /// One reading can only assume nothing is hidden: `allowance = tokens / percent`.
    /// Two readings in the same window are far stronger — the unknown hidden baseline
    /// is identical in both, so it cancels in the difference:
    ///
    ///     allowance = Δtokens / Δpercent
    ///     hidden    = allowance × percent₁ − tokens₁
    ///
    /// which is why recalibrating a second time meaningfully improves accuracy.
    @discardableResult
    static func record(percent: Double, rawTokens: Int, windowStart: Date?) -> CalibrationResult {
        guard percent > 0.5, percent <= 100, rawTokens > 0 else {
            return .rejected(reason: "Enter a percentage between 1 and 100.")
        }
        let now = Date()
        let start = windowStart ?? now
        defer {
            lastPoint = Point(rawTokens: rawTokens, percent: percent,
                              windowStart: start, takenAt: now)
            calibratedAt = now
            calibrationSamples = min(calibrationSamples + 1, 100)
        }

        if let prev = lastPoint,
           abs(prev.windowStart.timeIntervalSince(start)) < 120,
           percent - prev.percent >= 2,
           rawTokens > prev.rawTokens {

            let deltaTokens = Double(rawTokens - prev.rawTokens)
            let deltaFraction = (percent - prev.percent) / 100
            let implied = deltaTokens / deltaFraction

            // Reject nonsense from a mistyped number rather than corrupting a good
            // calibration with it.
            if implied > 1_000_000, implied < 50_000_000_000 {
                let hidden = Int((implied * (prev.percent / 100)) - Double(prev.rawTokens))
                allowance = Int(implied.rounded())
                hiddenTokens = max(hidden, 0)
                hiddenTokensWindowStart = start
                isTwoPoint = true
                return .twoPoint(allowance: allowance, hidden: hiddenTokens)
            }
        }

        // First reading of a window, or too small a change to solve from.
        allowance = Int((Double(rawTokens) / (percent / 100)).rounded())
        hiddenTokens = 0
        hiddenTokensWindowStart = start
        isTwoPoint = false
        return .singlePoint(allowance: allowance)
    }
}
