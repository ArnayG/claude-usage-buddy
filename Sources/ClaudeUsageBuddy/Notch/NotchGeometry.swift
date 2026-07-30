import AppKit

/// Locates the camera notch without hardcoding any model-specific numbers.
///
/// On a 14" MacBook Pro this resolves to roughly 185 x 32 pt centred at the top of
/// the built-in display, but it is derived at runtime so external monitors, docking,
/// and non-notched Macs all behave correctly.
enum NotchGeometry {
    /// Size of the panel once expanded.
    ///
    /// 440pt of body, plus `Theme.coveRadius` either side: the top corners sweep
    /// outward past the body to meet the edge of the display, so the frame is wider
    /// than the panel looks. See `NotchPanelShape`.
    ///
    /// Height as an explicit sum of what has to fit, so the cost of each band stays
    /// visible instead of being buried in one magic number.
    ///
    /// This reached 431pt when the three detail sections were stacked — 44% of a 982pt
    /// display, far too much to hand a hover. Rotating them through a single tabbed
    /// area, and shrinking the gauge, the buddy and the type, brings it back close to
    /// what it was before any of them existed.
    static let expandedHeight: CGFloat =
        32         // the cutout itself; content has to clear it
        + 60       // header: gauge, token count, reset, buddy
        + 33       // tab strip
        + 8        // divider
        + 66       // detail area, sized for the tallest of the three
        + 24       // footer
        + 12       // bottom padding

    static let expandedSize = CGSize(width: 440 + 2 * Theme.coveRadius, height: expandedHeight)

    /// The always-visible creature, sitting in the menu bar strip to the right of
    /// the camera. 32×22 renders the trimmed sprite at exactly 2pt per cell.
    static let peekSize = CGSize(width: 32, height: 22)

    /// Gap between the cutout's right edge and the buddy.
    static let peekGap: CGFloat = 6

    /// Sits the buddy in the menu bar, just right of the camera cutout.
    ///
    /// It used to hang below the notch, which put it in the content area where it got
    /// in the way of real work. The menu bar strip beside the cutout is dead space on
    /// most setups — status items pack in from the right edge, so the points next to
    /// the notch are the last to be claimed.
    static func peekFrame(for collapsed: CGRect) -> CGRect {
        // `collapsed` extends below the cutout for the hairline gauge; the cutout
        // itself is the part sitting in the menu bar.
        let cutoutHeight = collapsed.height - gaugeOverhang
        let menuBarMidY = collapsed.maxY - cutoutHeight / 2
        return CGRect(x: (collapsed.maxX + peekGap).rounded(),
                      y: (menuBarMidY - peekSize.height / 2).rounded(),
                      width: peekSize.width,
                      height: peekSize.height)
    }

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
