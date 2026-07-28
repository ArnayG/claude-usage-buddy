import AppKit

/// Locates the camera notch without hardcoding any model-specific numbers.
///
/// On a 14" MacBook Pro this resolves to roughly 185 x 32 pt centred at the top of
/// the built-in display, but it is derived at runtime so external monitors, docking,
/// and non-notched Macs all behave correctly.
enum NotchGeometry {
    /// Size of the panel once expanded.
    static let expandedSize = CGSize(width: 420, height: 214)

    /// Used when a Mac has no notch but we still want the panel to drop from the
    /// top edge (external display fallback, or a notch-less MacBook).
    static let syntheticNotch = CGSize(width: 185, height: 24)

    /// The notch is a physical cutout — there are no pixels behind it, so anything
    /// drawn inside its rect is invisible. The collapsed window therefore hangs a
    /// few points below the cutout so the ambient gauge lands on real pixels.
    static let gaugeOverhang: CGFloat = 4

    static func notchRect(on screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX
        else { return nil }

        return CGRect(x: left.maxX,
                      y: left.minY,
                      width: right.minX - left.maxX,
                      height: left.height)
    }

    /// The screen that physically has a notch, if any.
    static func notchedScreen() -> NSScreen? {
        NSScreen.screens.first { notchRect(on: $0) != nil }
    }

    /// Where the collapsed hover target lives. Falls back to a synthetic strip at
    /// the top-centre of the main screen when there is no notch.
    static func collapsedFrame() -> (frame: CGRect, screen: NSScreen)? {
        let base: CGRect
        let screen: NSScreen

        if let notched = notchedScreen(), let rect = notchRect(on: notched) {
            screen = notched
            base = rect
        } else if let main = NSScreen.main {
            screen = main
            let f = main.frame
            base = CGRect(x: f.midX - syntheticNotch.width / 2,
                          y: f.maxY - syntheticNotch.height,
                          width: syntheticNotch.width,
                          height: syntheticNotch.height)
        } else {
            return nil
        }

        // Grow downward past the cutout so the gauge is actually on screen.
        let frame = CGRect(x: base.minX,
                           y: base.minY - gaugeOverhang,
                           width: base.width,
                           height: base.height + gaugeOverhang)
        return (frame, screen)
    }

    /// Expanded panel, hung from the top edge and centred on the notch.
    static func expandedFrame(for collapsed: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(x: (collapsed.midX - expandedSize.width / 2).rounded(),
               y: screen.frame.maxY - expandedSize.height,
               width: expandedSize.width,
               height: expandedSize.height)
    }

    /// True when the menu bar is hidden — native fullscreen, mostly — in which case
    /// the notch is covered and the panel must get out of the way.
    static func menuBarHidden(on screen: NSScreen) -> Bool {
        screen.visibleFrame.maxY >= screen.frame.maxY - 1
    }
}
