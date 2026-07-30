// Generates Resources/AppIcon.icns from the same sprite the app draws.
//
// Reusing BuddyMood keeps one source of truth: change the creature and the icon
// follows. Run via `make icon`.
import AppKit
import SwiftUI

@main
struct IconGenerator {

// Trim the blank head-room rows so the creature is optically centred.
static let fullRows = Array(BuddyMood.chipper.grid.drop { !$0.contains("X") })

/// A simplified creature for small icons.
///
/// The full sprite is 16 cells wide, which at the 16pt slot Finder's list view uses
/// works out below one pixel per cell — it quantised to nothing and the icon rendered
/// as a plain black square, the very blankness this was meant to fix. Seven columns
/// give a full 2px per cell at 16pt and 4px at 32pt.
static let microRows = [
    ".XXXXX.",
    ".X.X.X.",
    "XXXXXXX",
    ".XXXXX.",
    "..X.X..",
]

static func art(for size: Int) -> [String] {
    // Small slots use the 7-wide glyph: its cells land on whole pixels at both 16
    // and 32, where the full 16-wide sprite cannot.
    size <= 40 ? microRows : fullRows
}

/// Small icons need proportionally bigger, bolder artwork to stay legible.
static func layout(for size: Int) -> (inset: CGFloat, share: CGFloat) {
    switch size {
    // Shares are picked so `target / cols` lands on a whole number of pixels at
    // each slot; otherwise rounding either overflows the plate or halves the art.
    case ...16:  return (26.0 / 1024, 0.95)   // plate 15.2 -> 2px cells, art 14px
    case ...32:  return (32.0 / 1024, 0.95)   // plate 30   -> 4px cells, art 28px
    case ...64:  return (76.0 / 1024, 0.80)
    case ...128: return (88.0 / 1024, 0.70)
    default:     return (100.0 / 1024, 0.62)
    }
}

// Apple's macOS grid: an 824pt rounded square inside a 1024pt canvas.
static func render(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)

    let rows = art(for: size)
    let cols = rows.map(\.count).max() ?? 16
    let (insetRatio, share) = layout(for: size)
    let inset = s * insetRatio
    let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * (185.0 / 1024.0)
    let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Near-black plate with a touch of lift at the top, so it reads as an object
    // rather than a hole at small sizes.
    ctx.saveGState()
    ctx.addPath(platePath); ctx.clip()
    let colours = [CGColor(red: 0.13, green: 0.12, blue: 0.12, alpha: 1),
                   CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: plate.maxY),
                           end: CGPoint(x: 0, y: plate.minY), options: [])
    ctx.restoreGState()

    // Hairline rim, the way system icons catch light along the top edge.
    ctx.addPath(platePath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
    ctx.setLineWidth(max(1, s / 512))
    ctx.strokePath()

    // Pixel-snap the cell so edges stay crisp, but never let it round to zero.
    let target = plate.width * share
    let cell = max(1, (target / CGFloat(cols)).rounded())
    let artW = cell * CGFloat(cols), artH = cell * CGFloat(rows.count)
    let originX = (s - artW) / 2
    let originY = (s - artH) / 2
    ctx.setFillColor(CGColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1))  // #D97757
    for (r, row) in rows.enumerated() {
        for (c, ch) in row.enumerated() where ch == "X" {
            // Row 0 is the top of the sprite; CoreGraphics y grows upward.
            let y = originY + CGFloat(rows.count - 1 - r) * cell
            ctx.fill(CGRect(x: originX + CGFloat(c) * cell, y: y, width: cell, height: cell))
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

static let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
static func main() {
    let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
    let set = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for (px, name) in variants {
        guard let data = render(size: px).representation(using: .png, properties: [:]) else { continue }
        try? data.write(to: set.appendingPathComponent(name))
    }
    print("wrote \(variants.count) variants to \(set.path)")
}
}
