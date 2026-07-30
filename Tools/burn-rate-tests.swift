import Foundation

// Synthetic-series checks for `BurnRate`. The repo has no test target — there is no
// Xcode on the machine it is developed on — so this is a plain executable built by
// `make test-burn-rate`, which compiles the real `BurnRate.swift` rather than a copy.
//
// Every series here is quantised to whole percentages before it reaches the estimator,
// because that is what `/usage` reports and it is the dominant error term. A test fed
// exact reals would pass while telling you nothing about the case that matters.

// MARK: - Harness

private var failures = 0
private var checks = 0

private func check(_ label: String, _ passed: Bool, _ detail: String = "") {
    checks += 1
    if passed {
        print("  ok   \(label)\(detail.isEmpty ? "" : "  [\(detail)]")")
    } else {
        failures += 1
        print("  FAIL \(label)\(detail.isEmpty ? "" : "  [\(detail)]")")
    }
}

private func section(_ name: String) { print("\n\(name)") }

// MARK: - Series builders

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)   // fixed, so runs are identical

/// `minutes` apart, percentage from a closure, rounded to whole numbers the way the CLI
/// reports them.
private func series(count: Int,
                    everyMinutes: Double,
                    endingAt end: Date,
                    percent: (Double) -> Double) -> [BurnSample] {
    (0..<count).map { i in
        let minutesBeforeEnd = Double(count - 1 - i) * everyMinutes
        let at = end.addingTimeInterval(-minutesBeforeEnd * 60)
        return BurnSample(at: at, percent: percent(-minutesBeforeEnd / 60).rounded())
    }
}

private extension BurnRate.Projection {
    var isExhausts: Bool { if case .exhausts = self { return true }; return false }
    var isNotRising: Bool { if case .notRising = self { return true }; return false }
    var isResetsFirst: Bool { if case .resetsFirst = self { return true }; return false }
    var blocker: BurnRate.Blocker? { if case .unknown(let b) = self { return b }; return nil }
    var at: Date? { if case .exhausts(let at, _, _, _) = self { return at }; return nil }
}

private func minutes(_ interval: TimeInterval) -> String {
    String(format: "%.1fm", interval / 60)
}

// MARK: - Cases

private func testRisingSteadily() {
    section("rising steadily — 20%/h from 60% with 3h to reset")
    // 40 samples, one a minute, ending at 60%.
    let history = series(count: 40, everyMinutes: 1, endingAt: t0) { hours in 60 + 20 * hours }
    let p = BurnRate.project(percent: 60, resetAt: t0.addingTimeInterval(3 * 3600),
                             history: history, now: t0)

    check("projects an exhaustion time", p.isExhausts, p.summary())
    if let rate = p.rate {
        check("recovers the rate within 2%/h", abs(rate.perHour - 20) < 2,
              String(format: "%.2f%%/h ±%.2f", rate.perHour, rate.standardError))
        check("standard error is small", rate.standardError < 4,
              String(format: "±%.2f", rate.standardError))
    }
    if let at = p.at {
        // 40 points remaining at 20%/h = 2h.
        let error = abs(at.timeIntervalSince(t0.addingTimeInterval(2 * 3600)))
        check("lands within 10 minutes of the truth", error < 600, minutes(error))
    }
    check("reports a margin", p.uncertainty != nil, p.uncertainty.map(minutes) ?? "nil")
}

private func testFalling() {
    section("falling — old requests aging out of the rolling window")
    let history = series(count: 40, everyMinutes: 1, endingAt: t0) { hours in 30 - 18 * hours }
    let p = BurnRate.project(percent: 30, resetAt: t0.addingTimeInterval(2 * 3600),
                             history: history, now: t0)
    check("refuses to project", p.isNotRising, p.summary())
    check("reports a negative rate", (p.rate?.perHour ?? 0) < 0,
          String(format: "%.2f%%/h", p.rate?.perHour ?? 0))
}

