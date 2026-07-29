import AppKit
import Combine
import SwiftUI

@main
enum Main {
    // Held statically because NSApplication does not retain its delegate.
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--print-usage") {
            printUsageAndExit()
        }
        if CommandLine.arguments.contains("--enable-login-item") {
            let ok = LoginItem.set(true)
            print(ok ? "Launch at login: enabled (\(LoginItem.isEnabled ? "confirmed" : "pending approval"))"
                     : "Launch at login: failed — move the app to /Applications first")
            exit(ok ? 0 : 1)
        }
        if CommandLine.arguments.contains("--disable-login-item") {
            _ = LoginItem.set(false)
            print("Launch at login: disabled")
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Headless readout of exactly what the notch would show.
    @MainActor
    private static func printUsageAndExit() -> Never {
        let scanner = TranscriptScanner()
        let entries = scanner.scan()
        let now = Date()
        let block = UsageBlock.current(from: entries, now: now)

        var snapshot = UsageSnapshot.empty
        snapshot.counts = block?.counts ?? TokenCounts()
        snapshot.allowance = Settings.allowance
        snapshot.blockStart = block?.start
        snapshot.resetAt = block?.end
        snapshot.resetSource = block == nil ? .unknown : .inferred
        if let pinned = Settings.overrideResetAt {
            snapshot.resetAt = pinned
            snapshot.blockStart = pinned.addingTimeInterval(-UsageBlock.windowLength)
            snapshot.resetSource = .pinned
        }

        let weekly = UsageBlock.trailingWeek(from: entries, now: now)
        let samples = Settings.calibrationSamples

        print("""
        Claude Usage Buddy
          entries parsed : \(entries.count)
          tokens used    : \(Format.exact(snapshot.used))
            input        : \(Format.exact(snapshot.counts.input))
            output       : \(Format.exact(snapshot.counts.output))
            cache write  : \(Format.exact(snapshot.counts.cacheCreation))
            cache read   : \(Format.exact(snapshot.counts.cacheRead))
          allowance      : \(Format.exact(snapshot.allowance))\(samples > 0 ? " (calibrated, \(samples) reading\(samples == 1 ? "" : "s"))" : " (placeholder — not calibrated)")
          used           : \(String(format: "%.2f", snapshot.percent))%
          window start   : \(snapshot.blockStart.map(Format.time) ?? "—")
          resets at      : \(snapshot.resetAt.map(Format.time) ?? "—") (\(resetLabel(snapshot.resetSource)))
          resets in      : \(snapshot.resetAt.map { Format.duration(max($0.timeIntervalSince(now), 0)) } ?? "—")
          last 7 days    : \(Format.exact(weekly.total))
        """)
        exit(0)
    }

    private static func resetLabel(_ source: ResetSource) -> String {
        switch source {
        case .pinned: return "pinned from /usage"
        case .inferred: return "inferred from transcripts, approximate"
        case .unknown: return "no active window"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private lazy var notch = NotchController(store: store)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var calibrationWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()

        notch.onCalibrate = { [weak self] in self?.openCalibration() }
        notch.install()

        installStatusItem()

        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusTitle() }
            .store(in: &cancellables)

        // First launch: ask for the one number that makes everything else exact.
        // Delayed so the notch is on screen first and the prompt has context.
        if !Settings.hasCalibrated && !Settings.promptedForCalibration {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.openCalibration()
            }
        }
    }

    // MARK: - Status item
    //
    // The fallback surface on Macs with no notch, and the keyboard-reachable path,
    // which a hover-only UI would not be.

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.with.needle",
                                     accessibilityDescription: "Claude usage")
        item.button?.imagePosition = .imageLeading
        item.menu = buildMenu()
        statusItem = item
        refreshStatusTitle()
    }

    private func refreshStatusTitle() {
        let s = store.snapshot
        statusItem?.button?.title = String(format: " %.0f%%", s.percent)
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let s = store.snapshot
        let menu = NSMenu()

        menu.addItem(disabled("Tokens used: \(Format.exact(s.used))"))
        menu.addItem(disabled("Allowance: \(Format.exact(s.allowance))\(s.isEstimated ? " (not calibrated)" : "")"))
        menu.addItem(disabled(String(format: "Session used: %.1f%%", s.percent)))
        if let reset = s.resetAt {
            let approx = s.resetSource == .inferred ? " approx." : ""
            menu.addItem(disabled("Resets \(Format.time(reset))\(approx) · in \(Format.duration(max(reset.timeIntervalSinceNow, 0)))"))
        } else {
            menu.addItem(disabled("No active session window"))
        }
        menu.addItem(.separator())
        menu.addItem(disabled("Last 7 days: \(Format.exact(store.weekly.total)) tokens"))
        menu.addItem(.separator())

        menu.addItem(action("Refresh", #selector(refreshNow)))
        menu.addItem(action(s.isEstimated ? "Calibrate…" : "Recalibrate…", #selector(openCalibrationMenu)))
        menu.addItem(action("Settings…", #selector(openSettingsMenu), key: ","))
        menu.addItem(.separator())
        menu.addItem(action("Quit", #selector(quit), key: "q"))
        return menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refreshNow() { store.refresh() }
    @objc private func openSettingsMenu() { openSettings() }
    @objc private func openCalibrationMenu() { openCalibration() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Windows

    /// `NSWindow.center()` uses the main screen, which on a multi-display setup can
    /// put the window on an external monitor — away from the notch the app lives in,
    /// where it is easy to miss entirely.
    fileprivate static func centerOnNotchedScreen(_ window: NSWindow) {
        guard let screen = NotchGeometry.notchedScreen() ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(
            x: (visible.midX - size.width / 2).rounded(),
            // Slightly above centre reads better and stays clear of the Dock.
            y: (visible.midY - size.height / 2 + visible.height * 0.08).rounded()
        ))
    }

    private func openCalibration() {
        if let calibrationWindow {
            calibrationWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Calibrate"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CalibrationPrompt(store: store) { [weak self] in
            self?.calibrationWindow?.close()
            self?.calibrationWindow = nil
            self?.refreshStatusTitle()
        })
        Self.centerOnNotchedScreen(window)
        calibrationWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage Buddy"
        window.contentView = NSHostingView(rootView: SettingsView(store: store) { [weak self] in
            self?.openCalibration()
        })
        window.isReleasedWhenClosed = false
        Self.centerOnNotchedScreen(window)
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
