import Foundation

/// One reading of the authoritative percentage, kept only so its rate of change can be
/// measured.
struct BurnSample: Equatable, Codable {
    let at: Date
    let percent: Double
}

/// The retained series of `/usage` readings.
///
/// Scoped to the current window on purpose. The session limit is a **rolling** window:
/// old requests age out of it, so the reported percentage falls as well as rises and the
/// reset time creeps forward. A sample taken before the window's current start describes
/// usage that is no longer being counted at all, so a slope drawn across that boundary
/// measures nothing real. Discarding those samples handles the slow creep and an outright
/// rollover with one rule, which is why there is no separate "did the window roll?" test.
struct BurnHistory: Equatable, Codable {
    var samples: [BurnSample] = []

    /// An hour of 60s probes is 60 samples, so 120 leaves generous headroom while
    /// keeping the persisted blob a few kilobytes. `Settings` is deliberately tiny and
    /// this should not be the thing that changes that.
    static let capacity = 120

    /// Adds a reading and forgets anything it makes irrelevant.
    mutating func record(percent: Double, at: Date, windowStart: Date?) {
        if let windowStart { samples.removeAll { $0.at < windowStart } }
        samples.removeAll { at.timeIntervalSince($0.at) > BurnRate.horizon }
        // A sample at or before the newest one means the clock moved backwards, or a
        // duplicate probe landed. Trust the newer reading and drop what it supersedes
        // rather than letting a non-monotonic series into the fit.
        samples.removeAll { $0.at >= at }
        samples.append(BurnSample(at: at, percent: percent))
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }
}

/// Estimates how fast the session window is being spent, and when it will be gone.
///
/// ## Which signal, and why
///
/// The rate is measured from **successive `/usage` percentages** and nothing else.
/// The obvious alternative — the local token rate from transcripts, which is
/// continuous and finely resolved — cannot be turned into a percentage without a
/// tokens-per-window allowance, and that constant is exactly the calibration this
/// project built, shipped, and deleted for being wrong. Transcripts also cannot see
/// claude.ai or another machine, so a local-only rate would confidently report "not on
/// track" while the window filled up elsewhere. The probe is coarse and sparse, but it
/// is the only number with an authoritative basis, so it is the only input here.
///
/// ## The maths
///
/// Weighted least squares of `percent` against time, weights decaying exponentially
/// with sample age (`halfLife`). Regression rather than a two-sample difference because
/// the percentage is reported as a **whole number**: a single pair 60s apart carries up
/// to 1pp of rounding error, which is ±60pp/hour of pure noise. Fitting N samples beats
/// that error down roughly as 1/√N, and least squares copes with the uneven spacing that
/// the adaptive probe cadence produces (60s active, 600s idle) where a plain EWMA of
/// pairwise slopes would not.
///
/// Exponential weighting rather than a flat window because the answer wanted is "if the
/// last little while continues", not "on average since the window opened". The
/// consequence, deliberately accepted, is that a pause makes the estimate decay over
/// tens of minutes rather than collapse instantly — otherwise it would flap between
/// "20 minutes left" and "not on track" every time someone stopped to read a diff.
///
/// ## What is extrapolated
///
/// The *net* rate: the derivative of the number actually on screen, which already has
/// aging-out folded into it (usage entering the window minus usage leaving it). That is
/// the right thing to extrapolate, but it is a linear model of something that is not
/// linear — early in a window nothing has aged out yet, so the net rate equals the gross
/// rate; later the net rate is smaller. Recovering the gross rate from net percentages
/// alone is an underdetermined deconvolution, so it is not attempted. The projection is
/// bounded by the reset instead, which keeps the horizon under five hours.
///
/// ## Refusing to answer
///
/// The estimate is gated on its own standard error, and reports `.unknown` or
/// `.notRising` rather than a time whenever the data cannot support one. A wrong
/// "you have 20 minutes" is worse than no projection at all.
enum BurnRate {

