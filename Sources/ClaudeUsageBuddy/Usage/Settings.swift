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
    }

    static var showHairlineGauge: Bool {
        get { d.object(forKey: Key.showHairline) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.showHairline) }
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
