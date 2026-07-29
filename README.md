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

Three readouts, by design: **tokens used**, **percentage**, **reset time**.

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
identity. The colour ramp is **interpolated, not stepped**: the mood bands are wide
(40–65% is 25 points), so without continuous colour the creature can look frozen
through hours of real use.

**Poke it.** Hovering lifts it slightly and perks its eyes up; clicking sends it into
two decaying hops. Even at 95% it manages a weak rally, which reads as the creature
responding to you rather than the gauge having broken. The animation ticker only runs
while you are interacting — idle CPU measured 0.6%, hovering 3.5%.

A small version also sits **in the menu bar, just right of the camera**, whenever the
panel is closed — so you get the mood without hovering. It started out hanging below the
notch, which put it in the content area on top of real work; the strip beside the cutout
is dead space on most setups, since status items pack in from the right edge. It renders
statically, because an animation timer on a window visible 24/7 is a permanent battery
cost — the ticker starts only while you are hovering or poking it.

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

## Where the numbers come from

```
percentage + reset time   ←  claude -p "/usage"      (authoritative, free)
token count               ←  ~/.claude transcripts   (exact, real-time)
```

Earlier versions tried to *infer* the percentage: back-solving a token allowance from
a number you typed in, then solving a two-point system for usage it could not see. It
was never going to be right. Anthropic's session window resets on its own schedule,
and transcripts cannot see claude.ai or another machine — so the app would happily
report 57% while the real window had already rolled over to 0%.

Claude Code already knows the answer, and will tell you:

```
$ claude -p "/usage"
Current session: 5% used · resets Jul 29 at 2:40am (America/Indianapolis)
```

Measured on Claude Code 2.1.220, that takes ~1.1s and **costs nothing** — the request
count reported by `/usage` was identical across three consecutive probes. It also needs
no credentials of ours: the CLI handles its own auth, so there is still no keychain
access and no password prompt.

How often it runs is adaptive, because the percentage moves fast while you are working
(8% to 14% inside a couple of minutes of heavy use) and not at all while you are not:

| Condition | Cadence |
|---|---|
| New transcript activity since the last probe | every 60s |
| Nothing happening locally | every 10 min |
| Opening the panel | immediately, if >15s old |
| Refresh button | always |
| Waking from sleep | immediately |

Sleep freezes every timer, and the window may have rolled over entirely while the lid
was shut, so waking always re-probes. The idle cadence is what keeps the average cost
down — the CLI spawn is the expensive part, and it is pointless when nothing has
changed.

Note the session window is **rolling**, not a fixed block: old requests age out of it,
so the percentage falls as well as rises, and the reset time creeps forward.

Transcripts still supply the token count, which `/usage` does not report. The window is
defined by the probe's reset time (`start = reset − 5h`), so only tokens inside the real
window are counted.

There is nothing to calibrate, and no settings that affect accuracy.

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