private func testFlat() {
    section("flat — 47% for 40 minutes")
    let history = series(count: 40, everyMinutes: 1, endingAt: t0) { _ in 47 }
    let p = BurnRate.project(percent: 47, resetAt: t0.addingTimeInterval(2 * 3600),
                             history: history, now: t0)
    check("refuses to project", p.isNotRising, p.summary())
    check("rate is ~zero", abs(p.rate?.perHour ?? 99) < 0.01,
          String(format: "%.4f%%/h", p.rate?.perHour ?? 99))
}

private func testSingleSampleAndEmpty() {
    section("too little data")
    let none = BurnRate.project(percent: 40, resetAt: t0.addingTimeInterval(3600),
                                history: [], now: t0)
    check("no samples", none.blocker == .noSamples, none.summary())

    let one = BurnRate.project(percent: 40, resetAt: t0.addingTimeInterval(3600),
                               history: [BurnSample(at: t0, percent: 40)], now: t0)
    check("one sample", one.blocker == .tooFewSamples, one.summary())

    let two = BurnRate.project(percent: 40, resetAt: t0.addingTimeInterval(3600),
                               history: [BurnSample(at: t0.addingTimeInterval(-900), percent: 30),
                                         BurnSample(at: t0, percent: 40)],
                               now: t0)
    check("two samples (zero-residual line, meaningless error)",
          two.blocker == .tooFewSamples, two.summary())

    // Three samples but only three minutes of baseline: 1pp of rounding across that span
    // is 20%/h of ambiguity, so there is nothing to say yet.
    let short = series(count: 4, everyMinutes: 1, endingAt: t0) { hours in 40 + 30 * hours }
    let p = BurnRate.project(percent: 40, resetAt: t0.addingTimeInterval(3600),
                             history: short, now: t0)
    check("span under 8 minutes", p.blocker == .tooShortSpan, p.summary())
}

private func testStale() {
    section("stale — a rising trend the user walked away from")
    // Steep rise, but the newest reading is 25 minutes old.
    let end = t0.addingTimeInterval(-25 * 60)
    let history = series(count: 30, everyMinutes: 1, endingAt: end) { hours in 70 + 40 * hours }
    let fresh = BurnRate.project(percent: 70, resetAt: t0.addingTimeInterval(2 * 3600),
                                 history: history, now: end)
    check("projects while the reading is fresh", fresh.isExhausts, fresh.summary())

    let p = BurnRate.project(percent: 70, resetAt: t0.addingTimeInterval(2 * 3600),
                             history: history, now: t0)
    check("withdraws once the reading is 25m old", p.blocker == .stale, p.summary())
}

private func testWindowRollover() {
    section("window rollover — history must not leak across it")
    // 30 minutes of hard use, then the window rolls: percent drops to 3 and windowStart
    // jumps to now. `record` is what enforces the scoping, so drive it directly.
    var history = BurnHistory()
    for i in 0..<30 {
        let at = t0.addingTimeInterval(Double(i - 30) * 60)
        let oldWindowStart = t0.addingTimeInterval(-4.5 * 3600)
        history.record(percent: (50 + Double(i)).rounded(), at: at, windowStart: oldWindowStart)
    }
    check("30 samples retained inside the old window", history.samples.count == 30,
          "\(history.samples.count)")

    let rolledStart = t0.addingTimeInterval(-30)   // brand new window
    history.record(percent: 3, at: t0, windowStart: rolledStart)
    check("everything before the new window start is discarded", history.samples.count == 1,
          "\(history.samples.count)")

    let p = BurnRate.project(percent: 3, resetAt: t0.addingTimeInterval(5 * 3600),
                             history: history.samples, now: t0)
    check("no projection from the surviving sample", p.blocker == .tooFewSamples, p.summary())

    // The reset time also creeps *forward* by a few minutes without the window rolling.
    // Only the samples the creep left behind should go.
    var creeping = BurnHistory()
    for i in 0..<40 {
        creeping.record(percent: (20 + Double(i) * 0.5).rounded(),
                        at: t0.addingTimeInterval(Double(i - 40) * 60),
                        windowStart: t0.addingTimeInterval(-4.9 * 3600))
    }
    let before = creeping.samples.count
    creeping.record(percent: 40, at: t0.addingTimeInterval(60),
                    windowStart: t0.addingTimeInterval(-25 * 60))
    check("a 15-minute creep drops only the samples it passed",
          creeping.samples.count == 26 && before == 40,
          "\(before) -> \(creeping.samples.count)")
}

