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
/// The trailing-week figures follow the same split: `/usage` supplies a weekly
/// percentage *if the plan has one* (most do not), transcripts supply the 7-day token
/// volume regardless. The two are never mixed into one number.
///
/// No credentials, no calibration, nothing inferred.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var lastUpdated: Date?

    /// Where the current trend lands, recomputed on each successful probe.
    ///
    /// Deliberately *not* recomputed on the UI's one-second tick. The percentage is only
    /// known at probe time, so re-running the extrapolation against a later `now` while
    /// holding the level fixed would push the projected time steadily further away —
    /// implying the user had stopped burning when nothing of the sort had been observed.
    /// It is an "as of the last reading" answer, and `BurnRate.staleness` withdraws it
    /// once that reading is too old to stand behind.
    @Published private(set) var projection = BurnRate.Projection.unknown(.noSamples)

    /// Percentage readings for the current window. Loaded from disk so a relaunch or a
    /// wake does not throw away a trend that is still valid.
    private var burnHistory = Settings.burnHistory

    private let scanner = TranscriptScanner()
    private var tokenTimer: Timer?
    private var probeTimer: Timer?
    private var watcher: DirectoryWatcher?
    /// Exposed so the Refresh button can show that something is happening.
    @Published private(set) var isProbing = false
    private var lastProbeAttempt: Date?
    /// Timestamp of the newest transcript entry seen, used to tell active from idle.
    private var newestEntryAt: Date?

    /// Cheap: just re-reads appended transcript bytes.
    private let tokenInterval: TimeInterval = 15
    /// How often the scheduler reconsiders probing.
    private let schedulerInterval: TimeInterval = 20

    /// While Claude is actually being used the percentage moves fast — 8% to 14% in
    /// a couple of minutes of heavy work — so a slow poll shows a visibly wrong
    /// number. Probe often when transcripts show new activity.
    private let activeProbeInterval: TimeInterval = 60
    /// When nothing is happening locally the only thing that can move the number is
    /// usage on another device, so back right off. This is also what keeps the
    /// average cost down: the CLI spawn is the expensive part.
    private let idleProbeInterval: TimeInterval = 600
    /// Guards only against double-clicks; a forced refresh ignores everything else.
    private let forcedProbeFloor: TimeInterval = 3

    func start() {
        recomputeTokens()
        probe()

        tokenTimer = Timer.scheduledTimer(withTimeInterval: tokenInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recomputeTokens() }
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: schedulerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probeIfDue() }
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

    /// Opening the panel: refresh if it is even slightly stale, since this is the
    /// moment the number is actually being read.
    func refresh() {
        recomputeTokens()
        if let last = lastProbeAttempt, Date().timeIntervalSince(last) < 15 { return }
        probe(force: true)
    }

    /// The Refresh button. Always probes — an earlier version routed this through the
    /// same throttle as the background poll, so clicking it did nothing at all and
    /// left a stale percentage on screen.
    func forceRefresh() {
        recomputeTokens()
        probe(force: true)
    }

    /// Fast while Claude is in use, slow when it is not.
    private func probeIfDue() {
        expireStaleProjection()
        let now = Date()
        let sinceProbe = lastProbeAttempt.map { now.timeIntervalSince($0) } ?? .infinity

        // New assistant messages since the last probe means the percentage has moved.
        let active: Bool = {
            guard let newest = newestEntryAt, let last = lastProbeAttempt else { return true }
            return newest > last
        }()

        if sinceProbe >= (active ? activeProbeInterval : idleProbeInterval) {
            probe()
        }
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
        next.weeklyCounts = UsageBlock.trailingWeek(from: entries, now: now)
        // Same entries, same window: the split is a regrouping of the headline, not a
        // second measurement, so the two can never disagree.
        next.byModel = ModelUsage.split(entries, since: start)
        snapshot = next
        newestEntryAt = entries.map(\.timestamp).max()
        lastUpdated = now
    }

    // MARK: - Burn rate

    /// Files the new reading and re-derives the projection.
    ///
    /// `windowStart` is passed through so `BurnHistory` can drop samples the rolling
    /// window has left behind; that single rule covers both the reset time creeping
    /// forward and the window rolling over outright.
    ///
    /// `now` is the probe timestamp, not the wall clock, which is what anchors the answer
    /// to the reading it was drawn from — see `projection`.
    private func recordBurnSample(_ snapshot: UsageSnapshot) {
        guard let probedAt = snapshot.probedAt else { return }
        burnHistory.record(percent: snapshot.percent,
                           at: probedAt,
                           windowStart: snapshot.windowStart)
        Settings.burnHistory = burnHistory
        projection = BurnRate.project(percent: snapshot.percent,
                                      resetAt: snapshot.resetAt,
                                      history: burnHistory.samples,
                                      now: probedAt)
    }

    /// Withdraws a projection once the reading behind it is too old to defend.
    ///
    /// Anchoring the projection at probe time is what makes it stable, but it also means
    /// nothing retracts it on its own: if probing breaks — the CLI stops answering, or the
    /// machine sits untouched — a rising trend measured a while ago would otherwise sit on
    /// screen indefinitely. `BurnRate`'s own staleness gate cannot catch this, because it
    /// is evaluated against the probe timestamp and so is fresh by construction. This runs
    /// on the 20s scheduler tick, which is ample against a 15-minute threshold.
    private func expireStaleProjection() {
        guard projection.rate != nil else { return }
        guard let probedAt = snapshot.probedAt,
              Date().timeIntervalSince(probedAt) > BurnRate.staleness
        else { return }
        projection = .unknown(.stale)
    }

    // MARK: - Probe

    private func probe(force: Bool = false) {
        guard !isProbing else { return }
        if let last = lastProbeAttempt, Date().timeIntervalSince(last) < forcedProbeFloor { return }
        _ = force   // scheduling is decided by probeIfDue; this call always runs
        lastProbeAttempt = Date()
        isProbing = true

        Task.detached(priority: .utility) {
            let outcome = Result { try UsageProbe.run() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isProbing = false
                switch outcome {
                case .success(let result):
                    var next = self.snapshot
                    next.percent = result.percent
                    next.resetAt = result.resetAt
                    next.weekly = result.weekly
                    // The window is defined by its reset, not by anything local.
                    next.windowStart = result.resetAt?.addingTimeInterval(-UsageBlock.windowLength)
                    next.probedAt = Date()
                    next.probeError = nil
                    self.snapshot = next
                    self.recomputeTokens()
                    self.recordBurnSample(next)
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
