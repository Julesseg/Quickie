# No palette mode: the launcher does not change shape under you

Status: accepted — **rejects** direction alternative B of the iPad UI audit
(issue #269). Nothing ships from it. ADR 0008's bottom-anchored [[Result list]]
and ADR 0039's [[Readable command column]] are unchanged, and the prototype
branch `prototype/ipad-palette-mode` is a primary source, not a candidate for
merge.

## Context

The iPad UI audit (branch `prototype/ipad-ui-audit`, report
`ipad-report/index.html`, §5) proposed three directions. **A** — the readable
command column — shipped as ADR 0039. **B** was a Spotlight/Raycast palette:
on a regular-width window with a hardware keyboard attached, put the input near
the top third and let results drop downward, instead of docking the input at
the bottom with results stacking up off it.

The argument for it is good, and it is worth stating properly because it
survives this rejection. Quickie's bottom dock is a **thumb-reach** decision:
the input sits where the thumb is and the [[Highlighted result]] sits just
above it, so the best match is nearest both the cursor and the hand. With a
hardware keyboard there is no thumb. The keyboard that the bar is lifted onto
([[Keyboard lift]], ADR 0040) is not there either. What is left is a command
bar alone at the foot of a 13" canvas with roughly 60% of the screen empty
above it, and an eye-line at the very bottom of the display. The audit's
concept mock put the field where the eye already is.

Issue #269 commissioned a `/prototype` round to prove or kill three things:
rank-0 adjacency, the motion budget for the flip, and whether mode-flipping
disorients. It was built and driven on an iPad Pro 13" (M5) simulator,
iPadOS 26.3. Report: `palette-report/index.html` on the prototype branch.

## Decision

**The launcher has one layout. It does not re-shape itself in response to a
keyboard being attached or detached.**

Alternative B is rejected. Not because the palette looks bad — it does not, and
§"What the prototype proved" below records that it is better than today's
layout in the state it was designed for — but because the *mode* is the
expensive part and the mode is what fails.

Three findings decide it, in order of weight.

### 1 · The flip is not a transition. It is the list dissolving into its own reverse.

This is the one that settles it, and it is not an implementation detail that a
better animation would fix.

Docked, the [[Result list]] renders rank 0 **last**, at the bottom, against the
input. Palette renders the same array the other way up, rank 0 **first**, at
the top. Every row is therefore in a different place in the two layouts —
not shifted, *reversed*. There is no correspondence for an animation to
interpolate along.

Filmed at the real motion budget, the intermediate frames show what that costs:
the input bar travelling **through** the middle of the result list, over the
rows, while two differently-ordered copies of the list crossfade — so `New
Snippet`, `Save for later`, `Search the web` and `Search the App Store` are each
on screen **twice**, in two different positions, for the duration. About
**26% of the screen** is in motion. Frames `flip-004` and `flip-025` in the
report are the evidence.

ADR 0010's animation budget exists to protect type → choose → run. A whole-
screen dissolve in which the [[Result list]] is transiently unreadable and the
input crosses it is not inside that budget, and cannot be brought inside it by
choosing a gentler spring: the two layouts have no shared geometry to animate
between. The honest way to move between them is a cut, and a cut that moves the
input bar and every result row at once is exactly the disorientation the
prototype was asked about.

### 2 · The trigger cannot be tested, and its obvious form does not work at all.

The first implementation asked `KeyboardBarLift.Geometry.isSoftwareKeyboard` —
the keyboard's own height, off the `keyboardWillChangeFrame` the bar lift
already consumes (ADR 0040). That is the natural place to look and it is wrong,
for a reason worth writing down: **with a hardware keyboard attached, iPadOS 26
posts no keyboard notification at all.** There is no accessory bar to announce
itself. The flag never left its initial value, so the launcher stayed docked on
precisely the device the mode exists for. *The absence of a keyboard is not a
keyboard event.*

The signal that does answer it is `GCKeyboard.coalesced`, from the Game
Controller framework, with its connect/disconnect notifications. That works —
and it is **unavailable in the simulator**: `GCKeyboard` reports no keyboard
even with Connect Hardware Keyboard enabled. Nor can XCUITest stand in for it,
because a UI test raises the **software** keyboard in order to type, which is
the exact condition the mode is defined by the absence of. A driver that types
can never photograph, or assert on, the mode it is testing.

So the trigger is verifiable only by hand, on physical hardware. Against
ADR 0038 (the UI suite runs on both families) and this repo's convention that
CI is the canonical UI gate, that is a permanent hole: a second layout mode
whose entry condition no automated test on any machine we own can ever assert.

### 3 · [[Home]] gets worse, and the [[Living backdrop]] loses its anchor.

Home's [[Favorites grid]] is pinned to the top of the surface and the Recent
list fills from the bottom. Move the input to the top third and the Favorites
band is stranded *above* the field with the rest of the window empty below it —
the pre-anything state, the first thing a hardware-keyboard user sees, reads
worse than it does today.

The [[Living backdrop]]'s hero glow rides the bar's [[Keyboard lift]] (ADR
0034), so it is defined relative to the *bottom* bar. In palette mode the bar
has left the bottom and the glow has nothing to ride. Neither is unfixable;
both are more surface area to redesign and then maintain in two shapes forever.

## What the prototype proved, and is worth keeping

Recorded because it is a real result and because a future round should not have
to rediscover it:

- **Rank-0 adjacency survives the inversion.** ADR 0008's guarantee turns out to
  be *adjacency to the input*, not "bottom" — the [[Highlighted result]] sits
  directly under the field instead of directly over it, and honouring it
  upside-down took only a reversal, a frame alignment and a scroll anchor. Rows
  stay keyed by rank, so a keystroke still swaps each slot's content in place
  and the highlighted slot still never moves.
- **In the results state, the palette is better.** With a hardware keyboard the
  query, its answer and the ranked rows sit at eye level instead of huddled in
  the bottom third under an empty canvas. This holds in light and dark. The
  audit's ergonomic argument is sound; it is the *mode* that does not pay.
- **`CONTEXT.md` bakes the anchor into the term.** The [[Result list]] is
  defined as "the single, **reversed** (bottom-anchored, best match nearest the
  input/thumb) list". Adopting B would have made the project's own vocabulary
  conditional on a layout mode. Left as is.

