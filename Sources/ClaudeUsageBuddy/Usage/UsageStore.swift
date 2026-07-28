import Combine
import Foundation

/// Single source of truth for the UI.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var weekly = TokenCounts()
    /// Server-reported weekly utilisation, when the plan has a weekly bucket.
    @Published private(set) var weeklyPercent: Double?
    @Published private(set) var lastUpdated: Date?
    /// Set when the opt-in server path was tried and did not work.
    @Published private(set) var serverNote: String?

    private let scanner = TranscriptScanner()
    private var timer: Timer?
    private var watcher: DirectoryWatcher?
    private var isFetchingServer = false
    private var lastServerAttempt: Date?
    private var serverBackoff: TimeInterval = 0

    /// Slow heartbeat; the directory watcher supplies the fast path.
    private let pollInterval: TimeInterval = 15

    /// Floor between usage-endpoint calls.
    ///
    /// This endpoint is rate limited — polling it on every local refresh earns a
    /// 429 within the hour. It only needs to be called often enough to keep the
    /// allowance calibrated and the reset time honest; the token count in between
    /// comes from transcripts, for free.
    private let serverMinInterval: TimeInterval = 300

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
            resetAt: block?.end,
            source: .local
        )
        // Carry the server's calibration forward between fetches. The reset time
        // especially: the server knows the true window start, which the local block
        // math can only infer from transcripts on this machine.
        if let synced = snapshot.serverSyncedAt {
            next.serverSyncedAt = synced
            next.source = .server
            if let serverReset = snapshot.resetAt, serverReset > now {
                next.resetAt = serverReset
            }
        }

        snapshot = next
        weekly = UsageBlock.trailingWeek(from: entries, now: now)
        lastUpdated = now

        if Settings.useServerUsage { fetchServer() }
    }

    /// Recomputes the allowance from a percentage the user read off `/usage`.
    func calibrate(observedPercent: Double) {
        Settings.calibrate(observedPercent: observedPercent, tokensUsed: snapshot.used)
        refresh()
    }

    func setAllowance(_ value: Int) {
        Settings.allowance = value
        refresh()
    }

    private func fetchServer() {
        guard !isFetchingServer else { return }

        // Respect the floor, and whatever backoff a previous failure imposed.
        let gap = max(serverMinInterval, serverBackoff)
        if let last = lastServerAttempt, Date().timeIntervalSince(last) < gap { return }

        // Stamp before the request, so failures throttle too.
        lastServerAttempt = Date()
        isFetchingServer = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.isFetchingServer = false } }
            do {
                let report = try await ServerUsageClient.fetch()
                await MainActor.run {
                    guard let self else { return }
                    var s = self.snapshot
                    s.serverSyncedAt = Date()
                    // The server knows the true window start, which can predate
                    // anything in the local transcripts (usage from claude.ai or
                    // another machine). Always prefer its reset time.
                    if let reset = report.sessionResetsAt { s.resetAt = reset }
                    s.source = .server

                    // Self-calibration: an authoritative percentage plus an exact
                    // local token count implies the allowance. This keeps all four
                    // readouts consistent and leaves the local fallback calibrated
                    // for whenever the server is unreachable.
                    if let pct = report.sessionPercent, pct >= 5, s.used > 0 {
                        let implied = Double(s.used) / (pct / 100)
                        // Utilisation comes back as a whole percent, so any single
                        // sample carries up to ~1pp of quantisation error — enough
                        // to make the implied allowance visibly wander. Blend into
                        // the stored value instead of overwriting it.
                        let value: Double
                        if Settings.hasCalibrated {
                            value = Double(Settings.allowance) * 0.8 + implied * 0.2
                        } else {
                            value = implied
                            Settings.hasCalibrated = true
                        }
                        let rounded = Int(value.rounded())
                        Settings.allowance = rounded
                        s.allowance = rounded
                    }

                    self.snapshot = s
                    self.weeklyPercent = report.weeklyPercent
                    self.serverNote = nil
                    self.serverBackoff = 0
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    // Fail soft: the local estimate stays on screen, calibrated from
                    // the last successful sync.
                    switch error {
                    case ServerUsageClient.Failure.badStatus(429):
                        // Rate limited. Back off hard — the numbers on screen are
                        // still live, they just stop being re-verified for a while.
                        self.serverBackoff = min(max(self.serverBackoff * 2, 900), 3600)
                        self.serverNote = "rate limited · retrying later"
                    case ServerUsageClient.Failure.notEnabled:
                        self.serverNote = nil
                    default:
                        self.serverBackoff = min(max(self.serverBackoff * 2, 60), 900)
                        self.serverNote = "server sync unavailable"
                    }
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
