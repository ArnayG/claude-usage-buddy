import AppKit
import Combine
import SwiftUI

/// Owns the notch window and the hover state machine.
@MainActor
final class NotchController {
    private let store: UsageStore
    private var window: NotchWindow?
    private var hoverView: HoverView?
    private let state = PanelState()

    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var tick: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Short delay so sweeping the cursor past the notch does not trigger it.
    private let openDelay: TimeInterval = 0.12
    /// Grace period so a brief exit at the panel edge does not slam it shut.
    private let closeDelay: TimeInterval = 0.25

    var onCalibrate: () -> Void = {}

    init(store: UsageStore) {
        self.store = store
    }

    func install() {
        buildWindow()

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .sink { [weak self] _ in self?.repositionForScreenChange() }
        .store(in: &cancellables)

        // Keeps the countdown ticking and hides the panel when the menu bar goes
        // away in fullscreen.
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
    }

    private func buildWindow() {
        guard let (frame, _) = NotchGeometry.collapsedFrame() else { return }

        let window = NotchWindow(contentRect: frame)
        let hover = HoverView(frame: CGRect(origin: .zero, size: frame.size))
        hover.autoresizingMask = [.width, .height]

        let root = NotchRootView(state: state, store: store, onCalibrate: { [weak self] in
            self?.onCalibrate()
        })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = hover.bounds
        hosting.autoresizingMask = [.width, .height]
        hover.addSubview(hosting)

        hover.onEnter = { [weak self] in self?.scheduleExpand() }
        hover.onExit = { [weak self] in self?.scheduleCollapse() }

        window.contentView = hover
        window.orderFrontRegardless()

        self.window = window
        self.hoverView = hover
    }

    // MARK: - Hover

    private func scheduleExpand() {
        collapseWork?.cancel()
        collapseWork = nil
        guard !state.isExpanded, expandWork == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.expandWork = nil
            self?.expand()
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + openDelay, execute: work)
    }

    private func scheduleCollapse() {
        expandWork?.cancel()
        expandWork = nil
        guard state.isExpanded, collapseWork == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            self?.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: work)
    }

    private func expand() {
        guard let window, let (collapsed, screen) = NotchGeometry.collapsedFrame() else { return }
        guard !NotchGeometry.menuBarHidden(on: screen) else { return }

        // Fresh numbers the moment the panel opens — this is the interaction that
        // matters, so it should never show a stale count.
        store.refresh()

        state.isExpanded = true
        let target = NotchGeometry.expandedFrame(for: collapsed, on: screen)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            window.animator().setFrame(target, display: true)
        }
    }

    private func collapse() {
        guard let window, let (collapsed, _) = NotchGeometry.collapsedFrame() else { return }
        state.isExpanded = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(collapsed, display: true)
        }
    }

    // MARK: - Screen changes

    private func onTick() {
        state.now = Date()

        guard let window, let (collapsed, screen) = NotchGeometry.collapsedFrame() else { return }

        // Fullscreen hides the menu bar and covers the notch; get out of the way.
        if NotchGeometry.menuBarHidden(on: screen) {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        if !window.isVisible {
            window.setFrame(collapsed, display: false)
            state.isExpanded = false
            window.orderFrontRegardless()
        }
    }

    private func repositionForScreenChange() {
        guard let window, let (collapsed, _) = NotchGeometry.collapsedFrame() else { return }
        expandWork?.cancel(); expandWork = nil
        collapseWork?.cancel(); collapseWork = nil
        state.isExpanded = false
        window.setFrame(collapsed, display: true)
    }
}

/// Observable bridge between AppKit hover events and the SwiftUI tree.
@MainActor
final class PanelState: ObservableObject {
    @Published var isExpanded = false
    /// Drives the live countdown without the views owning a timer each.
    @Published var now = Date()
}

private struct NotchRootView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var store: UsageStore
    var onCalibrate: () -> Void

    var body: some View {
        Group {
            if state.isExpanded {
                ExpandedView(snapshot: store.snapshot,
                             serverNote: store.serverNote,
                             now: state.now,
                             onCalibrate: onCalibrate)
                    .transition(.opacity)
            } else {
                CollapsedView(fraction: store.snapshot.fraction,
                              showGauge: Settings.showHairlineGauge)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.isExpanded)
    }
}
