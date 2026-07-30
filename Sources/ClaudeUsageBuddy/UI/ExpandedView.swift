import SwiftUI

/// Which of the three detail views the panel is showing.
///
/// The session numbers — percentage, tokens, and when it resets — are always on screen;
/// only the supporting detail rotates. Stacking all three vertically had grown the panel
/// to 431pt, 44% of a 982pt display, which is too much real estate to hand a hover.
enum PanelTab: String, CaseIterable {
    case models, rate, week

    var label: String {
        switch self {
        case .models: return "Models"
        case .rate:   return "Rate"
        case .week:   return "Week"
        }
    }
}

/// The hover panel.
///
/// Always visible: the ring, the token count, and the reset countdown — the reset in
/// particular because it is the one fact that decides whether to keep working now, and
/// burying it behind a tab would defeat the point.
///
/// Everything else lives in a fixed-height detail area under a segmented control. Fixed
/// height matters: the window frame is set by `NotchGeometry.expandedSize`, so a detail
/// view that changed height would either clip or leave a gap rather than resize.
struct ExpandedView: View {
    let snapshot: UsageSnapshot
    /// Ticks once a second so the countdown stays live.
    let now: Date
    /// Where the burn rate lands, as of the last probe. See `BurnRate`.
    var projection: BurnRate.Projection = .unknown(.noSamples)
    var isProbing: Bool = false
    @Binding var tab: PanelTab
    var onRefresh: () -> Void
    var onSettings: () -> Void = {}
    var onToggleLogin: () -> Void = {}
    var onQuit: () -> Void = {}

