import Foundation

enum Defaults {
    /// Placeholder 5-hour token allowance.
    ///
    /// Anthropic does not publish a token cap for a rolling session window, and it
    /// varies by plan and tier, so this cannot be looked up — it has to be calibrated.
    /// 250M is a deliberately round starting point sized against observed usage
    /// (a heavy 5h block on this machine measured ~44M raw tokens, cache reads
    /// included). Use Calibrate to replace it with a number derived from `/usage`.
    static let allowance = 250_000_000
}

/// Small UserDefaults wrapper. Nothing here is secret; the OAuth token is never
/// persisted by this app.
enum Settings {
    private static let d = UserDefaults.standard

    private enum Key {
        static let allowance = "allowance"
        static let useServer = "useServerUsage"
        static let showHairline = "showHairlineGauge"
        static let hasCalibrated = "hasCalibrated"
    }

    static var allowance: Int {
        get {
            let v = d.integer(forKey: Key.allowance)
            return v > 0 ? v : Defaults.allowance
        }
        set { d.set(max(newValue, 1), forKey: Key.allowance) }
    }

    /// On by default: read the Keychain OAuth token and ask Anthropic for the real
    /// number. Verified working against Claude Code 2.1.220, and every failure path
    /// falls back to the local estimate, so there is no downside to leaving it on.
    static var useServerUsage: Bool {
        get { d.object(forKey: Key.useServer) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.useServer) }
    }

    static var showHairlineGauge: Bool {
        get { d.object(forKey: Key.showHairline) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.showHairline) }
    }

    /// False while `allowance` is still the placeholder, so the first real
    /// measurement can replace it outright instead of being averaged into it.
    static var hasCalibrated: Bool {
        get { d.bool(forKey: Key.hasCalibrated) }
        set { d.set(newValue, forKey: Key.hasCalibrated) }
    }

    /// Back-solve the allowance from a percentage observed in `/usage`.
    /// If 43.6M tokens is reportedly 17%, the allowance is ~256M.
    static func calibrate(observedPercent: Double, tokensUsed: Int) {
        guard observedPercent > 0.5, tokensUsed > 0 else { return }
        allowance = Int((Double(tokensUsed) / (observedPercent / 100)).rounded())
        hasCalibrated = true
    }
}