    // MARK: - Tuning

    /// How far back samples are considered at all. Beyond an hour the rolling window's
    /// aging has reshaped the series enough that old slope information is misleading
    /// rather than merely stale.
    static let horizon: TimeInterval = 60 * 60

    /// Weight halves every 12 minutes of age. Long enough that a dozen 60s samples all
    /// contribute meaningfully, short enough that the estimate tracks the last half hour
    /// rather than the whole window.
    static let halfLife: TimeInterval = 12 * 60

    /// Two points define a line with zero residual and therefore a meaningless standard
    /// error; three is the minimum that can disagree with itself.
    static let minimumSamples = 3

    /// A slope measured over less than this is fitting rounding, not usage: 1pp of
    /// quantisation across 8 minutes is already ±7.5pp/hour of ambiguity.
    static let minimumSpan: TimeInterval = 8 * 60

    /// If the newest reading is older than this the projection is withdrawn. Without
    /// this a rising trend measured just before the user walked away would sit on screen
    /// unchallenged for an hour. Set above the 600s idle probe cadence so a quiet machine
    /// does not flicker in and out of "need more readings".
    static let staleness: TimeInterval = 15 * 60

    /// A step down this large between adjacent samples is a block of old usage aging out
    /// of the window at once, not a rate. Levels either side of it are not comparable, so
    /// the fit restarts after the drop.
    static let cliffDrop: Double = 5

    /// Percentages arrive rounded to whole numbers, so each carries an error uniform on
    /// ±0.5pp — variance 1/12. Used as a floor on the residual variance: a series that
    /// happens to fit perfectly is not evidence of a perfectly known slope, it is
    /// evidence that the rounding happened to line up.
    ///
    /// It is only a floor, and an optimistic one, because rounding a smooth ramp produces
    /// a *correlated* sawtooth rather than independent noise, and the least-squares
    /// standard error assumes independence. In practice this barely matters: real
    /// consumption arrives in bursts, so the measured residuals are several times the
    /// floor and are what set the reported margin. The floor only binds on series smooth
    /// enough that they were never going to be the problem.
    static let quantisationVariance = 1.0 / 12.0

    /// Roughly 95%. Used both to decide the slope is distinguishable from zero and to
    /// bound the projected time.
    static let confidenceZ = 2.0

    // MARK: - Types

    /// A fitted trend, with the uncertainty that justifies believing it.
    struct Rate: Equatable {
        /// Percentage points per hour. Negative means usage is aging out faster than it
        /// is accumulating.
        var perHour: Double
        /// Standard error of `perHour`, in the same units.
        var standardError: Double
        var sampleCount: Int
        var span: TimeInterval

        /// Rising by more than the noise can explain.
        var isRising: Bool { perHour > confidenceZ * standardError }
    }

    /// Why no projection is available. Each maps to something honest on screen.
    enum Blocker: Error, Equatable {
        case noSamples
        case tooFewSamples
        case tooShortSpan
        case stale
        case noWindow
    }

    enum Projection: Equatable {
        /// No estimate is possible, and this is why.
        case unknown(Blocker)
        /// Already at the cap; there is nothing left to project.
        case spent
        /// Flat, falling, or rising too weakly to distinguish from rounding.
        case notRising(Rate)
        /// Genuinely rising, but the window resets before the cap is reached.
        case resetsFirst(Rate)
        /// On track to run out. `earliest`/`latest` are the ~95% bounds implied by the
        /// slope's standard error, `latest` clamped to the reset because past that point
        /// the projection is moot.
        case exhausts(at: Date, earliest: Date, latest: Date, rate: Rate)

        var rate: Rate? {
            switch self {
            case .notRising(let r), .resetsFirst(let r): return r
            case .exhausts(_, _, _, let r): return r
            case .unknown, .spent: return nil
            }
        }