private func testAgeOutCliff() {
    section("age-out cliff — a burst leaving the window all at once")
    // 20 minutes rising at 24%/h, then a 22-point cliff as an old burst ages out, then
    // 20 more minutes rising at 24%/h. Fitting across the cliff gives a wildly negative
    // slope; the estimator must restart after it.
    var samples: [BurnSample] = []
    for i in 0..<20 {
        samples.append(BurnSample(at: t0.addingTimeInterval(Double(i - 40) * 60),
                                  percent: (60 + 0.4 * Double(i)).rounded()))
    }
    for i in 0..<20 {
        samples.append(BurnSample(at: t0.addingTimeInterval(Double(i - 20) * 60),
                                  percent: (46 + 0.4 * Double(i)).rounded()))
    }
    let acrossCliff = BurnRate.rate(from: samples, now: t0)
    guard case .success(let rate) = acrossCliff else {
        check("fit succeeds after the cliff", false, "\(acrossCliff)")
        return
    }
    check("uses only post-cliff samples", rate.sampleCount == 20, "\(rate.sampleCount)")
    check("recovers the post-cliff rate", abs(rate.perHour - 24) < 4,
          String(format: "%.2f%%/h", rate.perHour))

    // Sanity: without the cliff guard, the same series fits strongly negative.
    let naive = naiveSlope(samples)
    check("a naive fit would have been badly wrong", naive < -5,
          String(format: "%.1f%%/h", naive))
}

private func testResetsFirst() {
    section("rising, but the window resets first")
    // 6%/h from 30% needs 11.6h; the reset is 90 minutes away.
    let history = series(count: 40, everyMinutes: 1, endingAt: t0) { hours in 30 + 6 * hours }
    let p = BurnRate.project(percent: 30, resetAt: t0.addingTimeInterval(90 * 60),
                             history: history, now: t0)
    check("says the reset wins", p.isResetsFirst, p.summary())
}

private func testSparseIdleCadence() {
    section("sparse samples — the 600s idle cadence")
    let history = series(count: 6, everyMinutes: 10, endingAt: t0) { hours in 55 + 15 * hours }
    let p = BurnRate.project(percent: 55, resetAt: t0.addingTimeInterval(4 * 3600),
                             history: history, now: t0)
    check("still projects", p.isExhausts, p.summary())
    if let rate = p.rate {
        check("recovers the rate within 3%/h", abs(rate.perHour - 15) < 3,
              String(format: "%.2f%%/h ±%.2f", rate.perHour, rate.standardError))
    }
}

private func testWeakRiseIsNotOversold() {
    section("weak rise — 2%/h, barely above the rounding")
    let history = series(count: 40, everyMinutes: 1, endingAt: t0) { hours in 44 + 2 * hours }
    let p = BurnRate.project(percent: 44, resetAt: t0.addingTimeInterval(4.9 * 3600),
                             history: history, now: t0)
    // 56 points at 2%/h is 28 hours — far beyond any window — so whether the gate or the
    // reset comparison catches it, the answer must not be a time.
    check("does not print a time", !p.isExhausts, p.summary())
}

