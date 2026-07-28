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
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Headless readout of exactly what the notch would show. Handy for sanity
    /// checks against `/usage` without needing to hover.
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

        let weekly = UsageBlock.trailingWeek(from: entries, now: now)

        // Same server path the app uses, run synchronously for the CLI.
        var serverLine = "off"
        if Settings.useServerUsage {
            let gate = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var outcome = "unavailable"
            nonisolated(unsafe) var fetched: ServerUsageClient.Report?
            Task.detached {
                do {
                    let report = try await ServerUsageClient.fetch()
                    fetched = report
                    outcome = "ok"
                } catch {
                    outcome = "unavailable (\(error))"
                }
                gate.signal()
            }
            _ = gate.wait(timeout: .now() + 12)
            serverLine = outcome
            if let report = fetched {
                snapshot.serverPercent = report.sessionPercent
                if let reset = report.sessionResetsAt { snapshot.resetAt = reset }
                if let pct = report.sessionPercent, pct >= 5, snapshot.used > 0 {
                    snapshot.allowance = Int((Double(snapshot.used) / (pct / 100)).rounded())
                }
            }
        }

        print("""
        Claude Usage Buddy
          entries parsed : \(entries.count)
          tokens used    : \(Format.exact(snapshot.used))
            input        : \(Format.exact(snapshot.counts.input))
            output       : \(Format.exact(snapshot.counts.output))
            cache write  : \(Format.exact(snapshot.counts.cacheCreation))
            cache read   : \(Format.exact(snapshot.counts.cacheRead))
          allowance      : \(Format.exact(snapshot.allowance))\(snapshot.isEstimated ? "" : " (implied by server %)")
          used           : \(String(format: "%.2f", snapshot.percent))%\(snapshot.isEstimated ? " (estimated)" : " (live from Anthropic)")
          server         : \(serverLine)
          window start   : \(snapshot.blockStart.map(Format.time) ?? "—")
          resets at      : \(snapshot.resetAt.map(Format.time) ?? "—")
          resets in      : \(snapshot.resetAt.map { Format.duration(max($0.timeIntervalSince(now), 0)) } ?? "—")
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

        notch.onCalibrate = { [weak self] in self?.openSettings() }
        notch.install()

        installStatusItem()

        // Keep the menu bar summary in step with the panel.
        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusTitle() }
            .store(in: &cancellables)
    }

    // MARK: - Status item
    //
    // Serves two purposes beyond convenience: it is the fallback surface on Macs
    // with no notch, and it makes the app reachable without hovering, which a
    // hover-only UI would not be.

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
        menu.addItem(disabled("Allowance: \(Format.exact(s.allowance))"))
        menu.addItem(disabled(String(format: "Session used: %.1f%%%@",
                                     s.percent, s.isEstimated ? " (estimated)" : "")))
        if let reset = s.resetAt {
            menu.addItem(disabled("Resets \(Format.time(reset)) · in \(Format.duration(max(reset.timeIntervalSinceNow, 0)))"))
        } else {
            menu.addItem(disabled("No active session window"))
        }
        menu.addItem(.separator())
        menu.addItem(disabled("Last 7 days: \(Format.exact(store.weekly.total)) tokens"))
        menu.addItem(.separator())

        menu.addItem(action("Refresh", #selector(refreshNow)))
        menu.addItem(action("Settings & Calibration…", #selector(openSettingsMenu), key: ","))
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
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Settings

    private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 570),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage Buddy"
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
