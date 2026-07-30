import SwiftUI

enum Theme {
    /// Pure black, matching the cutout as closely as pixels allow.
    ///
    /// Verified #000000 when rendered — there is nothing darker available, so any
    /// remaining difference against the physical notch is the display's black point
    /// versus an unlit bezel, not something a colour value can fix. What *can* be
    /// fixed is light bleeding in from nearby: hence no outline stroke, and text a
    /// little below full white so mini-LED local dimming does not lift the black
    /// around it.
    static let panel = Color.black

    static let primaryText = Color.white.opacity(0.93)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.34)
    static let hairline = Color.white.opacity(0.10)

    static let ok = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let warn = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let critical = Color(red: 0.97, green: 0.44, blue: 0.44)

    /// Green until half, amber through the second half, red once the window is
    /// nearly spent.
    static func gauge(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.5: return ok
        case ..<0.8: return warn
        default: return critical
        }
    }

    // MARK: - Per-model split

    /// Category colours for the model split, hand-picked for the three families that
    /// exist today.
    ///
    /// Cool hues only — these sit at 197°, 248° and 314°. Warm colour on this panel is
    /// already spoken for twice: the ring runs green→amber→red for how spent the window
    /// is, and the buddy is clay. A warm slice here would read as a third severity
    /// signal rather than as a category, which is exactly the wrong message — which
    /// model you used is not good or bad news. All three measure above 7:1 against the
    /// black panel, and they stay apart from each other by at least 50° of hue so the
    /// bar survives being 9pt tall.
    static let modelColours: [String: Color] = [
        "opus":   Color(red: 0.61, green: 0.55, blue: 1.00),   // #9B8CFF periwinkle
        "sonnet": Color(red: 0.31, green: 0.76, blue: 0.94),   // #4FC1F0 sky
        "haiku":  Color(red: 0.94, green: 0.55, blue: 0.85),   // #F08CD8 orchid
    ]

    /// Reserved for the grouped tail, so "Other" is visibly not a named model.
    static let modelOther = Color(red: 0.55, green: 0.58, blue: 0.65)   // #8C93A6

    /// Colour for a model family, including ones that do not exist yet.
    ///
    /// An unrecognised family gets a hue rotated deterministically inside the same cool
    /// band, so a model shipped after this build still draws a legible slice — and the
    /// same colour on every launch — instead of vanishing or borrowing its neighbour's.
    /// Two unknown families can in principle land on similar hues; the legend names
    /// every slice, so colour is the hint and the label is the answer.
    static func modelColour(for key: String) -> Color {
        if let named = modelColours[key] { return named }
        if key == ModelUsage.otherKey { return modelOther }

        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        // 196°–320°: the cool band, clear of the ring's greens and the buddy's clay.
        return Color(hue: (196 + Double(hash % 125)) / 360,
                     saturation: 0.62, brightness: 0.94)
    }

    static let cornerRadius: CGFloat = 22

    /// Radius of the quarter-circle cove where the panel meets the top of the display.
    /// Circular on both axes by definition — see `NotchPanelShape`.
    static let coveRadius: CGFloat = 14
}

/// The expanded panel's silhouette: a true circular cove into the top edge of the
/// display, rounded at the bottom.
///
/// The top corners **add** black, sweeping outward to meet the top edge, the way the
/// display's active area curves around the real cutout. Rounding them off instead —
/// removing black — narrows the panel exactly where the hardware widens it.
///
/// The cove is a **quarter circle**, and getting that exactly right matters more than
/// its size. Two earlier versions missed it in different ways: one used a quadratic
/// curve, which cannot describe a circular arc at all, and one used an ellipse (wider
/// than deep) with a deliberately flattened middle. Both read as a generic arc rather
/// than a corner, because Apple's hardware and software corners are circular and the
/// eye is calibrated to that.
///
/// So: equal width and depth, and `circleControl` is the exact cubic-Bezier constant
/// for a quarter circle — 4/3·(√2−1). At that value a cubic matches a true arc to
/// within about 0.02% of the radius; nudging it, as an earlier revision did to taste,
/// is what turns a circle into "some curve".
struct NotchPanelShape: Shape {
    /// Radius of the quarter-circle cove. Applies to both axes: it is a circle.
    var coveRadius: CGFloat = Theme.coveRadius
    var bottomRadius: CGFloat = Theme.cornerRadius

    /// 4/3·(tan(45°/2)) = 4/3·(√2−1). The standard constant for approximating a
    /// quarter circle with one cubic segment.
    private let circleControl: CGFloat = 0.5522847498307936

    func path(in rect: CGRect) -> Path {
        let r = min(coveRadius, min(rect.width / 4, rect.height / 4))
        let br = min(bottomRadius, min(rect.width / 2 - r, rect.height / 2))
        let k = r * circleControl

        var p = Path()
        // Full width along the very top edge of the display.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Right cove — quarter circle centred at (maxX, minY + r), so the curve leaves
        // the top edge horizontally and joins the body's edge vertically.
        p.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                   control1: CGPoint(x: rect.maxX - k, y: rect.minY),
                   control2: CGPoint(x: rect.maxX - r, y: rect.minY + r - k))

        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r - br, y: rect.maxY),
                       control: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r + br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY - br),
                       control: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY + r))

        // Left cove, mirrored.
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                   control1: CGPoint(x: rect.minX + r, y: rect.minY + r - k),
                   control2: CGPoint(x: rect.minX + k, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

enum Format {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    /// "12,483,921"
    static func exact(_ n: Int) -> String {
        grouped.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// "12.5M" — for the headline, where precision matters less than shape.
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        switch abs(v) {
        case 1_000_000_000...: return trim(v / 1_000_000_000) + "B"
        case 1_000_000...:     return trim(v / 1_000_000) + "M"
        case 1_000...:         return trim(v / 1_000) + "K"
        default:               return "\(n)"
        }
    }

    private static func trim(_ v: Double) -> String {
        v < 10 ? String(format: "%.2f", v)
            : v < 100 ? String(format: "%.1f", v)
            : String(format: "%.0f", v)
    }

    /// "6d 4h" / "2h 14m" — for spans that can run to days.
    ///
    /// A weekly reset is up to seven days out, and `duration` counts hours without
    /// bound, so it would render that as "163h 12m". Nobody reads that as a week.
    static func longDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        guard total >= 24 * 3600 else { return duration(interval) }
        return "\(total / 86_400)d \((total % 86_400) / 3600)h"
    }

    /// "37.0%". One helper because six call sites had grown their own
    /// `String(format: "%.1f%%")`, which is the kind of thing that drifts a decimal
    /// place apart without anyone noticing.
    static func percent(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", value)
    }

    /// "2h 14m" / "48m" / "under a minute"
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        if total < 60 { return "under a minute" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static func time(_ date: Date) -> String { clock.string(from: date) }
}