private func testJitterUnderQuantisation() {
    section("jitter — same true rate, 30 different rounding phases")
    // The failure this guards against: a two-sample slope over whole percentages swings
    // by tens of points an hour from one probe to the next. Sweep the phase and check the
    // fitted rate stays in a narrow band.
    var fitted: [Double] = []
    var pairwise: [Double] = []
    for phase in 0..<30 {
        let offset = Double(phase) * 0.31
        let history = series(count: 30, everyMinutes: 1, endingAt: t0) { hours in
            40 + offset + 18 * hours
        }
        if case .success(let rate) = BurnRate.rate(from: history, now: t0) {
            fitted.append(rate.perHour)
        }
        // The naive alternative: last two samples.
        let a = history[history.count - 2], b = history[history.count - 1]
        pairwise.append((b.percent - a.percent) / (b.at.timeIntervalSince(a.at) / 3600))
    }
    let spread = (fitted.max() ?? 0) - (fitted.min() ?? 0)
    let naiveSpread = (pairwise.max() ?? 0) - (pairwise.min() ?? 0)
    check("all 30 phases fit", fitted.count == 30, "\(fitted.count)")
    check("fitted spread under 4%/h", spread < 4, String(format: "%.2f%%/h", spread))
    check("two-sample spread is far worse", naiveSpread > 4 * max(spread, 0.01),
          String(format: "%.1f%%/h vs %.2f", naiveSpread, spread))
}

private func testBurstyUsage() {
    section("bursty usage — the same 20%/h arriving in lumps")
    // Real consumption is not a ramp: nothing happens for four minutes, then a
    // multi-point step. The average is still 20%/h, but the residuals are much larger
    // than rounding alone, and the reported margin must widen to match — that is the
    // whole point of carrying a standard error rather than a bare slope.
    var samples: [BurnSample] = []
    for i in 0..<40 {
        let step = (Double(i) / 5).rounded(.down) * (20.0 / 60 * 5)
        samples.append(BurnSample(at: t0.addingTimeInterval(Double(i - 39) * 60),
                                  percent: (60 - 20.0 * 39 / 60 + step).rounded()))
    }
    let smooth = series(count: 40, everyMinutes: 1, endingAt: t0) { hours in 60 + 20 * hours }
    guard case .success(let bursty) = BurnRate.rate(from: samples, now: t0),
          case .success(let ramp) = BurnRate.rate(from: smooth, now: t0)
    else { check("both fits succeed", false); return }

    check("recovers the average rate within 5%/h", abs(bursty.perHour - 20) < 5,
          String(format: "%.2f%%/h ±%.2f", bursty.perHour, bursty.standardError))
    check("margin is wider than for a smooth ramp",
          bursty.standardError > ramp.standardError,
          String(format: "±%.2f vs ±%.2f", bursty.standardError, ramp.standardError))
}

private func testPauseDecays() {
    section("pause — 30 minutes at 30%/h, then 15 minutes idle")
    // Deliberate behaviour, not a bug: the exponential weighting means a pause bleeds the
    // estimate down over tens of minutes instead of collapsing it instantly, so the panel
    // does not flap every time someone stops to read a diff. What must hold is that the
    // rate falls and keeps falling.
    func history(idleMinutes: Double) -> [BurnSample] {
        var samples: [BurnSample] = []
        let burnEnd = t0.addingTimeInterval(-idleMinutes * 60)
        for i in 0..<30 {
            samples.append(BurnSample(at: burnEnd.addingTimeInterval(Double(i - 29) * 60),
                                      percent: (40 + 0.5 * Double(i)).rounded()))
        }
        // Idle probes land every 10 minutes and read the same percentage.
        var t = burnEnd.addingTimeInterval(600)
        while t <= t0 {
            samples.append(BurnSample(at: t, percent: 54.5.rounded()))
            t = t.addingTimeInterval(600)
        }
        return samples
    }

    let rates: [Double] = [0, 10, 20, 40].compactMap {
        if case .success(let r) = BurnRate.rate(from: history(idleMinutes: $0), now: t0) {
            return r.perHour
        }
        return nil
    }
    check("all four snapshots fit", rates.count == 4, "\(rates.count)")
    check("rate decays monotonically as the pause lengthens",
          zip(rates, rates.dropFirst()).allSatisfy { $0 > $1 },
          rates.map { String(format: "%.1f", $0) }.joined(separator: " -> "))
    check("30%/h recovered before the pause", abs((rates.first ?? 0) - 30) < 3,
          String(format: "%.2f%%/h", rates.first ?? 0))
}

