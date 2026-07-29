# Claude Usage Buddy

Hover the camera notch on a MacBook Pro and a panel drops down showing how much of
your current Claude session window you've used and when it resets.

```
        ╭─────────────────────────╮
        │        ▓▓ notch ▓▓      │
   ╭────┴─────────────────────────┴─────╮
   │  ╭───╮  TOKENS USED    ┌──────┐    │
   │  │44%│  132,337,126   ─┤ ▪  ▪ ├─   │
   │  ╰───╯  this window    └┬┬──┬┬┘    │
   │  ────────────────────────────────  │
   │  RESETS IN            AT           │
   │  1h 20m               9:40 PM      │
   │  ● solved       [Recalibrate]      │
   ╰────────────────────────────────────╯
```

Three readouts, by design: **tokens used**, **percentage**, **reset time** — plus a
Recalibrate button, because accuracy is something you top up rather than set once.

And a buddy, who is having a progressively worse time as you spend your window.

## The buddy

A pixel creature that wilts as usage climbs. With no mouth to work with, the emotional
range is carried by eye shape, arm droop, leg posture and colour:

| Usage | Eyes | Posture |
|---|---|---|
| 0–20% | `^ ^` happy | arms up, gentle bob |
| 20–40% | `▮ ▮` neutral | the reference sprite |
| 40–65% | `▬ ▬` wary squint | flat |
| 65–85% | `v v` downcast | arms sagging |
| 85–100% | `✕ ✕` dead | limp arms, legs splayed, ashen |

It stays clay (`#D97757`) and gets *sick* rather than shifting hue — the ring beside it
already carries green→amber→red, and recolouring the character would throw away its
identity.

A small version also hangs below the notch whenever the panel is closed, so you get the
mood without hovering. That peek is a **separate, `ignoresMouseEvents` window**: growing
the collapsed window instead would have left a 185×20pt strip permanently swallowing
clicks right under the menu bar. It renders statically — an animation timer on a window
that is visible 24/7 is a permanent battery cost.

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

There are two independent reasons a locally-computed percentage can be wrong:

1. **The denominator is unknown.** Anthropic publishes no token cap for the rolling
   session window, and it varies by plan and tier.
2. **The numerator is short.** Transcripts only cover Claude Code *on this Mac*. Usage
   from claude.ai, the desktop app, or another machine is invisible here.

A single reading can only fix the first, and it silently absorbs the second into the
allowance — which is why one calibration drifts.

**Two readings fix both.** The hidden baseline is the same in each, so it cancels:

```
allowance = Δtokens / Δpercent          ← hidden usage cancels in the subtraction
hidden    = allowance × percent₁ − tokens₁
```

Against a simulated ground truth of a 300M allowance with 40M spent off-device:

| | allowance error | reported % (truth 63.3%) |
|---|---|---|
| One reading | 39.4% | 82.5% |
| Two readings | **0.0%** | **63.0%** |

So: run `/usage` in Claude Code, hit **Recalibrate** on the panel and enter the
percentage. Do it again once usage has moved a few percent. The footer tells you which
tier you're on — *not calibrated* (amber), *1 reading* (amber), or *solved* (green),
with the off-device total it worked out.

Optionally enter the reset time too, which pins the current window exactly. Worth doing
for the same reason: an inferred window start can be late when the real window opened
off-device. A pinned reset expires by itself once it passes, after which the countdown
goes back to being inferred and is labelled *reset approx.*

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
