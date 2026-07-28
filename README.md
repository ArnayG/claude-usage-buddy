# Claude Usage Buddy

Hover the camera notch on a MacBook Pro and a panel drops down showing how much of
your current Claude session window you've used and when it resets.

```
        ╭─────────────────────────╮
        │        ▓▓ notch ▓▓      │
   ╭────┴─────────────────────────┴────╮
   │   ╭───╮   TOKENS USED             │
   │   │21%│   53,068,712              │
   │   ╰───╯   of 250M allowed         │
   │   ─────────────────────────────   │
   │   RESETS IN            AT         │
   │   2h 38m               10:00 PM   │
   │   ● estimated · calibrate         │
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

Token counts are exact. The percentage is not, and the app says so.

Anthropic doesn't publish a token cap for the rolling session window — it varies by
plan and tier — so there's no honest way to look up a denominator. Two ways to get a
real number:

**Calibrate** (recommended). Run `/usage` in any Claude Code session, open
Settings & Calibration, and type the percentage it reports. The allowance is
back-solved from the tokens currently counted, which makes the estimate accurate for
your specific plan. Until you do, the panel shows an amber dot and the word
*estimated*.

**Live usage** (experimental, off by default). Reads the Claude Code OAuth token from
your keychain and fetches the real percentage. This endpoint is undocumented and not
part of Anthropic's public API — it can break on any Claude Code update, so every
failure path falls back silently to the local estimate.

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
