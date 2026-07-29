import AppKit
import SwiftUI

/// The little creature that stays visible below the notch when the panel is collapsed.
///
/// Deliberately a **separate window** from `NotchWindow`. The obvious alternative —
/// growing the collapsed window's overhang so the buddy has room — would leave a
/// 185 × 20pt strip permanently swallowing clicks directly under the menu bar, right
/// where a maximised window's toolbar sits. This window sets `ignoresMouseEvents`, so
/// it is purely decorative and intercepts nothing at all.
final class PeekWindow: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false

        // Never takes a click, never takes focus.
        ignoresMouseEvents = true

        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
