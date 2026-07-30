import Foundation

/// Small UserDefaults wrapper.
///
/// Deliberately tiny. An earlier version carried a token allowance, calibration
/// samples, a solved off-device baseline and a pinned reset time — all of it existed
/// to *infer* a percentage. `claude -p "/usage"` reports the real one, so none of it
/// is needed.
enum Settings {
    private static let d = UserDefaults.standard

    private enum Key {
        static let showHairline = "showHairlineGauge"
        static let burnHistory = "burnHistory"
    }

    static var showHairlineGauge: Bool {
        get { d.object(forKey: Key.showHairline) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.showHairline) }
    }

    /// Recent `/usage` readings, so the burn-rate trend survives a relaunch instead of
    /// starting from "need more readings" every time.
    ///
    /// This is a *measurement* log, not the inferred state the calibration keys held: the
    /// samples are verbatim probe output, they are scoped to the current window, and
    /// losing the whole lot costs nothing worse than a few minutes of "need more
    /// readings". A corrupt or unreadable blob is silently treated as empty for the same
    /// reason — there is nothing here worth failing over.
    static var burnHistory: BurnHistory {
        get {
            guard let data = d.data(forKey: Key.burnHistory),
                  let decoded = try? JSONDecoder().decode(BurnHistory.self, from: data)
            else { return BurnHistory() }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                d.removeObject(forKey: Key.burnHistory)
                return
            }
            d.set(data, forKey: Key.burnHistory)
        }
    }

    /// Clears keys written by the calibration-era builds.
    static func removeLegacyKeys() {
        for key in ["allowance", "calibrationSamples", "hasCalibrated", "promptedForCalibration",
                    "overrideResetAt", "lastCalibrationPoint", "calibratedAt",
                    "isTwoPointCalibration", "hiddenTokens", "hiddenTokensWindowStart",
                    "useServerUsage"] {
            d.removeObject(forKey: key)
        }
    }
}