        /// Half-width of the projected interval, taking the wider side. Nil when there
        /// is no projection to be uncertain about.
        var uncertainty: TimeInterval? {
            guard case .exhausts(let at, let earliest, let latest, _) = self else { return nil }
            return max(at.timeIntervalSince(earliest), latest.timeIntervalSince(at))
        }
    }

    // MARK: - Rate

    /// Weighted least-squares slope of percent against time, in points per hour.
    ///
    /// Pure: everything it needs is in the arguments, so the whole estimator is testable
    /// against synthetic series without a probe, a clock, or a window.
    static func rate(from history: [BurnSample], now: Date) -> Result<Rate, Blocker> {
        let recent = history
            .filter { $0.at <= now && now.timeIntervalSince($0.at) <= horizon }
            .sorted { $0.at < $1.at }

        guard let newest = recent.last else { return .failure(.noSamples) }
        guard now.timeIntervalSince(newest.at) <= staleness else { return .failure(.stale) }

        // Restart after the most recent age-out cliff, if there is one.
        var series = recent
        if let cliff = firstIndexAfterLastCliff(in: series) {
            series = Array(series[cliff...])
        }

        guard series.count >= minimumSamples else { return .failure(.tooFewSamples) }
        let span = series[series.count - 1].at.timeIntervalSince(series[0].at)
        guard span >= minimumSpan else { return .failure(.tooShortSpan) }

        // Time in hours relative to the newest sample, so x <= 0 and the intercept is
        // the fitted level *now* rather than at some arbitrary epoch.
        let anchor = newest.at
        var sw = 0.0, sx = 0.0, sxx = 0.0, sy = 0.0, sxy = 0.0, sww = 0.0
        var points: [(x: Double, y: Double, w: Double)] = []
        points.reserveCapacity(series.count)

        for sample in series {
            let age = anchor.timeIntervalSince(sample.at)
            let x = -age / 3600
            let y = sample.percent
            let w = exp2(-age / halfLife)
            points.append((x, y, w))
            sw += w; sww += w * w
            sx += w * x; sxx += w * x * x
            sy += w * y; sxy += w * x * y
        }

        let determinant = sw * sxx - sx * sx
        // Degenerate: every sample landed at the same instant. `minimumSpan` should
        // already have caught this, but the division must not be taken on trust.
        guard determinant > 0, determinant.isFinite, sw > 0 else { return .failure(.tooFewSamples) }

        let slope = (sw * sxy - sx * sy) / determinant
        let intercept = (sy - slope * sx) / sw

        var weightedSquaredResidual = 0.0
        for p in points {
            let residual = p.y - (intercept + slope * p.x)
            weightedSquaredResidual += p.w * residual * residual
        }

        // Effective sample size for exponentially weighted data: the count a flat
        // weighting would have needed to carry the same information.
        let effectiveN = (sw * sw) / sww
        var residualVariance = weightedSquaredResidual / sw
        if effectiveN > 2 { residualVariance *= effectiveN / (effectiveN - 2) }
        residualVariance = max(residualVariance, quantisationVariance)

        let standardError = (residualVariance * sw / determinant).squareRoot()
        guard slope.isFinite, standardError.isFinite else { return .failure(.tooFewSamples) }

        return .success(Rate(perHour: slope,
                             standardError: standardError,
                             sampleCount: series.count,
                             span: span))
    }

    /// Index of the sample immediately after the last large step down, or nil if the
    /// series never falls off a cliff.
    static func firstIndexAfterLastCliff(in series: [BurnSample]) -> Int? {
        var found: Int?
        for i in 1..<max(series.count, 1) {
            if series[i].percent - series[i - 1].percent <= -cliffDrop { found = i }
        }
        return found
    }

    // MARK: - Projection

