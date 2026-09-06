# No blur bands over the launcher's lists

Status: accepted. Removes the two *bare* blur bands at the launcher's top edge —
Home's Favorites band and the shared status-bar band. The bands that back a
**breadcrumb** (a [[Quick capture]]'s, the [[Search Files context]]'s) are
untouched: those carry chrome on them, which is the case this ADR does not
cover. ADR 0010's backdrop, its never-hand-roll-blur rule and its motion budget
stand.

## Context

Home pinned the [[Favorites grid]] over a `.ultraThinMaterial` band that faded
out at its lower edge, and every scrolling surface — the [[Result list]], a
grid-less Home — carried a second, bare copy of the same band under the status
bar. Both existed so a row scrolling up to the top of the screen would not cross
the cards, or the clock, in full ink.

A band solves that by putting a **plate between the chrome and the [[Living
backdrop]]**. That is the thing ADR 0042 spent its argument on from the other
side: glass is the layer that floats over content and refracts it, and the
launcher already has such a layer in the Favorites cards themselves. Backing
those cards with a frosted rectangle means the user sees a card refracting a
plate refracting the backdrop — three surfaces where the design has two, and the
plate is the only one that carries no information. The status-bar copy is the
same plate with nothing riding it at all.

## Decision

**The bands are removed. Nothing takes their place.**

The cards sit directly on the backdrop, so a Favorite refracts the same thing the
input bar does. A Recent row that scrolls up passes behind the cards and behind
the status bar as itself — not dimmed, not blurred, not faded.

This is a removal, deliberately, and not a swap for a subtler effect. A gradient
mask over the list was tried and rejected on sight: it is the same idea as the
band (hide the collision) wearing different clothes, and it costs the same
honesty about what is on screen. If the overlap turns out to bother us in use,
the answer is to change what the surfaces *are* — not to reintroduce a veil.

## Consequences

- The grid has to hold its own clearance under the status bar, since the bleed
  that used to reserve it went with the band (`StatusBarMetrics.topInset`).
- A row crossing the grid is drawn in full behind the cards, and the glass shows
  it. That is the accepted trade: the Recent list stays bottom-anchored and the
  cards stay four, so the overlap is bounded by how far the user scrolls.
- A row under the status bar is likewise drawn in full. The status text stays
  the system's, over whatever the backdrop and the row put beneath it.
