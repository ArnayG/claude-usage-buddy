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

        Settings.removeLegacyKeys()

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
        print("Claude Usage Buddy")
        print("  claude CLI     : \(UsageProbe.locateCLI()?.path ?? "NOT FOUND")")

        var percent: Double?
        var resetAt: Date?
        var windowStart: Date?
        do {
            let probe = try UsageProbe.run()
            percent = probe.percent
            resetAt = probe.resetAt
            windowStart = probe.resetAt?.addingTimeInterval(-UsageBlock.windowLength)
            print("  /usage         : ok")
        } catch {
            print("  /usage         : FAILED — \(error)")
        }

        let entries = TranscriptScanner().scan()
        let now = Date()
        // Fall back to the locally inferred window only if the probe failed.
        let start = windowStart ?? UsageBlock.current(from: entries, now: now)?.start
        var counts = TokenCounts()
        if let start {
            for e in entries where e.timestamp >= start { counts += e.counts }
        }
        let weekly = UsageBlock.trailingWeek(from: entries, now: now)

        print("""
          entries parsed : \(entries.count)
          tokens used    : \(Format.exact(counts.total))
            input        : \(Format.exact(counts.input))
            output       : \(Format.exact(counts.output))
            cache write  : \(Format.exact(counts.cacheCreation))
            cache read   : \(Format.exact(counts.cacheRead))
          session used   : \(percent.map { String(format: "%.1f%%", $0) } ?? "unknown")
          window start   : \(start.map(Format.time) ?? "—")\(windowStart == nil ? " (inferred locally)" : "")
          resets at      : \(resetAt.map(Format.time) ?? "—")
          resets in      : \(resetAt.map { Format.duration(max($0.timeIntervalSince(now), 0)) } ?? "—")
          last 7 days    : \(Format.exact(weekly.total))
        """)
        exit(0)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private lazy var notch = NotchController(store: store)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()

        notch.onRefresh = { [weak self] in self?.store.forceRefresh() }
        notch.install()

        installStatusItem()

        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusTitle() }
            .store(in: &cancellables)
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
        statusItem?.button?.title = s.isUnverified ? " —" : String(format: " %.0f%%", s.percent)
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let s = store.snapshot
        let menu = NSMenu()

        menu.addItem(disabled("Tokens used: \(Format.exact(s.used))"))
        if s.isUnverified {
            menu.addItem(disabled("Session used: reading /usage…"))
        } else {
            menu.addItem(disabled(String(format: "Session used: %.1f%%", s.percent)))
        }
        if let reset = s.resetAt {
            menu.addItem(disabled("Resets \(Format.time(reset)) · in \(Format.duration(max(reset.timeIntervalSinceNow, 0)))"))
        } else {
            menu.addItem(disabled("No active session window"))
        }
        if let error = s.probeError {
            menu.addItem(disabled("⚠ /usage: \(error)"))
        }
        menu.addItem(.separator())
        menu.addItem(disabled("Last 7 days: \(Format.exact(store.weekly.total)) tokens"))
        menu.addItem(.separator())

        menu.addItem(action("Refresh now", #selector(refreshNow)))
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

    @objc private func refreshNow() { store.forceRefresh() }
    @objc private func openSettingsMenu() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Settings

    /// `NSWindow.center()` uses the main screen, which on a multi-display setup can
    /// put the window on an external monitor — away from the notch the app lives in.
    private static func centreOnNotchedScreen(_ window: NSWindow) {
        guard let screen = NotchGeometry.notchedScreen() ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2 + visible.height * 0.08).rounded()
        ))
    }

    private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage Buddy"
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.isReleasedWhenClosed = false
        Self.centreOnNotchedScreen(window)
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
