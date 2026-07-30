import SwiftUI

/// Preferences only. Accuracy is not configurable any more — the numbers come
/// straight from `claude -p "/usage"`, so there is nothing to tune.
struct SettingsView: View {
    @ObservedObject var store: UsageStore

    @State private var showGauge: Bool = Settings.showHairlineGauge
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show gauge under the notch", isOn: $showGauge)
                    .onChange(of: showGauge) { _, v in Settings.showHairlineGauge = v }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        if !LoginItem.set(v) {
                            launchAtLogin = LoginItem.isEnabled
                            note = "Could not change the login item. Move the app to /Applications and try again."
                        }
                    }
            }

            Text("The percentage and reset time come from `claude -p \"/usage\"` — Claude Code's own answer, refreshed every few minutes. Token counts are read from ~/.claude transcripts. No keychain, no credentials of our own.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note {
                Text(note).font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 460, height: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Claude Usage Buddy").font(.title2.weight(.semibold))
            Text("Current window: \(Format.exact(store.snapshot.used)) tokens · \(Format.percent(store.snapshot.percent))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

}
