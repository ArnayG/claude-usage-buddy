import Combine
import Foundation

/// Single source of truth for the UI.
///
/// Entirely local: transcripts on disk plus whatever calibration you have entered.
/// No network, no keychain, no credentials of any kind.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var weekly = TokenCounts()
    @Published private(set) var lastUpdated: Date?

    private let scanner = TranscriptScanner()
    private var timer: Timer?
    private var watcher: DirectoryWatcher?

    /// Slow heartbeat; the directory watcher supplies the fast path.
    private let pollInterval: TimeInterval = 15

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        watcher = DirectoryWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let entries = scanner.scan()
        let now = Date()
        let block = UsageBlock.current(from: entries, now: now)

        var next = UsageSnapshot(
            counts: block?.counts ?? TokenCounts(),
            allowance: Settings.allowance,
            blockStart: block?.start,
            resetAt: block?.end
        )
        next.resetSource = block == nil ? .unknown : .inferred
        next.calibratedAt = Settings.calibratedAt
        next.isTwoPoint = Settings.isTwoPoint
        next.hiddenTokens = Settings.hiddenTokens(forWindowStarting: block?.start)

        // A reset time copied from /usage beats anything inferred from transcripts,
        // which cannot see usage from claude.ai or another machine. It expires by
        // itself once it passes.
        if let pinned = Settings.overrideResetAt {
            next.resetAt = pinned
            next.blockStart = pinned.addingTimeInterval(-UsageBlock.windowLength)
            next.resetSource = .pinned
        }

        snapshot = next
        weekly = UsageBlock.trailingWeek(from: entries, now: now)
        lastUpdated = now
    }

    /// Records a `/usage` reading and recomputes the allowance.
    ///
    /// Passes the *visible* token count, not `snapshot.used` — the latter already
    /// includes a previously solved hidden baseline, and feeding that back in would
    /// double-count it.
    @discardableResult
    func calibrate(observedPercent: Double, resetAt: Date? = nil) -> Settings.CalibrationResult {
        if let resetAt { Settings.overrideResetAt = resetAt }
        let result = Settings.record(percent: observedPercent,
                                     rawTokens: snapshot.counts.total,
                                     windowStart: snapshot.blockStart)
        refresh()
        return result
    }

    func setAllowance(_ value: Int) {
        Settings.allowance = value
        refresh()
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