## Consequences

- Nothing ships. `ResultListView`, `HomeView`, `RootView` and the
  [[Readable command column]] are untouched on `main`.
- The empty-canvas problem the audit identified is **real and unaddressed** at
  regular width with a hardware keyboard. This ADR rejects *inverting the
  layout* as the answer to it, not the observation itself. Any future attempt
  should start from the two constraints this round established: decide the
  shape **once, at entry**, never live — a launcher that re-shapes mid-session
  has no acceptable transition — and expect the trigger to be hand-verified.
- Audit roadmap phase 6 loses its palette half. Alternative **C** (two-pane
  management via `NavigationSplitView`) is untouched by this and remains open;
  it is a navigation change, not a re-anchoring, so none of the three findings
  above transfer to it.
- `GCKeyboard.coalesced` is recorded here as the correct hardware-keyboard
  presence signal, and the keyboard-frame notifications as the wrong one, so the
  next thing that needs it does not repeat finding 2.

## Considered options

**Adopt B as specified — flip live on keyboard attach/detach.** Rejected: the
flip has no interpolable intermediate (finding 1), and the trigger is
untestable (finding 2).

**Adopt the palette layout, but decide once at launch and never flip.** This
answers finding 1 completely — no transition exists, so none can disorient —
and it is the shape a future round should take if this is reopened. Rejected
*now* rather than on its merits: it still buys a second layout mode with an
untestable entry condition and a Home that needs redesigning first, in exchange
for a gain confined to one state. The audit itself said to decide "after A
ships and hardware-keyboard telemetry/feel is in", and there is no telemetry
yet — so the cost is certain and the benefit is still an assertion.

**Make it a user setting rather than an automatic mode.** Rejected on the same
maintenance grounds, and it trades an untestable trigger for a permanently
supported second layout, which is worse. Quickie has no layout preferences and
this is a poor first one.

**Reduce the empty canvas without inverting anything** — e.g. compose the
docked layout deliberately for a short-and-wide or tall-and-empty window, which
audit finding F12 already flags for landscape. Not decided here; it is the
cheaper direction and it keeps one layout. Left open.
