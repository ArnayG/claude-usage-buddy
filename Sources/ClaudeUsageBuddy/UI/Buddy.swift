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
    /// The ramp, as one list.
    ///
    /// An earlier version also declared `healthy` / `dull` / `ill` / `ashen` with the
    /// same components spelled out again, which is two places to change and no check
    /// that they agree. Nothing referenced them, so they are gone; the hex comments
    /// carry the documentation they were providing.
    private static let stops: [(at: Double, r: Double, g: Double, b: Double)] = [
        (0.00, 0.851, 0.467, 0.341),   // #D97757  healthy clay
        (0.55, 0.773, 0.416, 0.298),   // #C56A4C  duller
        (0.80, 0.651, 0.380, 0.322),   // #A66152  desaturating
        (1.00, 0.549, 0.357, 0.341),   // #8C5B57  ashen
    ]

    /// Interpolated, not stepped.
    ///
    /// The five moods are wide — 40–65% is a 25-point band — so with a stepped ramp
    /// the creature can look completely frozen for hours of real use. A continuous
    /// colour means there is always some visible drift, even mid-band.
    static func colour(for fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        for i in 1..<stops.count where f <= stops[i].at {
            let lo = stops[i - 1], hi = stops[i]
            let t = hi.at == lo.at ? 0 : (f - lo.at) / (hi.at - lo.at)
            return Color(red:   lo.r + (hi.r - lo.r) * t,
                         green: lo.g + (hi.g - lo.g) * t,
                         blue:  lo.b + (hi.b - lo.b) * t)
        }
        let last = stops[stops.count - 1]
        return Color(red: last.r, green: last.g, blue: last.b)
    }
}

struct BuddyView: View {
    let fraction: Double
    /// Idle life costs a repaint timer, so it is opt-in: on in the hover panel, off
    /// for the always-on-screen notch peek.
    var animated: Bool = true
    /// Drops the empty rows above the head, for tight spaces like the peek.
    var trimTop: Bool = false
    /// Reacts to hover and clicks.
    var interactive: Bool = true

    @State private var hovering = false
    @State private var pokedAt: Date?
    @Environment(\.displayScale) private var displayScale

    private var mood: BuddyMood { BuddyMood(fraction: fraction) }

    private var reacting: Bool { interactive && (hovering || pokedAt != nil) }

    /// A poke perks it up. Even at death's door it manages a weak rally, which reads
    /// as the creature responding to you rather than the gauge having gone wrong.
    private var displayMood: BuddyMood {
        guard reacting else { return mood }
        return mood == .dying ? .sad : .chipper
    }

    /// The idle ticker is opt-in, but a reaction always needs one — otherwise the hop
    /// would never draw on the otherwise-static notch peek.
    private var needsTicker: Bool { animated || reacting }

    var body: some View {
        Group {
            if needsTicker {
                // 24Hz: smooth enough for the hop, still far cheaper than the
                // display-linked .animation schedule.
                TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { ctx in
                    canvas(at: ctx.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(at: 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            guard interactive else { return }
            hovering = inside
        }
        .onTapGesture { poke() }
        .animation(.spring(duration: 0.28), value: mood)
    }

    private func poke() {
        guard interactive else { return }
        pokedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + hopDuration + 0.1) {
            // Ignore a stale timer from an earlier poke that has been superseded.
            if let started = pokedAt, Date().timeIntervalSince(started) >= hopDuration {
                pokedAt = nil
            }
        }
    }

    private var hopDuration: TimeInterval { 0.62 }

    private func canvas(at time: TimeInterval) -> some View {
        let active = displayMood
        // A reacting buddy has its eyes open — blinking through a hop looks broken.
        let blinking = animated && !reacting && isBlinking(at: time)
        var rows = blinking ? active.blinkGrid : active.grid
        if trimTop {
            rows = Array(rows.drop { !$0.contains("X") })
        }
        let bob = (animated ? bobOffset(at: time) : 0) + reactionOffset(at: time)
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

    /// Hover lifts it slightly; a click sends it into two decaying hops.
    private func reactionOffset(at time: TimeInterval) -> CGFloat {
        guard interactive else { return 0 }

        if let started = pokedAt {
            let t = time - started.timeIntervalSinceReferenceDate
            if t >= 0 && t < hopDuration {
                let progress = t / hopDuration
                let arc = abs(sin(.pi * progress * 2))      // two hops
                let decay = 1 - progress                     // second one smaller
                return -CGFloat(arc * decay) * 8
            }
        }
        return hovering ? -2.5 : 0
    }

    /// Roughly every five seconds, for two frames.
    private func isBlinking(at time: TimeInterval) -> Bool {
        guard mood != .dying else { return false }
        return time.truncatingRemainder(dividingBy: 5.2) < 0.17
    }

    private func bobOffset(at time: TimeInterval) -> CGFloat {
        switch displayMood {
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
