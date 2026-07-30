# Claude Usage Buddy

Hover the camera notch on a MacBook Pro and a panel drops down showing how much of
your current Claude session window you've used, when it resets, and how much you have
got through in the last seven days.

```
        ╭─────────────────────────╮
        │        ▓▓ notch ▓▓      │
   ╭────┴─────────────────────────┴─────╮
   │ ╭──╮ NEW TOKENS   RESETS IN  ┌───┐ │
   │ │62│ 3,035,082    4h 1m     ─┤▪ ▪├─│
   │ ╰──╯ this window   10:56 PM  └┬┬┬┬┘ │
   │ ─────────────────────────────────  │
   │ (Models) (Rate) (Week)             │
   │ AT THIS RATE                 BURN  │
   │ full by 9:10 PM ±9m        +15%/h  │
   │ ● from /usage    [Refresh]  [•••]  │
   ╰────────────────────────────────────╯
```

**Tokens used**, **percentage** and **reset time** are always on screen. The three
detail sections — model split, burn rate, trailing week — share one slot behind a tab
bar, because you open the panel to answer one question and the other two are noise
around it.

The slot is a fixed height, so switching tabs never resizes the window. Which tab you
picked is remembered.

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

### The shoulders where the panel meets the top edge

Each shoulder is an **ogee** — two quarter circles of radius `flare / 2`, one concave
then one convex — so the boundary is **vertical at both ends**: perpendicular to the
top edge of the display, and parallel to the body's side edge where it lands.

It took three attempts. A `addQuadCurve` cannot describe a circular arc at all (6.1%
off the radius, biased toward the top edge). Replacing it with a *single* true quarter
circle was geometrically exact and still looked sharp, because a quarter arc is tangent
to the top edge: at a 20pt flare the boundary moves 6.2pt inward within the first 1pt
of descent, so the black ended in a razor-thin wedge. Only the ogee removes it —
curvature flips sign at the midpoint, which is what makes it read as a shoulder rather
than a bite.

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
7-day requests/sessions   ←  claude -p "/usage"      (this machine only)
weekly percentage         ←  claude -p "/usage"      (usually absent — see below)
burn-rate projection      ←  successive percentages  (an estimate, labelled as one)
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

## The weekly view, and the percentage it does not show

The bottom section of the panel covers the trailing seven days. It shows a **token
total**, not a share of a limit, and it says so on screen.

That is not an oversight. `claude -p "/usage"` reports **no weekly percentage** on this
account, and there is no other source the app can see. Its entire weekly output is:

```
Last 7d · 1361 requests · 7 sessions
  84% of your usage was at >150k context
  10% of your usage came from subagent-heavy sessions
  Top MCP servers: claude-in-chrome 31%
```

Those percentages are traps. They are *characteristics* of the week's usage — how much
of it happened at long context, which tools it went through — not fractions of any
allowance. The section is even prefaced "Behaviors are independent characteristics, not
a breakdown". Rendering any of them in a ring would be a straightforward lie.

So the parser demands two things before it will believe a weekly percentage: the label
before the colon must mention a week, *and* the value must literally read `N% used`.
That is enough to accept `Current week (all models): 45% used · resets Aug 5`, which
some plans do print, while rejecting every line above. When a real figure is found the
weekly section grows a ring matching the session gauge, names which limit it is (an
overall cap and a per-model cap are different things, and the higher of the two is
shown with its label), and counts down to the weekly reset.

When there is no figure — the common case — there is **no ring and no percentage**:

| Shown | Source |
|---|---|
| 7-day new-token total | local transcripts, this Mac |
| requests · sessions | `/usage`, explicitly "based on local sessions on this machine" |
| a percentage | nothing — so nothing is shown |

This project already shipped a weekly percentage once, inferred from a token allowance
it back-solved from a number you typed in. It was wrong in the field and had to be
deleted. Dividing a 7-day token count by a plausible-looking denominator would repeat
that with less excuse, because unlike the session limit there is no real weekly
quantity anywhere for it to converge on. A missing gauge is information. A confident
wrong gauge is not.

