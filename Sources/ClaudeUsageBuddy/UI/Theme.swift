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
    /// Size of the flare where the panel's sides meet the top edge of the display.
    ///
    /// Kept at or below the 32pt menu bar height so the curve resolves inside the
    /// menu bar strip rather than running on down into the panel body.
    static let topFlare: CGFloat = 20
}

/// The expanded panel's silhouette.
///
/// The bottom corners carry the big convex "dynamic island" curve. The top two are the
/// shoulders where the panel meets the top edge of the display: the cutout flares *out*
/// into that edge rather than rounding off, so black is added in the corner, not taken
/// away.
///
/// Each shoulder is an **ogee** — two quarter circles of radius `flare / 2`, one concave
/// then one convex — not a single quarter circle.
///
/// That matters, and it is the third attempt at this corner. A single quarter arc is
/// *tangent* to the top edge, so the boundary runs almost horizontally where it meets
/// it: measured at a 20pt flare, it moves 6.2pt inward within the first 1pt of descent
/// and 1.4pt within the first 0.05pt. Geometrically it is a perfect arc; visually the
/// black ends in a razor-thin wedge, which is what read as a sharp corner. (Before that
/// it was an `addQuadCurve`, which cannot describe a circular arc at all — 6.1% off the
/// radius, biased toward the top edge.)
///
/// The ogee is **vertical at both ends**: perpendicular to the top edge, so there is no
/// wedge and the display edge simply cuts it off cleanly, and parallel to the body's
/// side edge where it lands, so there is no corner there either. Curvature flips sign at
/// the midpoint, which is what makes it read as a smooth shoulder rather than a bite.
///
/// The body sits inset by `flare` on each side and only reaches full width at the very
/// top edge.
struct NotchPanelShape: Shape {
    var flare: CGFloat = Theme.topFlare
    var bottomRadius: CGFloat = Theme.cornerRadius

    /// Control-point offset that turns a cubic into a quarter circle: 4(√2−1)/3.
    /// Standard result — the value that puts the curve's midpoint exactly on the arc.
    private static let circleK: CGFloat = 4 * (sqrt(2) - 1) / 3

    func path(in rect: CGRect) -> Path {
        let f = min(flare, rect.width / 2)
        let br = min(bottomRadius, min(rect.width / 2 - f, rect.height / 2))
        let h = f / 2                       // radius of each half of the shoulder
        let kh = h * Self.circleK
        let kb = br * Self.circleK

        var p = Path()

        // Full width along the very top edge of the display.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Right shoulder. Concave half: leaves the top edge straight down, arrives at
        // the inflection running horizontally.
        p.addCurve(to: CGPoint(x: rect.maxX - h, y: rect.minY + h),
                   control1: CGPoint(x: rect.maxX, y: rect.minY + kh),
                   control2: CGPoint(x: rect.maxX - h + kh, y: rect.minY + h))
        // Convex half: leaves the inflection horizontally, lands on the body edge
        // running straight down.
        p.addCurve(to: CGPoint(x: rect.maxX - f, y: rect.minY + f),
                   control1: CGPoint(x: rect.maxX - h - kh, y: rect.minY + h),
                   control2: CGPoint(x: rect.maxX - f, y: rect.minY + f - kh))

        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.maxY - br))

        // Convex round, bottom-right.
        p.addCurve(to: CGPoint(x: rect.maxX - f - br, y: rect.maxY),
                   control1: CGPoint(x: rect.maxX - f, y: rect.maxY - br + kb),
                   control2: CGPoint(x: rect.maxX - f - br + kb, y: rect.maxY))

        p.addLine(to: CGPoint(x: rect.minX + f + br, y: rect.maxY))

        // Convex round, bottom-left.
        p.addCurve(to: CGPoint(x: rect.minX + f, y: rect.maxY - br),
                   control1: CGPoint(x: rect.minX + f + br - kb, y: rect.maxY),
                   control2: CGPoint(x: rect.minX + f, y: rect.maxY - br + kb))

        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.minY + f))

        // Left shoulder, mirrored — and traversed upward, so both control points are
        // the mirror of the right shoulder's *reversed*. Getting one of them on the
        // wrong side of the inflection puts a visible hook in the curve.
        p.addCurve(to: CGPoint(x: rect.minX + h, y: rect.minY + h),
                   control1: CGPoint(x: rect.minX + f, y: rect.minY + f - kh),
                   control2: CGPoint(x: rect.minX + h + kh, y: rect.minY + h))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                   control1: CGPoint(x: rect.minX + h - kh, y: rect.minY + h),
                   control2: CGPoint(x: rect.minX, y: rect.minY + kh))

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
