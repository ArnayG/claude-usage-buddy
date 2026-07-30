import SwiftUI

/// Stacked bar showing which models the window's new tokens came from.
///
/// The share is of *observed tokens*, never of the rate limit — hence the "of new
/// tokens" in the label rather than a bare percentage that could be mistaken for the
/// ring's. `/usage` reports one session figure with no breakdown, and the models do not
/// draw on the limit at the same rate, so a per-model percentage of the limit would be
/// fabricated. This bar therefore never mentions the limit.
struct ModelSplitBar: View {
    let models: [ModelUsage]

    /// Past four slices the legend stops fitting across 396pt of panel body, so the
    /// tail is grouped into "Other" rather than dropped.
    private let maxSegments = 4
    private let barHeight: CGFloat = 9
    /// Hairline gap, so two adjacent slices read as two slices rather than a gradient.
    private let gap: CGFloat = 1.5
    /// Floor for any non-zero slice. Measured over a real window here the split ran
    /// 99.3% Opus / 0.7% Sonnet — at 396pt wide the minority model is a 2.7pt sliver,
    /// and a rounding error away from disappearing. Without a floor the bar would show
    /// a single flat colour and imply the other model was never used.
    private let minSegment: CGFloat = 5

    private var shown: [ModelUsage] { ModelUsage.capped(models, to: maxSegments) }
    private var total: Int { models.reduce(0) { $0 + $1.used } }

    /// Bar slot then legend slot, both always present. An empty window fills them with
    /// placeholders rather than collapsing the section: the panel is a fixed height, and
    /// a section that appears when the first token lands would jolt everything below it.
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            bar
            legend
        }
    }

    @ViewBuilder private var bar: some View {
        if total > 0 {
            GeometryReader { geo in
                let widths = segmentWidths(across: geo.size.width)
                HStack(spacing: gap) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, model in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(Theme.modelColour(for: model.id))
                            .frame(width: max(widths[index], 0))
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
            }
            .frame(height: barHeight)
        } else {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(height: barHeight)
        }
    }

    @ViewBuilder private var legend: some View {
        if total == 0 {
            // Usually the first seconds of a fresh window.
            Text("nothing in this window yet")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
        } else {
            populatedLegend
        }
    }

    private var populatedLegend: some View {
        HStack(spacing: 11) {
            ForEach(shown) { model in
                HStack(spacing: 4.5) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Theme.modelColour(for: model.id))
                        .frame(width: 7, height: 7)

                    Text(model.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primaryText.opacity(0.88))

                    Text(shareText(model))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        // Four long names can overrun on a narrow build; shrink rather than clip, so a
        // slice is never left in the bar with no label to explain it.
        .minimumScaleFactor(0.75)
    }

    /// "99%" / "<1%". A slice rounding to 0% still has to say it is not zero, or the
    /// legend contradicts the bar's visible sliver.
    private func shareText(_ model: ModelUsage) -> String {
        let share = model.share(of: total) * 100
        if share >= 99.5 && model.used < total { return ">99%" }
        if share < 1 { return share > 0 ? "<1%" : "0%" }
        return String(format: "%.0f%%", share)
    }

    /// Proportional widths, with every non-zero slice floored at `minSegment`.
    ///
    /// The floor is paid for by the slices that have room to give, in proportion to how
    /// much room that is — so a dominant slice loses a few points and the rest of the
    /// bar keeps its relative shape.
    private func segmentWidths(across total: CGFloat) -> [CGFloat] {
        let shares = shown.map { CGFloat($0.share(of: self.total)) }
        let count = shares.count
        guard count > 0 else { return [] }

        let available = total - gap * CGFloat(count - 1)
        guard available > 0 else { return Array(repeating: 0, count: count) }
        // If the floors alone would overflow the bar, honour proportion instead: a bar
        // that lies about the shares is worse than one with a slice too thin to see.
        guard minSegment * CGFloat(count) <= available else {
            return shares.map { available * $0 }
        }

        var widths = shares.map { max(available * $0, minSegment) }
        let overshoot = widths.reduce(0, +) - available
        guard overshoot > 0 else { return widths }

        let surplus = widths.map { max($0 - minSegment, 0) }
        let pool = surplus.reduce(0, +)
        guard pool > 0 else { return widths }
        for i in widths.indices { widths[i] -= overshoot * surplus[i] / pool }
        return widths
    }
}