## Burn rate: "full by 8:44 PM"

The bottom row extrapolates the trend and says when the window will be spent — or that it
won't be. It is the one number in the app that is an **estimate**, which is why the label
above it reads `AT THIS RATE` and why it shows its own error bar.

The rate is measured from **successive `/usage` percentages** and nothing else. The
tempting alternative — the local token rate, which is continuous and finely resolved —
cannot be converted into a percentage without a tokens-per-window allowance, and that
constant is exactly the calibration [described above](#where-the-numbers-come-from) that
was deleted for being wrong. Transcripts also cannot see claude.ai or another machine, so
a local-only rate would report "not on track" while the window filled up elsewhere.

The percentage arrives as a **whole number**, so one sample carries up to ±0.5pp of
rounding error and a two-sample slope 60s apart is ±60pp/hour of pure noise. Instead the
app fits a weighted least-squares line through up to an hour of readings, with weights
halving every 12 minutes. Measured across 30 rounding phases of the same true 18%/h
series, the fitted rate varied by 0.68pp/h; the two-sample slope varied by 60pp/h.

Because the fit reports a standard error, the app can tell when it does not know:

| What you see | When |
|---|---|
| `full by 8:44 PM ±9m` | rising by more than ~2σ, and the cap arrives before the reset |
| `resets before you run out` | genuinely rising, but the window resets first |
| `not on track to run out` | flat, falling, or rising too weakly to distinguish from rounding |
| `need more readings` | fewer than 3 readings in the current window |
| `measuring…` | 3 or more readings, but under 8 minutes of baseline |
| `trend too old to trust` | the newest reading is over 15 minutes old |
| `no active window` | `/usage` gave no reset time |

The window is rolling, which the projection has to respect in three places. Readings from
before the current window start are discarded, so the slow forward creep of the reset time
and an outright rollover are handled by the same rule. A step down of 5pp or more between
adjacent readings is treated as a block of old usage aging out at once, and the fit
restarts after it rather than reading the cliff as a rate. And what gets extrapolated is
the *net* rate — the derivative of the number on screen, which already has aging-out
folded in — bounded by the reset, so the horizon is never more than five hours.

Honest limitations, in the same spirit as the rest of this file:

- It is a **linear** extrapolation of something that is not linear. Early in a window
  nothing has aged out yet and the net rate equals the gross rate; later the net rate is
  smaller. Recovering the gross rate from net percentages alone is underdetermined, so it
  is not attempted.
- The reset time itself **creeps forward**, so "resets before you run out" can become
  wrong later in a window.
- A pause bleeds the estimate down over tens of minutes rather than instantly. That is
  deliberate — the alternative flaps between "20 minutes left" and "not on track" every
  time you stop to read a diff — but it does mean a projection can lag reality by a while.
- The reported margin assumes independent rounding errors. Rounding a smooth ramp is
  actually a correlated sawtooth, so on unusually smooth series the margin is optimistic.
  Real consumption is bursty enough that measured residuals dominate the floor.

Roughly an hour of readings is kept in `UserDefaults` so the trend survives a relaunch.
They are verbatim probe output, scoped to the current window, and about 3KB.

```sh
make test-burn-rate   # synthetic-series checks: rising, falling, flat, cliffs, rollovers
```

## Layout

```
Sources/ClaudeUsageBuddy/
├── App.swift              entry point, app menu, CLI flags
├── Notch/
│   ├── NotchGeometry.swift   derives the notch rect at runtime
│   ├── NotchWindow.swift     borderless panel above the menu bar
│   └── NotchController.swift hover state machine
├── UI/                    Collapsed / Expanded / ModelSplitBar / Weekly / Settings / Theme
├── Usage/                 scanner, 5h window math, model split, burn rate, store, settings
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