    /// Height of the physical cutout; content must clear it.
    private let notchInset: CGFloat = 32
    /// The detail area is sized once, for the tallest of the three views.
    private let detailHeight: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: notchInset)

            header

            tabStrip
                .padding(.top, 11)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.top, 7)

            detail
                .frame(height: detailHeight, alignment: .topLeading)
                .padding(.top, 8)

            Spacer(minLength: 4)
            footer
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // No outline: a light stroke traced the whole silhouette, including the
        // edges meeting the notch, and read as a halo separating panel from cutout.
        .background(NotchPanelShape().fill(Theme.panel))
    }

    /// Ring, token count, reset, buddy — the parts that never rotate away.
    ///
    /// The ring is 60pt rather than 84 and the buddy 64×56 rather than 88×77. 64×56 is
    /// deliberate: the sprite is 16×14 cells, so those dimensions land on exactly 4pt
    /// per cell and stay pixel-crisp instead of blurring on a fractional grid.
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            RingGauge(fraction: snapshot.fraction, percent: snapshot.percent,
                      lineWidth: 6, numberSize: 17, unitSize: 8)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 2) {
                Label2("NEW TOKENS")

                Text(Format.exact(snapshot.used))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Reset folded in here rather than given its own row: it is a single
                // short phrase, and a whole row for it was 44pt of the old height.
                HStack(spacing: 4) {
                    Text(resetCountdown)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText.opacity(0.85))
                        .monospacedDigit()
                    Text(resetTail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            BuddyView(fraction: snapshot.fraction)
                .frame(width: 64, height: 56)
        }
    }

    /// Segmented control. Plain capsules rather than `Picker`: the panel is a
    /// non-activating window, and a system segmented control renders its selection with
    /// accent-colour vibrancy that fights the flat near-black here.
    private var tabStrip: some View {
        HStack(spacing: 5) {
            ForEach(PanelTab.allCases, id: \.self) { candidate in
                Button { tab = candidate } label: {
                    Text(candidate.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(candidate == tab
                                         ? Theme.primaryText
                                         : Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule().fill(Color.white.opacity(candidate == tab ? 0.15 : 0.05))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .models:
            VStack(alignment: .leading, spacing: 5) {
                Label2("SHARE OF NEW TOKENS")
                ModelSplitBar(models: snapshot.byModel)
            }
        case .rate:
            projectionRow
        case .week:
            WeeklySection(snapshot: snapshot, now: now)
        }
    }

    /// The projection. Labelled "AT THIS RATE" because that is exactly what it is — an
    /// extrapolation of the last half hour, not a fact — and it says so before it says a
    /// time. When the trend cannot support a time this row states why instead; see
    /// `BurnRate` for the gates.
    private var projectionRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Label2("AT THIS RATE")
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(projection.headline)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(projectionColour)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // The margin is part of the claim, not a footnote to it: where the
                    // slope only just clears its own noise this can be wider than the
                    // estimate is early, and hiding that would oversell it.
                    if let margin = projection.marginText {
                        Text(margin)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Label2("BURN")
                Text(projection.rateText ?? "—")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            }
        }
    }

    /// Warmer as the projected time closes in, on the same green→amber→red logic the
    /// ring uses. Anything that is not an actual projection stays quiet: a muted "need
    /// more readings" should not compete with the number it is declining to give.
    private var projectionColour: Color {
        switch projection {
        case .exhausts(let at, _, _, _):
            let remaining = at.timeIntervalSince(now)
            if remaining < 45 * 60 { return Theme.critical }
            if remaining < 2 * 3600 { return Theme.warn }
            return Theme.primaryText
        case .spent:      return Theme.critical
        case .resetsFirst, .notRising: return Theme.secondaryText
        case .unknown:    return Theme.tertiaryText
        }
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
                Text(isProbing ? "Checking…" : "Refresh")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText.opacity(0.9))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.white.opacity(0.11)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Visible on purpose. With no Dock icon and no room in the menu bar for a
            // status item, a right-click-only menu would leave no discoverable way to
            // reach Settings or quit the app.
            Menu {
                Button("Settings…", action: onSettings)
                Button(LoginItem.isEnabled ? "Disable launch at login" : "Launch at login",
                       action: onToggleLogin)
                Divider()
                Button("Quit Claude Usage Buddy", action: onQuit)
            } label: {
                Text("•••")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Theme.primaryText.opacity(0.9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(Color.white.opacity(0.11)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var statusColour: Color {
        if snapshot.isUnverified || snapshot.probeError != nil { return Theme.warn.opacity(0.7) }
        return snapshot.isStale(now: now) ? Theme.warn.opacity(0.55) : Theme.ok
    }

    /// Says where the number came from and how fresh it is, rather than implying a
    /// live feed. The probe runs every few minutes, not continuously.
    private var statusText: String {
        if isProbing { return "asking /usage…" }
        if let error = snapshot.probeError, snapshot.isUnverified { return "/usage — \(error)" }
        guard let probedAt = snapshot.probedAt else { return "reading /usage…" }
        let age = now.timeIntervalSince(probedAt)
        let suffix = snapshot.probeError == nil ? "" : " · retrying"
        if age < 75 { return "from /usage · just now" + suffix }
        return "from /usage · \(Format.duration(age)) ago" + suffix
    }

    private var resetCountdown: String {
        guard let at = snapshot.resetAt else { return "—" }
        return Format.duration(max(at.timeIntervalSince(now), 0))
    }

    /// Reads as "1h 20m · resets 10:49 PM".
    private var resetTail: String {
        guard let at = snapshot.resetAt else { return "no active window" }
        return "· resets \(Format.time(at))"
    }
}

/// Small all-caps section label. Shared with the weekly section so the two halves of
/// the panel keep one typographic voice.
struct Label2: View {
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
    /// Defaults are the 84pt session gauge. The weekly ring, when a plan actually
    /// reports a weekly percentage, reuses this at roughly half the size — the two
    /// gauges must read as the same instrument, so they share one implementation
    /// rather than a lookalike.
    var lineWidth: CGFloat = 8
    var numberSize: CGFloat = 23
    var unitSize: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(
                    Theme.gauge(for: fraction),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.gauge(for: fraction).opacity(0.45), radius: 5)

            VStack(spacing: -1) {
                Text(percentText)
                    .font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: unitSize, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .animation(.easeOut(duration: 0.5), value: fraction)
    }

    private var percentText: String {
        percent < 10 ? String(format: "%.1f", percent) : String(format: "%.0f", percent)
    }
}
