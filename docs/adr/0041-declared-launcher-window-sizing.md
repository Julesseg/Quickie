# The app declares the window it wants, and composes at every size the system gives it

## Context

Since ADR 0039 the launcher lays out in a readable command column at regular
width and in the iPhone layout at compact, keyed off the window's horizontal
size class. What it never said anything about is the **window** itself.

Under iPadOS 26 that omission has teeth. `UIRequiresFullScreen` is deprecated
and ignored, every window is a freely resizable rectangle, and the system tiles
one against an edge or a corner into halves, thirds, quadrants and Slide Over.
The scene was a bare `WindowGroup` (audit finding F8): no minimum content size,
no default size. The system therefore picked both — including how small a drag
may take a window that has to keep an input bar, a [[Shelf]] and the
[[Highlighted result]] on screen together.

A second finding fell out of the same sweep. On a **short and wide** window —
landscape with the keyboard docked, or a Stage Manager half-height — the
[[pre-anything Home]]'s block (the [[Brand mark]], "Start typing", the
[[Hint line]]) sat visibly high in the band above the input bar (F12). It was
composed as `VStack { Spacer(); block; Spacer() }`, which centres the block in
the height SwiftUI *proposes to the stack*. Measured on a 13" iPad in landscape
that put the block ~40pt above the middle of the ~460pt band the placeholder is
actually drawn in — a tenth of the band. In a portrait window's ~1,300pt band
the same 40pt is 3%, which is why this only ever read as an iPad defect.

## Decision

**The app declares two window sizes, and they live in QuickieCore beside the
column they bracket** (`LauncherWindow`), not in the scene declaration:

- **`minimumSize` — 320×320.** 320 wide is the narrowest canvas iOS has ever
  handed the compact layout: the 4" iPhone's, and Slide Over's. 320 tall is the
  shortest window that still holds the three things that make this a launcher —
  the input bar, the Shelf above it, and the highlighted row above that — with
  the safe areas around them. The scene applies it with
  `.frame(minWidth:minHeight:)` plus `.windowResizability(.contentMinSize)`,
  which is what turns a declaration into a limit the drag stops at.
- **`defaultSize` — 880×1000.** The readable column plus a 100pt margin on each
  side, tall enough for the [[Favorites grid]], a screen of Recents and the bar.

**The floor is deliberately not roomier.** The two acceptance criteria pull
against each other: "the window cannot shrink below a usable launcher" wants a
high floor, and "pass the sweep at halves, thirds, quadrants and Slide Over"
wants a low one. The tiles win. An iPad mini's landscape quadrant is 372pt tall
and a Slide Over panel is 320pt wide; a floor set anywhere above those would
refuse a window the system itself hands the app, which is a worse defect than
the one a roomy floor would prevent. `LauncherWindowTests` walks every tile on
three displays in both orientations and asserts none of them is below the floor,
so the constraint is checked rather than remembered.

**The floor sits under the column and the default sits over it.** That is the
whole relationship between this policy and ADR 0039: a window can be dragged
across its entire legal range and only ever land in one of the two layouts that
are tested — the iPhone layout at the floor, the column at the default. Nothing
in between needs a third case.

**Non-destructive resizing is a property, not a feature.** Every layout decision
downstream is a pure function of the window's size class, so a window dragged
narrow and back wide returns to the layout it left with nothing torn down in
between (the WWDC25 208 requirement). It is asserted the way the property is
stated: replay a resize forwards and backwards and demand the same answer at
each width on the way back. A policy that remembered anything about the widths
it had been through would disagree with itself there.

**The pre-anything Home is *placed*, not spaced.** The block's centre goes at
the centre of the band the placeholder is drawn in, read from that band's own
resolved height (`GeometryReader` + `.position`) instead of emerging from two
`Spacer`s. This is exact at every window shape, because the rectangle it
measures against is the rectangle the block is drawn in — which is the one
thing the Spacer sandwich could not guarantee.

## Consequences

- The scene grows three modifiers and no logic; the two numbers and their
  relationship to the column are `swift test`-gated in Core, like every other
  piece of presentation arithmetic in this codebase.
- The odd-size sweep is covered from two directions. Core walks the tile table
  as geometry — no tile below the floor, the column never overflowing a tile, a
  Favorite card never collapsing — and, because a keyboard on iPad belongs to
  the *display* rather than to the window, it re-runs ADR 0040's lift at each
  tile placed where the system puts it, including a top quadrant the keyboard
  never reaches. The rest is a screenshot sweep on the simulator, attached to
  the PR: a QA pass is evidence, not a test.
- F12's fix is App-side and has no Core rule, because there is no arithmetic in
  it worth pinning — "centre it in the band it is in" is one line. What *is*
  pinned is the acceptance statement, as a UI test that measures the block
  against the band on a real device
  (`HomeBrandUITests.testThePlaceholderBlockIsCentredInTheBandAboveTheInputBar`).
- The declared floor is a *lower bound on the system's own*: iPadOS applies its
  minimum on top, so the effective floor is the larger of the two. Declaring
  ours can only ever raise it, never talk the system into a window it would
  otherwise refuse.

## Considered options

- **Say nothing and let the system pick** — the status quo. Rejected: the
  system's floor is about windows in general and cannot know which of the
  launcher's parts stop fitting together first, and a default window it picks
  may well be compact, opening every new iPad window in the iPhone layout that
  ADR 0039 exists to move past.
- **A roomier floor (say 500×600), so "usable" is comfortable rather than
  minimal.** Rejected above: it refuses tiles the system produces.
- **`.windowResizability(.contentSize)`.** Rejected: it pins the window *to*
  the content's size in both directions, which would fight free resizing —
  exactly the iPadOS 26 behaviour the app should be a good citizen of.
- **Enumerate the tile sizes in Core and switch on them.** Rejected: under
  iPadOS 26 a window is a continuum, and a policy that recognised seven sizes
  would be wrong at the 8th. The tile table belongs in the test, as the sweep it
  is; the shipping rule stays a function of the size class.
- **Fix F12 with a constant nudge (`.offset(y: 40)`) or a fraction of the band
  other than a half.** Rejected: both encode the *symptom's* size. A constant is
  wrong at every band but the one it was measured in, and a fraction re-breaks
  the tall windows that were already right.