    /// Where the current trend lands, or why it cannot be said.
    ///
    /// `percent` is taken from the latest probe rather than from the fit's intercept, so
    /// the projection starts from the same number the ring is showing. It inherits that
    /// number's ±0.5pp of rounding, which at 10pp/hour is about ±3 minutes — small
    /// against the slope's own uncertainty, and not worth trading UI consistency for.
    static func project(percent: Double,
                        resetAt: Date?,
                        history: [BurnSample],
                        now: Date = Date()) -> Projection {
        guard percent < 100 else { return .spent }
        guard let resetAt, resetAt > now else { return .unknown(.noWindow) }

        let rate: Rate
        switch self.rate(from: history, now: now) {
        case .success(let r): rate = r
        case .failure(let blocker): return .unknown(blocker)
        }
        guard rate.isRising else { return .notRising(rate) }

        let remaining = 100 - percent
        let at = now.addingTimeInterval(remaining / rate.perHour * 3600)
        guard at > now else { return .notRising(rate) }
        if at >= resetAt { return .resetsFirst(rate) }

        // `isRising` guarantees the lower bound is positive, so neither division blows
        // up — but it can be very small, which is what makes `latest` run long. Clamping
        // it to the reset is the honest ceiling: beyond that the window has rolled and
        // the question no longer applies.
        let fastest = rate.perHour + confidenceZ * rate.standardError
        let slowest = rate.perHour - confidenceZ * rate.standardError
        let earliest = now.addingTimeInterval(remaining / fastest * 3600)
        let latest = min(now.addingTimeInterval(remaining / slowest * 3600), resetAt)

        return .exhausts(at: at, earliest: earliest, latest: max(latest, at), rate: rate)
    }
}

// MARK: - Wording
//
// One place, so the panel, the right-click menu and `--print-usage` can never disagree
// about what the same projection means. They differ only in how much of the working they
// have room to show — and the working matters: an estimate that shows its evidence is much
// easier to disbelieve when it deserves it.

extension BurnRate.Projection {
    /// Short enough for the 440pt panel, and never a time unless a time is warranted.
    var headline: String {
        switch self {
        case .exhausts(let at, _, _, _): return "full by \(Format.time(at))"
        case .resetsFirst:               return "resets before you run out"
        case .notRising:                 return "not on track to run out"
        case .spent:                     return "window is spent"
        case .unknown(let blocker):
            switch blocker {
            case .noSamples, .tooFewSamples: return "need more readings"
            case .tooShortSpan:              return "measuring…"
            case .stale:                     return "trend too old to trust"
            case .noWindow:                  return "no active window"
            }
        }
    }

    /// "±9m". Floored at a minute so it never reads "±under a minute".
    var marginText: String? {
        uncertainty.map { "±" + Format.duration(max($0, 60)) }
    }

    /// "+15.0%/h", signed so a window draining backwards reads as such. One decimal below
    /// 10 because the difference between 2 and 3 points an hour is the difference between
    /// comfortable and not.
    var rateText: String? {
        rate.map {
            let magnitude = abs($0.perHour)
            let value = magnitude < 10 ? String(format: "%.1f", magnitude)
                                      : String(format: "%.0f", magnitude)
            return "\($0.perHour < 0 ? "−" : "+")\(value)%/h"
        }
    }

    /// For the right-click menu: the claim, its margin, and the rate behind it.
    var oneLine: String {
        [headline, marginText, rateText].compactMap { $0 }.joined(separator: " · ")
    }

    /// For `--print-usage`, where there is room for the whole basis: the interval, the
    /// slope's own standard error, and how many readings over how long produced it.
    func summary() -> String {
        let interval: String? = {
            guard case .exhausts(_, let earliest, let latest, _) = self else { return nil }
            return "between \(Format.time(earliest)) and \(Format.time(latest))"
        }()
        let evidence = rate.map {
            String(format: "%d readings over %@, slope ±%.1f%%/h",
                   $0.sampleCount, Format.duration($0.span), $0.standardError)
        }
        return [headline, interval, rateText, evidence]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
