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

    static let cornerRadius: CGFloat = 22
    /// Size of the flare where the panel's sides meet the top edge of the display.
    ///
    /// Kept at or below the 32pt menu bar height so the curve resolves inside the
    /// menu bar strip rather than running on down into the panel body.
    static let topFlare: CGFloat = 20
}

/// The expanded panel's silhouette.
///
/// The bottom corners carry the big convex "dynamic island" curve. The top corners
/// are the opposite: the MacBook's cutout does not round *off* where its vertical
/// edges reach the top edge of the display, it flares *out* into it — black is added
/// in that corner, not taken away, so the boundary is concave. Rounding the corner
/// off instead (which is what this shape did at first) narrows the panel exactly
/// where the hardware widens it, and reads as backwards next to the real thing.
///
/// The body therefore sits inset by `topFlare` on each side and only reaches the
/// full width at the very top edge.
struct NotchPanelShape: Shape {
    var flare: CGFloat = Theme.topFlare
    var bottomRadius: CGFloat = Theme.cornerRadius

    func path(in rect: CGRect) -> Path {
        let f = min(flare, rect.width / 2)
        let br = min(bottomRadius, min(rect.width / 2 - f, rect.height / 2))

        var p = Path()
        // Full width along the very top edge of the display.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Concave flare inward: control at the *inner* corner puts the centre of
        // curvature outside the fill, which is what makes it cove rather than round.
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.minY + f),
                       control: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f - br, y: rect.maxY),
                       control: CGPoint(x: rect.maxX - f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + f + br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.maxY - br),
                       control: CGPoint(x: rect.minX + f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                       control: CGPoint(x: rect.minX + f, y: rect.minY))
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
