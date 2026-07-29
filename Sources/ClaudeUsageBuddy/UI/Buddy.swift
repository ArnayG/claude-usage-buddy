import SwiftUI

/// The pixel creature, rendered from hand-authored bitmap grids.
///
/// Five discrete moods rather than an interpolated morph: blending two pixel grids
/// produces mush, and pixel art reads better as distinct frames. The reference sprite
/// has no mouth, so the emotional range has to come from eye shape, arm droop, leg
/// posture and colour — which is why the X eyes are held back for the final stage.
enum BuddyMood: Int, CaseIterable {
    case chipper   // 0–20%
    case content   // 20–40%
    case worried   // 40–65%
    case sad       // 65–85%
    case dying     // 85–100%

    init(fraction: Double) {
        switch fraction {
        case ..<0.20: self = .chipper
        case ..<0.40: self = .content
        case ..<0.65: self = .worried
        case ..<0.85: self = .sad
        default:      self = .dying
        }
    }

    /// 16 wide × 14 tall. `X` is body, `.` is empty — eyes are simply absent cells, so
    /// the panel behind shows through exactly like the holes in the reference art.
    var grid: [String] {
        switch self {
        case .chipper:
            return [
                "................",
                "................",
                "................",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..XX.XXXXXX.XX..",   // ┐ eyes curve up into a happy "^"
                "XXX.X.XXXX.X.XXX",   // ┘ …and the arm tips ride a row higher
                "XXXXXXXXXXXXXXXX",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "...X.X....X.X...",
                "...X.X....X.X...",
            ]
        case .content:
            return [
                "................",
                "................",
                "................",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..XX.XXXXXX.XX..",
                "..XX.XXXXXX.XX..",
                "XXXXXXXXXXXXXXXX",
                "XXXXXXXXXXXXXXXX",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "...X.X....X.X...",
                "...X.X....X.X...",
            ]
        case .worried:
            return [
                "................",
                "................",
                "................",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..XX..XXXX..XX..",   // eyes flatten into a wary squint
                "..XXXXXXXXXXXX..",
                "XXXXXXXXXXXXXXXX",
                "XXXXXXXXXXXXXXXX",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "...X.X....X.X...",
                "...X.X....X.X...",
            ]
        case .sad:
            return [
                "................",
                "................",
                "................",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "..X.X.XXXX.X.X..",   // ┐ eyes invert into a downcast "v"
                "..XX.XXXXXX.XX..",   // ┘
                ".XXXXXXXXXXXXXX.",   // arms sagging outward and down
                "XXXXXXXXXXXXXXXX",
                "..XXXXXXXXXXXX..",
                "..XXXXXXXXXXXX..",
                "...X.X....X.X...",
                "...X.X....X.X...",
            ]
        case .dying:
            return [
                "................",
                "................",
                "................",
                "................",
                "..XXXXXXXXXXXX..",   // body squats, losing its top row
                "..X.X.XXXX.X.X..",   // ┐
                "..XX.XXXXXX.XX..",   // ├ X-shaped eyes
                "..X.X.XXXX.X.X..",   // ┘
                "..XXXXXXXXXXXX..",
                "XX.XXXXXXXXXX.XX",   // arms hanging limp at the sides
                "XX.XXXXXXXXXX.XX",
                "..XXXXXXXXXXXX..",
                "..X..X....X..X..",   // legs splayed
                ".X....X..X....X.",
            ]
        }
    }

    /// Eyes shut. Produced by filling every hole strictly inside a row's outermost
    /// body cells, so it works for any mood without a second set of hand-authored art.
    var blinkGrid: [String] {
        guard self != .dying else { return grid }   // the dying don't blink
        return grid.map { row in
            let chars = Array(row)
            guard let first = chars.firstIndex(of: "X"),
                  let last = chars.lastIndex(of: "X"), first < last else { return row }
            return String(chars.enumerated().map { i, c in
                (i > first && i < last && c == ".") ? "X" : c
            })
        }
    }
}

/// The creature stays clay and gets *sick* rather than shifting hue.
///
/// Tinting it green at 0% would throw away the character's identity — the ring beside
/// it already carries the green→amber→red signal, so this ramp only has to read as
/// "the life is draining out of it".
enum BuddyPalette {
    static let healthy = Color(red: 0.851, green: 0.467, blue: 0.341)  // #D97757
    static let dull    = Color(red: 0.773, green: 0.416, blue: 0.298)  // #C56A4C
    static let ill     = Color(red: 0.651, green: 0.380, blue: 0.322)  // #A66152
    static let ashen   = Color(red: 0.549, green: 0.357, blue: 0.341)  // #8C5B57

    static func colour(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.40: return healthy
        case ..<0.70: return dull
        case ..<0.90: return ill
        default:      return ashen
        }
    }
}

struct BuddyView: View {
    let fraction: Double
    /// Idle life costs a repaint timer, so it is opt-in: on in the hover panel, off
    /// for the always-on-screen notch peek.
    var animated: Bool = true
    /// Drops the empty rows above the head, for tight spaces like the peek.
    var trimTop: Bool = false

    @Environment(\.displayScale) private var displayScale

    private var mood: BuddyMood { BuddyMood(fraction: fraction) }

    var body: some View {
        Group {
            if animated {
                // 12Hz is plenty for a bob and a blink, and far cheaper than the
                // display-linked .animation schedule.
                TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { ctx in
                    canvas(at: ctx.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(at: 0)
            }
        }
        .animation(.spring(duration: 0.28), value: mood)
    }

    private func canvas(at time: TimeInterval) -> some View {
        let blinking = animated && isBlinking(at: time)
        var rows = blinking ? mood.blinkGrid : mood.grid
        if trimTop {
            rows = Array(rows.drop { !$0.contains("X") })
        }
        let bob = animated ? bobOffset(at: time) : 0
        let colour = BuddyPalette.colour(for: fraction)

        return Canvas { ctx, size in
            let cols = rows.map(\.count).max() ?? 16
            let unit = min(size.width / CGFloat(cols), size.height / CGFloat(rows.count))
            let originX = (size.width - unit * CGFloat(cols)) / 2
            let originY = (size.height - unit * CGFloat(rows.count)) / 2 + bob

            // Snap to whole device pixels. Rounding each edge independently — rather
            // than rounding origin and size separately — is what keeps adjacent cells
            // seamless instead of leaving hairline gaps between them.
            func snap(_ v: CGFloat) -> CGFloat { (v * displayScale).rounded() / displayScale }

            for (r, row) in rows.enumerated() {
                for (c, char) in row.enumerated() where char == "X" {
                    let x0 = snap(originX + CGFloat(c) * unit)
                    let x1 = snap(originX + CGFloat(c + 1) * unit)
                    let y0 = snap(originY + CGFloat(r) * unit)
                    let y1 = snap(originY + CGFloat(r + 1) * unit)
                    ctx.fill(
                        Path(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)),
                        with: .color(colour)
                    )
                }
            }
        }
    }

    /// Roughly every five seconds, for two frames.
    private func isBlinking(at time: TimeInterval) -> Bool {
        guard mood != .dying else { return false }
        return time.truncatingRemainder(dividingBy: 5.2) < 0.17
    }

    private func bobOffset(at time: TimeInterval) -> CGFloat {
        switch mood {
        case .chipper, .content:
            return sin(time * 1.9) * 1.0
        case .worried:
            return sin(time * 1.2) * 0.5
        case .sad:
            return 0
        case .dying:
            // An irregular, laboured shudder rather than a clean oscillation.
            return (sin(time * 9.1) + sin(time * 14.3)) * 0.35
        }
    }
}
