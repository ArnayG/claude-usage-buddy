# Claude Usage Buddy

Hover the camera notch on a MacBook Pro and a panel drops down showing how much of
your current Claude session window you've used and when it resets.

```
        ╭─────────────────────────╮
        │        ▓▓ notch ▓▓      │
   ╭────┴─────────────────────────┴────╮
   │   ╭───╮   TOKENS USED             │
   │   │32%│   70,870,879              │
   │   ╰───╯   of 221M allowed         │
   │   ─────────────────────────────   │
   │   RESETS IN            AT         │
   │   1h 59m               9:39 PM    │
   │   ● live from Anthropic           │
   ╰───────────────────────────────────╯
```

Four readouts, by design: **tokens used**, **allowance**, **percentage**, **reset time**.

When you're not hovering there's nothing to see but a hairline gauge under the notch
that shifts green → amber → red. The notch itself is a physical cutout with no pixels
behind it, so the gauge lives in the few points of real screen just below.

## Install

Requires macOS 14+. Xcode is *not* needed — Command Line Tools are enough.

```sh
make install     # builds, bundles, ad-hoc signs, copies to /Applications, launches
```

Other targets: `make run` (run from `dist/`), `make bundle`, `make clean`.

The app is an accessory (`LSUIElement`) — no Dock icon. It also installs a menu bar
item, which is both a keyboard-reachable alternative to hovering and the fallback UI
on Macs without a notch.

Headless readout, useful for sanity checks:

```sh
dist/ClaudeUsageBuddy.app/Contents/MacOS/ClaudeUsageBuddy --print-usage
```

## How usage is calculated

Every assistant response Claude Code writes to `~/.claude/projects/**/*.jsonl`
carries a `message.usage` block with exact token counts. Those files are tailed
incrementally from a stored byte offset and de-duplicated by record `uuid`, which
also cancels out the overlap between a session transcript and the per-subagent
transcripts written next to it. Usage is aggregated **account-wide** across every
project, because the rate limit is account-wide.

The session window is reconstructed the way Claude describes it: a block starts at
the top of the hour containing its first request and runs five hours; a five-hour
gap opens a new block. Reset time is `blockStart + 5h`.

### About the percentage

Token counts are exact. The percentage needs a denominator that Anthropic doesn't
publish — there's no token cap documented for the rolling session window, and it
varies by plan and tier. So the app gets it one of two ways.

**Live usage** (on by default). Reads the Claude Code OAuth token from your keychain
and calls `GET /api/oauth/usage` — the same endpoint Claude Code itself uses to render
`/usage`:

```jsonc
{ "five_hour": { "utilization": 32.0, "resets_at": "2026-07-29T01:39:59+00:00" },
  "limits": [ { "kind": "session", "percent": 32, "resets_at": "...", "is_active": true } ] }
```

The server's job is **calibration, not display**. An authoritative percentage plus an
exact local token count implies the allowance — so the app works backwards to your real
allowance, and from then on computes the percentage itself, continuously, from
transcripts.

That indirection is deliberate. **The usage endpoint is rate limited** (polling it every
15s earns a `429` within the hour), so it can only be called every few minutes. A stored
server percentage would sit frozen between calls while your token count kept climbing.
Calibrating instead means the number on screen updates every refresh *and* agrees with
Anthropic. Calls are floored at 5 minutes apart, with exponential backoff to an hour on
`429`; the panel keeps working throughout, it just stops re-verifying for a while.

Utilisation comes back as a whole percent, so each sample carries ~1pp of quantisation
error; the implied allowance is smoothed rather than overwritten to stop it wandering.

This endpoint is **not** part of Anthropic's public API and can change on any Claude
Code update. Every failure path falls back silently to the local estimate, which by
then has a real allowance to work from.

**Manual calibration.** If you'd rather not touch the keychain, turn live usage off,
run `/usage` in any session, and type the percentage into Settings & Calibration. The
allowance is back-solved the same way. Until the app has a real number from either
route, the panel shows an amber dot and the word *estimated*.

> The local five-hour block math is a good approximation but not authoritative: it
> only sees transcripts on this machine, so usage from claude.ai or another Mac is
> invisible to it, and the window start it infers can be off. Prefer live usage.

**Keychain access.** macOS prompts the first time the app reads the token — click
*Always Allow*.

That grant is bound to the app's *designated requirement*. Under ad-hoc signing
(`codesign -s -`) the requirement is derived from the binary hash, so every rebuild
invalidates it and the prompt returns. `make signing-identity` creates a stable
self-signed certificate in your login keychain, which pins the requirement to the
certificate instead:

```
designated => identifier "com.arnay.claude-usage-buddy" and certificate leaf = H"29b5…"
```

Grant it once and it survives every subsequent rebuild. The Makefile picks the identity
up automatically and falls back to ad-hoc if it isn't there.
`scripts/remove-signing-identity.sh` reverses it.

Note that raw totals are dominated by cache reads (~97% of tokens in practice), which
are far cheaper than output tokens. Calibration absorbs that skew for a typical usage
mix; the per-type weights are constants in `Settings.swift` if you want to tune them.

## Layout

```
Sources/ClaudeUsageBuddy/
├── App.swift              entry point, menu bar item, --print-usage
├── Notch/
│   ├── NotchGeometry.swift   derives the notch rect at runtime
│   ├── NotchWindow.swift     borderless panel above the menu bar
│   └── NotchController.swift hover state machine
├── UI/                    Collapsed / Expanded / Settings / Theme
├── Usage/                 scanner, 5h block math, store, keychain, server client
└── Support/LoginItem.swift
```

Notch geometry is derived from `NSScreen.auxiliaryTopLeftArea` /
`auxiliaryTopRightArea` rather than hardcoded, so docking, external displays, and
notch-less Macs all behave. The panel pins to the built-in screen and hides itself
when the menu bar does (native fullscreen).

## Privacy

Nothing leaves your machine unless you explicitly enable live usage. Only token
counts and timestamps are read from transcripts — never message content. The OAuth
token is read on demand and never written to disk.

## License

MIT
