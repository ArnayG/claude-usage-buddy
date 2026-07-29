import SwiftUI

/// Shown once on first launch, and reachable afterwards from the menu.
///
/// Two numbers copied out of `/usage` are enough to make everything else exact:
/// the percentage fixes the token allowance, and the reset time pins the current
/// window. Both are optional — skipping just leaves the readout approximate.
struct CalibrationPrompt: View {
    @ObservedObject var store: UsageStore
    var onFinish: () -> Void

    @State private var percentText = ""
    @State private var resetText = ""
    @State private var error: String?

    private var parsedPercent: Double? {
        let cleaned = percentText.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(cleaned), v > 0, v <= 100 else { return nil }
        return v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("One-time setup")
                    .font(.title2.weight(.semibold))
                Text("Your token count is exact, but turning it into a percentage needs to know your plan's limit — and Anthropic doesn't publish one. Copy two numbers from Claude Code and this is accurate from then on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("In any Claude Code session, run:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("/usage")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField("37", text: $percentText).frame(width: 70)
                        Text("%").foregroundStyle(.secondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Session used")
                        Text("the percentage /usage reports")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    TextField("9:39 PM", text: $resetText).frame(width: 100)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Resets at").foregroundStyle(.primary)
                        Text("optional — pins the current window")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Text("Counted so far: \(Format.exact(store.snapshot.used)) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }

            if let error {
                Text(error).font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Skip for now") {
                    Settings.promptedForCalibration = true
                    onFinish()
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedPercent == nil)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func save() {
        guard let percent = parsedPercent else {
            error = "Enter the session percentage from /usage."
            return
        }
        guard store.snapshot.used > 0 else {
            error = "No usage counted yet in this window — try again after a request or two."
            return
        }

        var reset: Date?
        let trimmed = resetText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            guard let parsed = ClockTime.parse(trimmed) else {
                error = "Couldn't read \"\(trimmed)\". Try a form like 9:39 PM or 21:39."
                return
            }
            reset = parsed
        }

        store.calibrate(observedPercent: percent, resetAt: reset)
        Settings.promptedForCalibration = true
        onFinish()
    }
}

/// Parses a wall-clock time like "9:39 PM" or "21:39" into the next time it occurs.
enum ClockTime {
    static func parse(_ text: String, now: Date = Date()) -> Date? {
        let formats = ["h:mm a", "h:mma", "H:mm", "h a", "ha"]
        let normalized = text
            .replacingOccurrences(of: ".", with: "")
            .uppercased()

        for format in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            guard let parsed = f.date(from: normalized) else { continue }

            let cal = Calendar.current
            let hm = cal.dateComponents([.hour, .minute], from: parsed)
            guard var candidate = cal.date(bySettingHour: hm.hour ?? 0,
                                           minute: hm.minute ?? 0,
                                           second: 0,
                                           of: now) else { continue }
            // A reset time is always ahead of now; roll to tomorrow if it reads as past.
            if candidate <= now {
                candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            // Guard against a typo producing a window longer than five hours.
            if candidate.timeIntervalSince(now) > UsageBlock.windowLength { return nil }
            return candidate
        }
        return nil
    }
}
