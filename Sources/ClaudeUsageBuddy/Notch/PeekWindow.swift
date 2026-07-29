import AppKit
import SwiftUI

/// The little creature that stays visible below the notch when the panel is collapsed.
///
/// Deliberately a **separate window** from `NotchWindow`. The obvious alternative —
/// growing the collapsed window's overhang so the buddy has room — would leave a
/// 185 × 20pt strip permanently swallowing clicks directly under the menu bar, right
/// where a maximised window's toolbar sits.
///
/// The buddy is pokeable, so this window does take mouse events — but at 24 × 17pt
/// that is a thumbnail-sized target rather than a bar across the whole notch, which
/// is the entire reason for keeping it in its own window.
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

        // Takes hover and clicks so the buddy can react, but never focus — poking it
        // must not pull you out of whatever you are typing in.
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true

        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
