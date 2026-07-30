import SwiftUI

/// Which of the three detail sections the panel is currently showing.
///
/// The model split, the burn rate and the trailing week were built in parallel and each
/// grew the panel on its own, taking it to 431pt — 44% of a 982pt screen. Stacking them
/// was never the right answer: you open this panel to answer one question, and the other
/// two sections are just noise around it. They share one slot instead.
///
/// What does *not* get a tab is the session state itself — tokens, percentage and reset
/// stay visible in every mode, because those are the numbers you opened the panel for
/// and hiding one behind a click would defeat the point of a hover UI.
enum PanelTab: String, CaseIterable, Codable {
    case models
    case rate
    case week

    var title: String {
        switch self {
        case .models: return "Models"
        case .rate:   return "Rate"
        case .week:   return "Week"
        }
    }
}

/// Small segmented control, sized for the panel footer rather than for a settings sheet.
///
/// Hand-rolled instead of `Picker(.segmented)`: the system control brings ~28pt of
/// chrome and a light material that fights the near-black panel, and the whole exercise
/// here is reclaiming vertical space.
struct PanelTabBar: View {
    let selection: PanelTab
    var onSelect: (PanelTab) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let active = tab == selection
                Button {
                    onSelect(tab)
                } label: {
                    Text(tab.title)
                        .font(.system(size: 10, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.primaryText : Theme.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.white.opacity(active ? 0.13 : 0.0))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
