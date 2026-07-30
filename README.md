# Claude Usage Buddy

Hover the camera notch on a MacBook Pro and a panel drops down showing how much of
your current Claude session window you've used and when it resets.

```
        ╭─────────────────────────╮
        │        ▓▓ notch ▓▓      │
   ╭────┴─────────────────────────┴─────╮
   │  ╭───╮  NEW TOKENS     ┌──────┐    │
   │  │44%│    2,847,309   ─┤ ▪  ▪ ├─   │
   │  ╰───╯  this window    └┬┬──┬┬┘    │
   │  SHARE OF NEW TOKENS               │
   │  ██████████████████████████████  █ │
   │  ■ Opus 99%    ■ Sonnet <1%        │
   │  ────────────────────────────────  │
   │  RESETS IN            AT           │
   │  1h 20m               9:40 PM      │
   │  ● solved       [Recalibrate]      │
   ╰────────────────────────────────────╯
```

Three readouts, by design: **tokens used**, **percentage**, **reset time** — plus a
breakdown of which models spent them.

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

## The model split

A stacked bar under the token count shows which models the window's new tokens came
from — Opus, Sonnet, Haiku — with the exact figures on the right-click menu and in
`--print-usage`.

It is a share of **tokens observed on this Mac**, and deliberately not a share of the
limit. `claude -p "/usage"` reports one session percentage and does not break it down by
model, so a per-model *percentage of the limit* would have to be invented: the models do
not draw on the allowance at the same rate, and transcripts cannot see usage from
claude.ai or another machine. Hence the label "share of new tokens" rather than a bare
percentage that could be read as a second opinion on the ring.

Two details that only show up against real data:

- **A dominant model is the normal case.** One window measured here ran 99.3% Opus /
  0.7% Sonnet. A strictly proportional bar would have drawn the minority model as a
  2.7pt sliver, and a rounding error would have erased it — so every non-zero slice has
  a 5pt floor, paid for by the slices with room to give. The legend says `<1%` rather
  than `0%` for the same reason.
- **Model ids are not a fixed list.** `claude-haiku-4-5-20251001` is not a name anyone
  wants to read, and hardcoding a table of ids would silently drop the next model
  Anthropic ships. The family word is parsed out instead, which also handles the older
  `claude-3-5-sonnet-20241022` ordering and Bedrock/Vertex decorations like
  `us.anthropic.claude-sonnet-4-5-v1:0`. An unrecognised family still gets a readable
  name and its own colour rather than disappearing.

The palette is cool — periwinkle, sky, orchid — because warm colour on this panel is
already spoken for twice: the ring runs green→amber→red for how spent the window is, and
the buddy is clay. A warm slice would read as a third severity signal, and which model
you used is not good or bad news.

Past four models the tail groups into a grey **Other (n)** rather than being truncated,
so the slices always sum to the headline.

## Requirements

- **macOS 14+**, Apple silicon or Intel
- **Claude Code installed and signed in.** The app shells out to `claude -p "/usage"`
  for the percentage, so without it there is nothing to read. Check with:
  ```sh
  claude -p "/usage"
  ```
  It looks for the binary in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and
  `~/.claude/local`.
- **Command Line Tools** to build (`xcode-select --install`). Full Xcode is *not*
  needed.
- A **notch** is optional. Without one the panel drops from the top-centre of the main
  screen instead, and the buddy sits at the top of the menu bar strip either way.

## Install

```sh
git clone https://github.com/ArnayG/claude-usage-buddy.git
cd claude-usage-buddy
make install
```

That builds, bundles, ad-hoc signs, copies to `/Applications`, and launches it.
Other targets: `make run` (run from `dist/`), `make bundle`, `make clean`.

The app is an accessory (`LSUIElement`) — **no Dock icon and no Cmd-Tab entry**. That
is deliberate: it lives in the notch.

To reach Settings, launch-at-login or Quit, either **right-click the buddy** (or the
open panel), or use the **•••** button in the panel footer.

There is deliberately no menu bar status item. On a notched Mac the bar fills up fast
— measured here, only 55pt separated the cutout from the leftmost Control Center item,
and the buddy already occupies 32 of it, while an icon-plus-percentage item needs
about 62pt. macOS silently hides items that do not fit, so rather than ship invisible
UI the menu moved onto the panel.

```sh
# launch at login
/Applications/ClaudeUsageBuddy.app/Contents/MacOS/ClaudeUsageBuddy --enable-login-item

# headless readout, for sanity checks
/Applications/ClaudeUsageBuddy.app/Contents/MacOS/ClaudeUsageBuddy --print-usage
```

### Why build from source instead of downloading a binary?

Because a downloaded copy would be blocked. The app is ad-hoc signed, so Gatekeeper
rejects it (`spctl` says `rejected`) and macOS quarantines anything that arrives from
a browser or a messaging app — the recipient would have to right-click → Open, or
strip the flag by hand:

```sh
xattr -dr com.apple.quarantine /Applications/ClaudeUsageBuddy.app
```

Shipping a binary that opens cleanly needs a paid Apple Developer ID and
notarization. Building locally sidesteps all of it: locally-built apps are never
quarantined, and the build takes a few seconds.

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
land on precise seconds rather than on the hour, so rounding a window start down to
the hour can shift the countdown by up to an hour in the wrong direction.

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
Current session: 37% used · resets Jul 29 at 2:40am (America/New_York)
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

The headline counts **new tokens only** — input, output, and cache writes. Cache *reads*
are excluded on purpose: they are the existing conversation being re-fed on every
request, so the same tokens get counted again and again. Measured over one real window
they were 98.8% of the raw total (245M of 248M), inflating it about 86× while being the
cheapest token type by an order of magnitude. The raw figure is still available via
`--print-usage`.

There is nothing to calibrate, and no settings that affect accuracy.

## Layout

```
Sources/ClaudeUsageBuddy/
├── App.swift              entry point, app menu, CLI flags
├── Notch/
│   ├── NotchGeometry.swift   derives the notch rect at runtime
│   ├── NotchWindow.swift     borderless panel above the menu bar
│   └── NotchController.swift hover state machine
├── UI/                    Collapsed / Expanded / ModelSplitBar / Settings / Theme
├── Usage/                 scanner, 5h window math, model split, store, settings
└── Support/LoginItem.swift
```

`Tools/render-panel.swift` renders the panel offscreen to PNGs at 3×. There is no Xcode
here, so no previews and no canvas, and screenshotting the real panel needs Screen
Recording permission — this is how the layout actually gets looked at:

```sh
swiftc -O -parse-as-library \
  Sources/ClaudeUsageBuddy/UI/{Theme,ExpandedView,ModelSplitBar,Buddy}.swift \
  Sources/ClaudeUsageBuddy/Usage/{UsageModel,ModelSplit}.swift \
  Sources/ClaudeUsageBuddy/Support/LoginItem.swift \
  Sources/ClaudeUsageBuddy/Notch/NotchGeometry.swift \
  Tools/render-panel.swift -o /tmp/render-panel
/tmp/render-panel /tmp/panels
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
