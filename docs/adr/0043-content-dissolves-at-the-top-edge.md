# Content dissolves at the top edge; no blur bands over the launcher's lists

Status: accepted. Supersedes the two *bare* blur bands at the launcher's top
edge — Home's Favorites band and the shared status-bar band. The bands that
back a **breadcrumb** (a [[Quick capture]]'s, the [[Search Files context]]'s)
are untouched: those carry chrome on them, which is the case this ADR does not
cover. ADR 0010's backdrop, its never-hand-roll-blur rule and its motion budget
stand.

## Context

Home pinned the [[Favorites grid]] over a `.ultraThinMaterial` band that faded
out at its lower edge, and every scrolling surface — the [[Result list]], a
grid-less Home — carried a second, bare copy of the same band under the status
bar. Both existed for the same reason: a row scrolling up to the top of the
screen would otherwise cross the cards, or the clock, in full ink.

A band solves that by putting a **plate between the chrome and the [[Living
backdrop]]**. That is the thing ADR 0042 spent its argument on from the other
side: glass is the layer that floats over content and refracts it, and the
launcher already has such a layer in the Favorites cards themselves. Backing
those cards with a frosted rectangle means the user sees a card refracting a
plate refracting the backdrop — three surfaces where the design has two, and
the plate is the only one that carries no information. The status-bar copy is
the same plate with nothing riding it at all.

## Decision

**Nothing is painted over these lists. The content gives way instead.**

The scrolling surface masks itself with a top fade: rows are solid below the
strip they have to clear, dissolve through it, and are fully gone at the
screen's top edge. On Home the strip is the one the grid already reserves, so a
row is gone by the time it reaches the cards; where no grid is pinned, and on
the Result list, it is the status area alone.

- The cards sit **directly on the backdrop**, so a Favorite refracts the same
  thing the input bar does.
- The status bar never shares pixels with a row, which is what the band was
  actually for — reached by removing ink rather than adding material.
- One rule, one modifier (`dissolvesAtTop`), for both surfaces: a Recent row
  and a result row are the same `ActionRow`, and they now leave the screen the
  same way.

## Consequences

- The grid has to hold its own clearance under the status bar, since the bleed
  that used to reserve it went with the band (`StatusBarMetrics.topInset`).
- The fade is geometric, not measured: it runs over the same constant the
  Recent list is padded past, so the two move together or not at all. A grid
  whose height stops matching that constant would show rows too close to the
  cards — the constant is the coupling, and it is named once.
- A row inside the strip is gone rather than dimmed, so nothing there can be
  read *or* aimed at. That is the intent — it sits behind the cards or the
  clock — but it is a real difference from a band, which left an unreadable row
  underneath still taking taps.
