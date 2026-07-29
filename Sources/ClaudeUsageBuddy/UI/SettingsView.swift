import SwiftUI

/// Calibration is the only thing here that affects accuracy.
///
/// Anthropic doesn't publish a token cap for the rolling session window, so the only
/// way to turn an exact token count into a trustworthy percentage is to anchor it to
/// a number read off `/usage`.
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    var onRecalibrate: () -> Void

    @State private var allowanceText: String = ""
    @State private var showGauge: Bool = Settings.showHairlineGauge
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Calibration").font(.headline)
                    Text(store.snapshot.isEstimated
                         ? "Not calibrated yet — the percentage is measured against a placeholder allowance and should not be trusted."
                         : "Calibrated from \(Settings.calibrationSamples) reading\(Settings.calibrationSamples == 1 ? "" : "s") of /usage. Recalibrate any time it drifts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(store.snapshot.isEstimated ? "Calibrate…" : "Recalibrate…") {
                            onRecalibrate()
                        }
                        Spacer()
                    }
                }
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Token allowance").font(.headline)
                    Text("Set directly if you already know your limit.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("tokens", text: $allowanceText).frame(width: 160)
                        Button("Save") { saveAllowance() }
                        Spacer()
                        Text(Format.compact(Settings.allowance))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(6)
            }

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

            Text("Everything is read from ~/.claude transcripts already on this Mac. No network access, no keychain, no credentials.")
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
        .frame(width: 460, height: 520)
        .onAppear { allowanceText = String(Settings.allowance) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Claude Usage Buddy").font(.title2.weight(.semibold))
            Text("Current window: \(Format.exact(store.snapshot.used)) tokens · \(String(format: "%.1f", store.snapshot.percent))%")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func saveAllowance() {
        let digits = allowanceText.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return }
        store.setAllowance(value)
        allowanceText = String(value)
        note = nil
    }
}
