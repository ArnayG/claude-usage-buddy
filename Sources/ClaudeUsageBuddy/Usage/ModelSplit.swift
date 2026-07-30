import Foundation

/// Which model produced a batch of tokens, resolved from the raw `message.model`
/// string a transcript records.
///
/// The raw ids are not fit to show anyone — `claude-haiku-4-5-20251001` — and they
/// change with every release, so the mapping is *derived* rather than tabulated. A
/// hardcoded table of ids would silently drop the next model Anthropic ships, and that
/// is the one failure mode that matters here: a split that quietly stops summing to the
/// headline number is worse than no split at all.
struct ModelIdentity: Hashable {
    /// Stable grouping key: the family word, lowercased — `opus`, `sonnet`, `haiku`.
    let key: String
    /// What the panel shows — `Opus`.
    let name: String

    /// Records written before a model was chosen, or with the field absent.
    static let unknown = ModelIdentity(key: "unknown", name: "Unknown")

    /// Vendor scaffolding that wraps the family word depending on how Claude Code is
    /// routed. Bedrock ids look like `us.anthropic.claude-sonnet-4-5-v1:0`, Vertex ids
    /// like `claude-opus-4@20250514`, and `-latest` aliases turn up in configs.
    private static let scaffolding: Set<String> = [
        "claude", "anthropic", "us", "eu", "apac", "global",
        "bedrock", "vertex", "models", "publishers", "latest",
    ]

    /// Reduces a model id to its family word.
    ///
    /// Every id seen so far carries the family as a bare alphabetic run, but not in a
    /// fixed position: `claude-opus-5` leads with it, `claude-haiku-4-5-20251001` pads
    /// it with a date, and the older `claude-3-5-sonnet-20241022` puts the version
    /// first. Taking the first alphabetic run that is not vendor scaffolding handles all
    /// three shapes and, more importantly, will handle a shape nobody has written yet.
    ///
    /// `<synthetic>` — Claude Code's marker for locally generated messages — falls out
    /// of the same rule as "Synthetic". Those records carry no tokens, so the scanner
    /// drops them before they reach here, but the fallback is honest if that changes.
    static func resolve(_ raw: String?) -> ModelIdentity {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .unknown
        }

        let runs = raw.lowercased().split { !$0.isLetter && !$0.isNumber }
        let family = runs.first { run in
            run.allSatisfy(\.isLetter) && !scaffolding.contains(String(run))
        }

        guard let family else {
            // Nothing recognisable survived. Show the id itself, clipped, so the slice
            // stays attributable — an unexplained slice is worse than an ugly label.
            let label = raw.count > 16 ? raw.prefix(15) + "…" : raw
            return ModelIdentity(key: raw.lowercased(), name: String(label))
        }
        return ModelIdentity(key: String(family),
                             name: family.prefix(1).uppercased() + family.dropFirst())
    }
}

/// One model family's contribution to the tokens observed inside a window.
struct ModelUsage: Identifiable, Equatable {
    let identity: ModelIdentity
    let counts: TokenCounts

    var id: String { identity.key }
    var name: String { identity.name }

    /// New tokens, matching the headline — see `TokenCounts.fresh`. Using the same
    /// basis is the whole point: the slices have to add up to the number above them.
    var used: Int { counts.fresh }
}

extension ModelUsage {
    /// Key for the grouped tail, so it can never collide with a real family word.
    static let otherKey = "·other"

    /// Groups entries by model family, largest first.
    ///
    /// These are shares of the tokens **this Mac observed**, never shares of the rate
    /// limit. `/usage` is the only authoritative source of a percentage and it reports a
    /// single session figure with no per-model breakdown; slicing that figure by local
    /// token share would invent numbers, because the models do not draw on the limit at
    /// the same rate and transcripts cannot see usage from claude.ai or another machine.
    ///
    /// `start` is the authoritative window start the rest of the app already uses, so
    /// the split covers exactly the entries behind the headline count. Nil means no
    /// window is known yet, and an empty split is the honest answer.
    static func split(_ entries: [UsageEntry], since start: Date?) -> [ModelUsage] {
        guard let start else { return [] }

        var byKey: [String: (identity: ModelIdentity, counts: TokenCounts)] = [:]
        for entry in entries where entry.timestamp >= start {
            let identity = ModelIdentity.resolve(entry.model)
            var bucket = byKey[identity.key] ?? (identity, TokenCounts())
            bucket.counts += entry.counts
            byKey[identity.key] = bucket
        }

        return byKey.values
            .map { ModelUsage(identity: $0.identity, counts: $0.counts) }
            .filter { $0.used > 0 }
            // Ties break on name so the ordering — and therefore the colour each model
            // gets — cannot flicker between two equal slices on successive rescans.
            .sorted { $0.used == $1.used ? $0.name < $1.name : $0.used > $1.used }
    }

    /// Collapses everything past `limit` slices into one grey "Other".
    ///
    /// Grouping rather than truncating, because the slices must keep summing to the
    /// headline: a dropped tail would leave the bar quietly short of 100%.
    static func capped(_ models: [ModelUsage], to limit: Int) -> [ModelUsage] {
        guard limit > 0, models.count > limit else { return models }

        let head = models.prefix(limit - 1)
        let tail = models.dropFirst(limit - 1)
        let merged = ModelUsage(
            identity: ModelIdentity(key: otherKey, name: "Other (\(tail.count))"),
            counts: tail.reduce(TokenCounts()) { $0 + $1.counts }
        )
        return Array(head) + [merged]
    }

    /// Fraction of `total`, clamped. Zero total yields zero rather than a NaN that
    /// would propagate into layout maths and collapse the bar.
    func share(of total: Int) -> Double {
        total > 0 ? min(max(Double(used) / Double(total), 0), 1) : 0
    }
}
