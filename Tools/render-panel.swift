import AppKit
import SwiftUI

// Renders the expanded panel offscreen to PNGs, at 3× so text and hairlines can be
// judged.
//
// There is no Xcode on the machine this was built on, so no SwiftUI previews and no
// canvas — and taking a screenshot of the real panel needs Screen Recording permission,
// which a headless build cannot ask for. `ImageRenderer` is the way to actually look at
// the layout, and having it in the repo means the states below can be re-checked after
// any change to `ExpandedView` rather than trusted.
//
//   swiftc -O -parse-as-library \
//     Sources/ClaudeUsageBuddy/UI/{Theme,ExpandedView,ModelSplitBar,Buddy}.swift \
//     Sources/ClaudeUsageBuddy/Usage/{UsageModel,ModelSplit}.swift \
//     Sources/ClaudeUsageBuddy/Support/LoginItem.swift \
//     Sources/ClaudeUsageBuddy/Notch/NotchGeometry.swift \
//     Tools/render-panel.swift -o /tmp/render-panel
//   /tmp/render-panel /tmp/panels
//
// The SwiftUI `Menu` in the footer cannot be rendered by `ImageRenderer` and comes out
// as a placeholder box; everything else is faithful.

private func counts(_ fresh: Int) -> TokenCounts {
    // Spread across the three fresh buckets. Only `.fresh` is read here, but keeping a
    // plausible cache-read figure alongside it exercises the same struct the app uses.
    TokenCounts(input: fresh / 3,
                output: fresh / 3,
                cacheCreation: fresh - 2 * (fresh / 3),
                cacheRead: fresh * 80)
}

private func model(_ rawID: String, _ fresh: Int) -> ModelUsage {
    ModelUsage(identity: ModelIdentity.resolve(rawID), counts: counts(fresh))
}

private func snapshot(percent: Double, _ models: [ModelUsage]) -> UsageSnapshot {
    var s = UsageSnapshot()
    s.byModel = models.sorted { $0.used == $1.used ? $0.name < $1.name : $0.used > $1.used }
    s.counts = models.reduce(TokenCounts()) { $0 + $1.counts }
    s.percent = percent
    s.resetAt = Date().addingTimeInterval(80 * 60)
    s.probedAt = Date()
    return s
}

@MainActor
private func render(_ name: String, _ snapshot: UsageSnapshot, into directory: URL) {
    let size = NotchGeometry.expandedSize
    let view = ExpandedView(snapshot: snapshot, now: Date(), onRefresh: {})
        .frame(width: size.width, height: size.height)
        // Magenta surround: shows the panel is not painting outside its own silhouette,
        // and makes the concave top flare visible against something.
        .background(Color(red: 0.55, green: 0, blue: 0.45))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 3

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("render failed: \(name)"); return }

    let url = directory.appendingPathComponent("\(name).png")
    do {
        try png.write(to: url)
        print("wrote \(url.path)  \(rep.pixelsWide)×\(rep.pixelsHigh)")
    } catch {
        print("write failed: \(url.path) — \(error.localizedDescription)")
    }
}

@main
enum RenderPanel {
    @MainActor
    static func main() {
        let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1
                            ? CommandLine.arguments[1] : ".")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The split measured on a real window here: Opus dominant, Sonnet a sliver. This
        // is the case the bar has to survive, and the reason slices have a width floor.
        render("01-dominant", snapshot(percent: 44, [
            model("claude-opus-5", 11_403_566),
            model("claude-sonnet-5", 79_444),
        ]), into: directory)

        // Three families, all substantial.
        render("02-three", snapshot(percent: 62, [
            model("claude-opus-5", 1_800_000),
            model("claude-sonnet-5", 900_000),
            model("claude-haiku-4-5-20251001", 300_000),
        ]), into: directory)

        // Five families: exercises the grouped "Other" tail and the legend's width.
        render("03-grouped", snapshot(percent: 88, [
            model("claude-opus-5", 1_200_000),
            model("claude-sonnet-5", 800_000),
            model("claude-haiku-4-5-20251001", 400_000),
            model("claude-quartet-6-20270101", 120_000),
            model("claude-3-5-sonnet-20241022", 60_000),
        ]), into: directory)

        // Empty window. Must occupy the same height as a populated split, or everything
        // below it jumps the moment the first token lands.
        render("04-empty", snapshot(percent: 0, []), into: directory)

        // 0.02% — well past the point where a proportional slice would be sub-pixel.
        render("05-sliver", snapshot(percent: 18, [
            model("claude-opus-5", 5_000_000),
            model("claude-haiku-4-5-20251001", 1_000),
        ]), into: directory)

        // Ids this build has never seen, to confirm they get a name and a colour rather
        // than being dropped.
        render("06-unknown", snapshot(percent: 30, [
            model("claude-verse-7-20280412", 2_000_000),
            model("<synthetic>", 40_000),
        ]), into: directory)

        print("\nmodel id resolution:")
        for raw in ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001",
                    "claude-3-5-sonnet-20241022", "us.anthropic.claude-sonnet-4-5-v1:0",
                    "claude-opus-4@20250514", "claude-3-5-haiku-latest",
                    "<synthetic>", "claude-latest", "", "weird_thing"] {
            let id = ModelIdentity.resolve(raw.isEmpty ? nil : raw)
            print("  \(raw.isEmpty ? "(nil)" : raw) → key=\(id.key) name=\(id.name)")
        }
    }
}