private func testSpentAndNoWindow() {
    section("edges")
    let full = BurnRate.project(percent: 100, resetAt: t0.addingTimeInterval(3600),
                                history: [], now: t0)
    check("100% is spent, not projected", full == .spent, full.summary())

    let history = series(count: 20, everyMinutes: 1, endingAt: t0) { hours in 50 + 20 * hours }
    let noReset = BurnRate.project(percent: 50, resetAt: nil, history: history, now: t0)
    check("no reset time means no projection", noReset.blocker == .noWindow, noReset.summary())

    let pastReset = BurnRate.project(percent: 50, resetAt: t0.addingTimeInterval(-60),
                                     history: history, now: t0)
    check("a reset already in the past means no projection",
          pastReset.blocker == .noWindow, pastReset.summary())
}

private func testHistoryHousekeeping() {
    section("history housekeeping")
    var history = BurnHistory()
    for i in 0..<400 {
        history.record(percent: Double(i % 100),
                       at: t0.addingTimeInterval(Double(i) * 20), windowStart: nil)
    }
    check("capped at capacity", history.samples.count <= BurnHistory.capacity,
          "\(history.samples.count)")
    check("stays inside the horizon",
          history.samples.allSatisfy {
              history.samples.last!.at.timeIntervalSince($0.at) <= BurnRate.horizon
          })
    check("strictly increasing", zip(history.samples, history.samples.dropFirst())
        .allSatisfy { $0.at < $1.at })

    // Clock rewind: a reading stamped earlier than the newest one supersedes it.
    var rewound = BurnHistory()
    rewound.record(percent: 10, at: t0, windowStart: nil)
    rewound.record(percent: 12, at: t0.addingTimeInterval(600), windowStart: nil)
    rewound.record(percent: 4, at: t0.addingTimeInterval(300), windowStart: nil)
    check("clock rewind drops superseded samples", rewound.samples.count == 2,
          rewound.samples.map { String(format: "%.0f", $0.percent) }.joined(separator: ","))

    // Round-trip through the same encoder `Settings` uses.
    let data = try! JSONEncoder().encode(history)
    let decoded = try! JSONDecoder().decode(BurnHistory.self, from: data)
    check("survives a JSON round trip", decoded == history, "\(data.count) bytes")
    check("persisted blob stays small", data.count < 12_000, "\(data.count) bytes")
}

/// Unweighted ordinary least squares, used only to show what the guards are protecting
/// against.
private func naiveSlope(_ samples: [BurnSample]) -> Double {
    let n = Double(samples.count)
    let xs = samples.map { $0.at.timeIntervalSince(samples[0].at) / 3600 }
    let ys = samples.map(\.percent)
    let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
    let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
    let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
    return den == 0 ? 0 : num / den
}

// MARK: - Entry point

@main
struct BurnRateTests {
    static func main() {
        print("BurnRate synthetic-series checks")
        testRisingSteadily()
        testFalling()
        testFlat()
        testSingleSampleAndEmpty()
        testStale()
        testWindowRollover()
        testAgeOutCliff()
        testResetsFirst()
        testSparseIdleCadence()
        testWeakRiseIsNotOversold()
        testJitterUnderQuantisation()
        testBurstyUsage()
        testPauseDecays()
        testSpentAndNoWindow()
        testHistoryHousekeeping()

        print("\n\(checks - failures)/\(checks) checks passed")
        exit(failures == 0 ? 0 : 1)
    }
}
