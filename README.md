# Claude Usage Buddy

Hover the camera notch on a MacBook Pro and a panel drops down showing how much of
your current Claude session window you've used and when it resets.

```
        ╭─────────────────────────╮
        │        ▓▓ notch ▓▓      │
   ╭────┴─────────────────────────┴────╮
   │   ╭───╮   TOKENS USED             │
   │   │44%│   120,113,794             │
   │   ╰───╯   of 272M allowed         │
   │   ─────────────────────────────   │
   │   RESETS IN            AT         │
   │   2h 49m               10:58 PM   │
   │   ● calibrated                    │
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

```sh
# launch at login
/Applications/ClaudeUsageBuddy.app/Contents/MacOS/ClaudeUsageBuddy --enable-login-item

# headless readout, for sanity checks
/Applications/ClaudeUsageBuddy.app/Contents/MacOS/ClaudeUsageBuddy --print-usage
```

## No credentials, ever

This app reads local files and nothing else. It does not link `Security` or
`CFNetwork` — verify with `otool -L` — so it is structurally incapable of reading your
keychain or making a network request. No passwords, no tokens, no prompts.

## How usage is calculated

Every assistant response Claude Code writes to `~/.claude/projects/**/*.jsonl`
carries a `message.usage` block with exact token counts. Those files are tailed
incrementally from a stored byte offset and de-duplicated by record `uuid`, which
also cancels out the overlap between a session transcript and the per-subagent
transcripts written next to it. Usage is aggregated **account-wide** across every
project, because the rate limit is account-wide.

A session window opens on the first request after a five-hour lull and runs five hours
from that exact moment — *not* from the top of the hour. Anthropic's own reset times
land on precise seconds (one observed here reset at 21:39:59, so it opened at
16:39:59), so rounding down to the hour would shift the countdown by up to an hour.

## Calibration

Token counts are exact. Turning them into a percentage needs a denominator, and
Anthropic doesn't publish one — there's no documented token cap for the rolling
session window, and it varies by plan and tier.

So the app asks you once, on first launch. Run `/usage` in any Claude Code session and
type in two numbers:

| From `/usage` | What it fixes |
|---|---|
| Session percentage | Back-solves your real token allowance |
| Reset time *(optional)* | Pins the current window exactly |

The percentage is the important one. Repeated calibrations feed a running average, so
they converge rather than overwrite each other. Recalibrate any time from the menu bar
item; until you do, the panel shows an amber dot and the word *estimated*.

The reset time is worth entering because transcripts only cover Claude Code **on this
Mac** — usage from claude.ai, the desktop app, or another machine is invisible here, so
an inferred window can start later than the real one. A pinned reset time expires on
its own once it passes, after which the countdown reverts to being inferred and the
panel labels it *reset approx.*

## Layout

```
Sources/ClaudeUsageBuddy/
├── App.swift              entry point, menu bar item, CLI flags
├── Notch/
│   ├── NotchGeometry.swift   derives the notch rect at runtime
│   ├── NotchWindow.swift     borderless panel above the menu bar
│   └── NotchController.swift hover state machine
├── UI/                    Collapsed / Expanded / Calibration / Settings / Theme
├── Usage/                 scanner, 5h window math, store, settings
└── Support/LoginItem.swift
```

Notch geometry is derived from `NSScreen.auxiliaryTopLeftArea` /
`auxiliaryTopRightArea` rather than hardcoded, so docking, external displays, and
notch-less Macs all behave. The panel pins to the built-in screen and hides itself
when the menu bar does (native fullscreen).

## Privacy

Only token counts and timestamps are read from transcripts — never message content.
Nothing is transmitted anywhere.

## License

MIT
