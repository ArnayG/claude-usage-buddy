import AppKit
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
        var weeklyLimit = UsageProbe.Weekly()
        do {
            let probe = try UsageProbe.run()
            percent = probe.percent
            resetAt = probe.resetAt
            weeklyLimit = probe.weekly
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
        let byModel = ModelUsage.split(entries, since: start)

        print("""
          entries parsed : \(entries.count)
          new tokens     : \(Format.exact(counts.fresh))   <- headline
            input        : \(Format.exact(counts.input))
            output       : \(Format.exact(counts.output))
            cache write  : \(Format.exact(counts.cacheCreation))
          cached re-read : \(Format.exact(counts.cacheRead))   (excluded)
          raw total      : \(Format.exact(counts.total))
          session used   : \(percent.map { String(format: "%.1f%%", $0) } ?? "unknown")
          window start   : \(start.map(Format.time) ?? "—")\(windowStart == nil ? " (inferred locally)" : "")
          resets at      : \(resetAt.map(Format.time) ?? "—")
          resets in      : \(resetAt.map { Format.duration(max($0.timeIntervalSince(now), 0)) } ?? "—")
          last 7 days    : \(Format.exact(weekly.fresh)) new  (\(Format.exact(weekly.total)) raw)
            requests     : \(weeklyLimit.requests.map(Format.exact) ?? "not reported")
            sessions     : \(weeklyLimit.sessions.map(Format.exact) ?? "not reported")
          week used      : \(weeklyPercentLine(weeklyLimit))
          week resets in : \(weeklyLimit.resetAt.map { Format.longDuration(max($0.timeIntervalSince(now), 0)) } ?? "—")
        """)

        // Shares of new tokens observed locally — deliberately not shares of the limit,
        // which /usage does not break down and which cannot be derived from these.
        print("  by model       : \(byModel.isEmpty ? "no tokens in window" : "")")
        for model in byModel {
            let name = model.name.padding(toLength: 10, withPad: " ", startingAt: 0)
            let share = String(format: "%6.2f%%", model.share(of: counts.fresh) * 100)
            print("    \(name) \(Format.exact(model.used)) new  \(share) of new")
        }
        exit(0)
    }

    /// Spells out the absence rather than printing a dash, because "no weekly
    /// percentage exists" and "the parser missed it" look identical otherwise, and only
    /// one of them is a bug worth chasing.
    private static func weeklyPercentLine(_ weekly: UsageProbe.Weekly) -> String {
        guard let percent = weekly.percent else {
            return "not reported by /usage (no weekly limit on this plan)"
        }
        return String(format: "%.1f%%", percent) + (weekly.limitLabel.map { "  (\($0))" } ?? "")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private lazy var notch = NotchController(store: store)
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()

        notch.onRefresh = { [weak self] in self?.store.forceRefresh() }
        notch.menuProvider = { [weak self] in self?.buildMenu() ?? NSMenu() }
        notch.onSettings = { [weak self] in self?.openSettings() }
        notch.onToggleLogin = { _ = LoginItem.set(!LoginItem.isEnabled) }
        notch.onQuit = { NSApp.terminate(nil) }
        notch.install()
    }

    // MARK: - Menu
    //
    // There is deliberately no NSStatusItem. On a notched Mac the menu bar fills up
    // fast: measured here, only 55pt separated the cutout from the leftmost Control
    // Center item, and the buddy already sits in 32 of it. An icon-plus-percentage
    // item needs ~62pt, so macOS silently hid it — the app had no reachable menu at
    // all. Right-clicking the buddy or the panel opens this instead.

    private func buildMenu() -> NSMenu {
        let s = store.snapshot
        let menu = NSMenu()

        menu.addItem(disabled("New tokens: \(Format.exact(s.used))"))
        // The panel's bar carries the shape of the split; the menu carries the exact
        // figures, which is the same division of labour as the ring and this menu's
        // percentage line.
        for model in ModelUsage.capped(s.byModel, to: 5) {
            let share = model.share(of: s.used) * 100
            menu.addItem(disabled(String(format: "  %@ %@  (%.1f%% of new)",
                                         model.name, Format.exact(model.used), share)))
        }
        menu.addItem(disabled("  + \(Format.exact(s.contextReplay)) cached context re-read"))
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
        // Mirrors the panel's weekly section, including its refusal to show a
        // percentage that /usage did not supply.
        menu.addItem(disabled("Last 7 days: \(Format.exact(s.weeklyUsed)) new tokens (this Mac)"))
        if let requests = s.weekly.requests {
            let sessions = s.weekly.sessions.map { " · \(Format.exact($0)) sessions" } ?? ""
            menu.addItem(disabled("  \(Format.exact(requests)) requests\(sessions)"))
        }
        if let percent = s.weekly.percent {
            let label = s.weekly.limitLabel.map { " (\($0))" } ?? ""
            menu.addItem(disabled(String(format: "This week%@: %.1f%% used", label, percent)))
        } else if !s.isUnverified {
            menu.addItem(disabled("No weekly limit reported by /usage"))
        }
        menu.addItem(.separator())

        menu.addItem(action("Refresh now", #selector(refreshNow)))
        menu.addItem(action("Settings…", #selector(openSettingsMenu), key: ","))
        let login = action(LoginItem.isEnabled ? "Disable launch at login" : "Launch at login",
                           #selector(toggleLoginItem))
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action("Quit Claude Usage Buddy", #selector(quit), key: "q"))
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
    @objc private func toggleLoginItem() { _ = LoginItem.set(!LoginItem.isEnabled) }
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
