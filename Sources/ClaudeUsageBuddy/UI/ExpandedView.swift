import SwiftUI

/// The hover panel. Four readouts, in the order they matter:
/// tokens used → allowance → percentage → reset.
struct ExpandedView: View {
    let snapshot: UsageSnapshot
    /// Ticks once a second so the countdown stays live.
    let now: Date
    var onRefresh: () -> Void

    /// Height of the physical cutout; content must clear it.
    private let notchInset: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: notchInset)

            HStack(alignment: .center, spacing: 18) {
                RingGauge(fraction: snapshot.fraction, percent: snapshot.percent)
                    .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 3) {
                    Label2("TOKENS USED")

                    Text(Format.exact(snapshot.used))
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)

                // 88×77 keeps the sprite's 16:14 ratio at exactly 5.5pt per cell,
                // which lands on whole device pixels at 2×.
                BuddyView(fraction: snapshot.fraction)
                    .frame(width: 88, height: 77)
            }

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.top, 14)
                .padding(.bottom, 11)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label2("RESETS IN")
                    Text(resetCountdown)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Label2("AT")
                    Text(resetClock)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 6)
            footer
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            BottomRoundedRect(radius: Theme.cornerRadius)
                .fill(Theme.panel)
                .overlay(
                    BottomRoundedRect(radius: Theme.cornerRadius)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColour)
                .frame(width: 5, height: 5)

            Text(statusText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)

            Spacer()

            Button(action: onRefresh) {
                Text("Refresh")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText.opacity(0.9))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.white.opacity(0.11)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var statusColour: Color {
        if snapshot.isUnverified || snapshot.probeError != nil { return Theme.warn.opacity(0.7) }
        return snapshot.isStale(now: now) ? Theme.warn.opacity(0.55) : Theme.ok
    }

    /// Says where the number came from and how fresh it is, rather than implying a
    /// live feed. The probe runs every few minutes, not continuously.
    private var statusText: String {
        if let error = snapshot.probeError, snapshot.isUnverified { return "/usage — \(error)" }
        guard let probedAt = snapshot.probedAt else { return "reading /usage…" }
        let age = now.timeIntervalSince(probedAt)
        let suffix = snapshot.probeError == nil ? "" : " · retrying"
        if age < 75 { return "from /usage · just now" + suffix }
        return "from /usage · \(Format.duration(age)) ago" + suffix
    }

    private var subtitle: String { "this 5-hour window" }

    private var resetCountdown: String {
        guard let at = snapshot.resetAt else { return "—" }
        return Format.duration(max(at.timeIntervalSince(now), 0))
    }

    private var resetClock: String {
        guard let at = snapshot.resetAt else { return "no active window" }
        return Format.time(at)
    }
}

/// Small all-caps section label.
private struct Label2: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.tertiaryText)
    }
}

struct RingGauge: View {
    let fraction: Double
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)

            Circle()
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(
                    Theme.gauge(for: fraction),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.gauge(for: fraction).opacity(0.45), radius: 5)

            VStack(spacing: -1) {
                Text(percentText)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .animation(.easeOut(duration: 0.5), value: fraction)
    }

    private var percentText: String {
        percent < 10 ? String(format: "%.1f", percent) : String(format: "%.0f", percent)
    }
}
