import AppKit
import SwiftUI

/// The little creature that sits in the menu bar beside the camera when the panel
/// is collapsed.
///
/// Deliberately a **separate window** from `NotchWindow`, so it can be positioned
/// independently of the hover target and sized to nothing more than the sprite.
///
/// It lives in the menu bar rather than below the notch: hanging into the content
/// area put it on top of real work. The buddy is pokeable, so this window does take
/// mouse events — at 32 × 22pt in a strip that is dead space on most setups.
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
