import SwiftUI

/// The trailing-week readout at the bottom of the hover panel.
///
/// This view has two shapes, and which one it takes is decided by whether the CLI gave
/// us a real number — never by what would look better.
///
/// **With a weekly percentage** (`/usage` printed `Current week …: N% used`): a ring,
/// matching the session gauge, plus the 7-day token volume beside it.
///
/// **Without one** (the common case, and the case on the account this was built
/// against): the token volume and request counts only, labelled as a *total* rather
/// than a share, with a line saying outright that no weekly limit was reported.
///
/// The absent-percentage branch is the whole point of the design. `/usage` publishes no
/// weekly denominator on most plans, and the app cannot see one anywhere else — so
/// there is no honest way to draw a weekly ring. An earlier version of this project
/// shipped a scheme that *inferred* the session percentage from a guessed allowance;
/// it was wrong in the field and had to be deleted. Showing a ring here filled from
/// `weekly tokens ÷ some plausible number` would repeat that mistake with a worse
/// excuse, because at least the session limit is a real quantity Anthropic states.
/// A missing gauge is information. A confident wrong gauge is not.
struct WeeklySection: View {
    let snapshot: UsageSnapshot
    /// Ticks once a second, so a weekly countdown stays live like the session one.
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let fraction = snapshot.weeklyFraction, let percent = snapshot.weekly.percent {
                measured(fraction: fraction, percent: percent)
            } else {
                volumeOnly
            }

            Text(footnote)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - With a real weekly percentage

    private func measured(fraction: Double, percent: Double) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Half the session gauge's diameter: it is the secondary limit, and the
            // hierarchy should say so before the label does.
            RingGauge(fraction: fraction, percent: percent,
                      lineWidth: 5.5, numberSize: 15, unitSize: 7.5)
                .frame(width: 52, height: 52)

            // Two lines only, with the request counts demoted to the footnote. Three
            // stacked lines beside the ring overflowed the panel and squeezed the
            // session section above it, and the counts are the least useful figure
            // here — the percentage is the answer, they are colour.
            VStack(alignment: .leading, spacing: 3) {
                Label2(weeklyLimitLabel)
                volumeLine
            }

            Spacer(minLength: 8)

            if let reset = snapshot.weekly.resetAt {
                VStack(alignment: .trailing, spacing: 3) {
                    Label2("RESETS IN")
                    Text(Format.longDuration(max(reset.timeIntervalSince(now), 0)))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
            }
        }
    }

    /// "THIS WEEK" / "THIS WEEK · OPUS" — a per-model sub-limit is named, so a 90%
    /// Opus figure is never read as 90% of everything.
    private var weeklyLimitLabel: String {
        guard let label = snapshot.weekly.limitLabel else { return "THIS WEEK" }
        return "THIS WEEK · \(label.uppercased())"
    }

    // MARK: - Volume only

    private var volumeOnly: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label2("LAST 7 DAYS")
                volumeLine
            }

            Spacer(minLength: 8)

            if let counts = countsLine {
                VStack(alignment: .trailing, spacing: 3) {
                    Label2("ACTIVITY")
                    Text(counts)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Shared pieces

    /// Compact rather than exact, unlike the session headline. Seven days of work runs
    /// to nine digits, and a number that wide both crowds the row and stops being
    /// legible as a quantity — the week is a sense of scale, the window is a figure you
    /// watch move.
    private var volumeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Format.compact(snapshot.weeklyUsed))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
                .monospacedDigit()
            Text("new tokens")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
    }

    /// "1,361 requests · 7 sessions", or as much of it as `/usage` printed.
    private var countsLine: String? {
        var parts: [String] = []
        if let r = snapshot.weekly.requests { parts.append("\(Format.exact(r)) requests") }
        if let s = snapshot.weekly.sessions { parts.append("\(Format.exact(s)) sessions") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Says where the figures came from and, when there is no percentage, that the
    /// absence is Anthropic's rather than a bug in the app. Users comparing this panel
    /// to the session ring above will notice the missing gauge and deserve the reason.
    private var footnote: String {
        if snapshot.weekly.hasPercent {
            guard let counts = countsLine else {
                return "Weekly limit from /usage · token count is this Mac only"
            }
            return "Weekly limit from /usage · this Mac: \(counts)"
        }
        if snapshot.isUnverified {
            return "7-day total from this Mac · checking /usage for a weekly limit…"
        }
        return "7-day total from this Mac · /usage reports no weekly limit, so no percentage"
    }
}
