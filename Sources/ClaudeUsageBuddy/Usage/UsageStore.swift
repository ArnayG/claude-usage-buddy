import Combine
import Foundation

/// Single source of truth for the UI.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var weekly = TokenCounts()
    @Published private(set) var lastUpdated: Date?
    /// Set when the opt-in server path was tried and did not work.
    @Published private(set) var serverNote: String?

    private let scanner = TranscriptScanner()
    private var timer: Timer?
    private var watcher: DirectoryWatcher?
    private var isFetchingServer = false

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
            resetAt: block?.end,
            source: .local
        )
        // Preserve a server percentage across local refreshes so the number does not
        // flicker between authoritative and estimated between fetches.
        if let existing = snapshot.serverPercent, snapshot.source == .server {
            next.serverPercent = existing
            next.source = .server
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
        isFetchingServer = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.isFetchingServer = false } }
            do {
                let report = try await ServerUsageClient.fetch()
                await MainActor.run {
                    guard let self else { return }
                    var s = self.snapshot
                    s.serverPercent = report.sessionPercent
                    if let reset = report.sessionResetsAt { s.resetAt = reset }
                    s.source = .server
                    self.snapshot = s
                    self.serverNote = nil
                }
            } catch {
                await MainActor.run {
                    // Fail soft: keep the local estimate, just say the sync did not land.
                    self?.serverNote = "server sync unavailable"
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
