import AppKit
import Combine
import Foundation

/// Single source of truth for the UI.
///
/// Two sources, each doing what it is actually good at:
/// - `claude -p "/usage"` for the percentage and reset time — authoritative, free,
///   and aware of usage from claude.ai and other machines
/// - local transcripts for the exact token count, which `/usage` does not report
///
/// No credentials, no calibration, nothing inferred.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var weekly = TokenCounts()
    @Published private(set) var lastUpdated: Date?

    private let scanner = TranscriptScanner()
    private var tokenTimer: Timer?
    private var probeTimer: Timer?
    private var watcher: DirectoryWatcher?
    private var probing = false
    private var lastProbeAttempt: Date?

    /// Cheap: just re-reads appended transcript bytes.
    private let tokenInterval: TimeInterval = 15
    /// Spawns the CLI (~1–3s), so keep it occasional. Costs no quota.
    private let probeInterval: TimeInterval = 240
    /// Floor for on-demand probes (opening the panel, waking from sleep).
    private let probeFloor: TimeInterval = 25

    func start() {
        recomputeTokens()
        probe()

        tokenTimer = Timer.scheduledTimer(withTimeInterval: tokenInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recomputeTokens() }
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: probeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probe() }
        }

        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        watcher = DirectoryWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.recomputeTokens() }
        }

        // Sleep freezes every timer, so on wake the countdown and the window itself
        // can both be badly out of date — the window may have rolled over entirely.
        // Re-probe immediately rather than waiting out the interval.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.probe(force: true) }
        }
    }

    /// Called when the panel opens, so it never shows a stale number.
    func refresh() {
        recomputeTokens()
        probe()
    }

    // MARK: - Tokens

    private func recomputeTokens() {
        let entries = scanner.scan()
        let now = Date()

        // Count only what falls inside the authoritative window. Before the first
        // probe lands, fall back to the locally inferred block so the panel is not
        // blank for the couple of seconds the CLI takes.
        let start = snapshot.windowStart ?? UsageBlock.current(from: entries, now: now)?.start

        var next = snapshot
        next.windowStart = start
        next.counts = entries.reduce(into: TokenCounts()) { acc, entry in
            guard let start else { return }
            if entry.timestamp >= start { acc += entry.counts }
        }
        snapshot = next
        weekly = UsageBlock.trailingWeek(from: entries, now: now)
        lastUpdated = now
    }

    // MARK: - Probe

    private func probe(force: Bool = false) {
        guard !probing else { return }
        if !force, let last = lastProbeAttempt, Date().timeIntervalSince(last) < probeFloor { return }
        lastProbeAttempt = Date()
        probing = true

        Task.detached(priority: .utility) {
            let outcome = Result { try UsageProbe.run() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.probing = false
                switch outcome {
                case .success(let result):
                    var next = self.snapshot
                    next.percent = result.percent
                    next.resetAt = result.resetAt
                    // The window is defined by its reset, not by anything local.
                    next.windowStart = result.resetAt?.addingTimeInterval(-UsageBlock.windowLength)
                    next.probedAt = Date()
                    next.probeError = nil
                    self.snapshot = next
                    self.recomputeTokens()
                case .failure(let error):
                    var next = self.snapshot
                    next.probeError = "\(error)"
                    self.snapshot = next
                }
            }
        }
    }
}

/// Thin FSEvents-style watcher over the transcripts directory. Coalesces bursts so a
/// chatty session does not trigger a rescan per line.
private final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    init?(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.coalesce() }
        src.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        src.resume()
        source = src
    }

    private func coalesce() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }
}
