import SwiftUI

/// Calibration is the important control here.
///
/// Anthropic does not publish a token cap for the rolling session window, so the
/// only way to turn a token count into a trustworthy percentage is to anchor it to
/// a number the user can read off `/usage`. Enter that percentage and the allowance
/// is back-solved from the tokens currently counted.
struct SettingsView: View {
    @ObservedObject var store: UsageStore

    @State private var allowanceText: String = ""
    @State private var observedPercent: String = ""
    @State private var useServer: Bool = Settings.useServerUsage
    @State private var showGauge: Bool = Settings.showHairlineGauge
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Calibrate from /usage")
                        .font(.headline)
                    Text("Run `/usage` in any Claude Code session and type the session percentage it reports. The allowance is recalculated from the \(Format.exact(store.snapshot.used)) tokens counted in the current window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        TextField("e.g. 17", text: $observedPercent)
                            .frame(width: 90)
                        Text("%").foregroundStyle(.secondary)
                        Button("Calibrate") { calibrate() }
                            .disabled(Double(observedPercent) == nil || store.snapshot.used == 0)
                        Spacer()
                    }
                }
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Token allowance")
                        .font(.headline)
                    HStack {
                        TextField("tokens", text: $allowanceText)
                            .frame(width: 160)
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

                Toggle("Use live usage from Anthropic", isOn: $useServer)
                    .onChange(of: useServer) { _, v in
                        Settings.useServerUsage = v
                        store.refresh()
                    }
                Text("Reads the Claude Code OAuth token from your keychain and fetches the real percentage, then works backwards to your token allowance. The endpoint is undocumented and may stop working after a Claude Code update — the local estimate takes over whenever it does, using the last allowance learned here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 460, height: 570)
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

    private func calibrate() {
        guard let pct = Double(observedPercent) else { return }
        store.calibrate(observedPercent: pct)
        allowanceText = String(Settings.allowance)
        note = "Allowance set to \(Format.exact(Settings.allowance)) tokens."
    }

    private func saveAllowance() {
        let digits = allowanceText.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return }
        store.setAllowance(value)
        allowanceText = String(value)
        note = nil
    }
}
