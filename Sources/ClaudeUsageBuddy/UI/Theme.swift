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
    /// Where the panel's sides meet the top edge of the display, mirroring the
    /// cutout's own fillet.
    static let topCornerRadius: CGFloat = 7
}

/// The expanded panel's silhouette.
///
/// The bottom corners carry the big "dynamic island" curve. The top corners are
/// rounded too, just far less: on a MacBook the cutout curves gently where its
/// vertical edges meet the top edge of the display, so a hard 90° corner there reads
/// as obviously synthetic sitting next to the real thing.
struct NotchPanelShape: Shape {
    var topRadius: CGFloat = Theme.topCornerRadius
    var bottomRadius: CGFloat = Theme.cornerRadius

    func path(in rect: CGRect) -> Path {
        let halfMin = min(rect.width, rect.height) / 2
        let tr = min(topRadius, halfMin)
        let br = min(bottomRadius, halfMin)

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - br),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
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
