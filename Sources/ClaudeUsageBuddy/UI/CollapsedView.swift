import SwiftUI

/// What sits at the notch when you are not hovering.
///
/// The notch itself is a cutout with no pixels, so the only visible element is a
/// hairline gauge in the few points of real screen just below it. It reads as a
/// faint underline on the notch and is the whole point of living up here: usage
/// state with zero interaction.
struct CollapsedView: View {
    let fraction: Double
    let showGauge: Bool

    private let barHeight: CGFloat = 2.5

    var body: some View {
        VStack(spacing: 0) {
            // Transparent stand-in for the cutout — invisible, but it keeps the
            // hover target the full height of the notch.
            Color.clear
            if showGauge {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.07))
                        Capsule()
                            .fill(Theme.gauge(for: fraction))
                            .frame(width: max(geo.size.width * fraction, fraction > 0 ? 3 : 0))
                            .shadow(color: Theme.gauge(for: fraction).opacity(0.6), radius: 2.5)
                    }
                }
                .frame(height: barHeight)
                .padding(.horizontal, 10)
                .padding(.bottom, 1)
                .animation(.easeOut(duration: 0.45), value: fraction)
            }
        }
    }
}
