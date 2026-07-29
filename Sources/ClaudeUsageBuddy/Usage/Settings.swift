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

    /// Back-solve the allowance from a percentage read off `/usage`.
    /// If 102M tokens is reportedly 37%, the allowance is ~276M.
    static func calibrate(observedPercent: Double, tokensUsed: Int) {
        guard observedPercent > 0.5, tokensUsed > 0 else { return }
        calibrationSamples = 0
        _ = applyCalibration(impliedAllowance: Double(tokensUsed) / (observedPercent / 100))
    }

    /// Folds a measurement into the stored allowance via a running average, so
    /// repeated calibrations converge instead of overwriting each other.
    @discardableResult
    static func applyCalibration(impliedAllowance implied: Double) -> Int {
        let n = calibrationSamples
        let value: Double
        if n == 0 {
            value = implied
        } else {
            let weight = 1.0 / Double(min(n + 1, 4))
            value = Double(allowance) + (implied - Double(allowance)) * weight
        }
        calibrationSamples = min(n + 1, 100)
        allowance = Int(value.rounded())
        return allowance
    }
}
