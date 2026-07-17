# A brand accent derived from the icon, with gold reserved for the hero

## Context

Quickie shipped its icon and its Quickie mark before it ever claimed a color.
`AccentColor.colorset` was an *empty* colorset, so every `Color.accentColor`
site — the [[Highlighted result]]'s ring and wash, the backdrop glow, the
breadcrumb pills, the Enter hint, the Live Activity glyphs — and every toggle
that merely inherits the ambient tint resolved to **system blue**. The app
looked like a default SwiftUI project standing next to a purple icon.

Meanwhile the brand's real colors existed in exactly two places that could not
see each other: `docs/brand/make-app-icon.py`, which owns them (`LAVENDER`,
`DOT_COLOR`, `BG_TOP`, `BG_BOTTOM`), and `QuickieGlyph.swift`, which
**hand-copied** three of them as SwiftUI literals for the widget extension —
a drift seam PR #169's review already flagged, papered over by a CI check.
Nothing in the *app* target could reach either.

The look-and-feel slice (#177, #178, #183, #184) needs both gaps closed first:
one palette, reachable from both targets, and a rule for where each color is
allowed to appear.

## Decision

**The accent is an adaptive purple derived from the icon — not one fixed
purple.** The icon's field (`BG_TOP` #2E1A5E) and its trail (`LAVENDER`
#CBB8FF) sit on the same hue (~257°) and differ only in lightness and
saturation, so the brand has a purple *axis* rather than a purple *value*. We
pick a point on it per appearance:

- **Light mode — a mid-purple, #5832B4**: the icon field's hue and saturation
  lifted to HSL lightness 0.45 (8.3:1 on white). The field's own #2E1A5E is
  legible on white but reads as near-black — an accent has to look *chosen*.
- **Dark mode — the icon's lavender, #CBB8FF** (11.8:1 on black), unchanged
  from the trail.

Neither value works in both appearances, which is why a single literal was
rejected: the lavender washes out to nothing on white, and the mid-purple
disappears into a dark backdrop.

**The accent is claimed twice, deliberately.** The **app** target's
`AccentColor` asset carries it so that *default* tinting — the 14 toggles,
system controls, anything that never opts in — is brand purple with no per-view
change and no way to forget. `QuickieBrand.accent` carries the same color as an
explicit token, for the **widget** extension (which has no such asset, by the
rule below) and for gradients and rings, which need a `Color` rather than an
ambient. The two agreeing is a CI obligation, not a convention (below).

An accent asset in *each* catalog would have been the symmetric answer, and is
rejected: two colorsets can disagree, which is the entire failure this ADR
exists to prevent — and the asset's reach (everything, by default) is wrong for
the extension specifically.

**The brand only tints Quickie's own surface.** Where the app extends into
shared chrome — the compact and minimal Dynamic Island, sitting beside the clock
and every other app's glyphs — the **system** tint stays. Those presentations
are a guest in someone else's layout, and a launcher insisting on its purple
there is noise, not identity. Quickie's own surfaces (the Live Activity's
expanded and Lock Screen presentations, the deep-link widget tile) wear the
accent. This is why the widget extension deliberately has **no** `AccentColor`
asset: an accent asset would tint *everything* in the extension by default,
including the chrome that shouldn't have it, so those surfaces name
`QuickieBrand.accent` explicitly and the rest keep `.tint`.

**Gold appears in exactly one place: the Highlighted result's hero glow
(#177).** The icon's warm mass (`DOT_COLOR` #FFC94F) is the thing the comet
orbits — the center of gravity. The Highlighted result is the app's center of
gravity: the row nearest the thumb, the one Enter runs. Spending gold anywhere
else makes it decoration; spending it there makes it *mean* focus. This is a
budget, not a palette entry — the rule is what gives the one use its force.

**One module owns every brand literal: `QuickieBrand`, in
`App/QuickieEntry/`** — the folder already synchronized into both the app and
the widget targets (`ActionIcons`, `DeeplinkInbox`). `QuickieGlyph`'s
hand-copied gradients are absorbed into it, leaving `QuickieGlyph` with its
actual charter: the symbol's identity. No brand color literal may live
anywhere else.

**The module's literals are CI-anchored to the icon generators.** Swift cannot
read Python constants, so `docs/brand/check-brand-assets.py` proves the two
agree on every full CI run: it re-derives the palette from `make-app-icon.py`'s
constants — including the light accent's lift, so the *derivation* is executable
rather than a note in a designer's head — and compares it against both
`QuickieBrand.swift`'s named literals and the `AccentColor` asset's JSON. Edit
the icon's purples and CI tells you which literals to update, with the numbers.

**QuickieCore stays color-free.** Core classifies (`ActionKind`, `MainAction`,
`ReturnKeyLabel`); the App edge decides what a classification looks like. Core
says *which glyph*, never *how it looks* — the same split that keeps
`MotionPolicy` naming moments rather than returning `Animation`s.

## Considered options

- **Recolor each surface at its call site**, no token module: the status quo
  extended. Rejected — it is how the widget ended up hand-copying three RGB
  triples in the first place, and it leaves the toggles (which name no color at
  all) on system blue forever.
- **A single fixed brand purple** for both appearances: simpler asset, simpler
  check. Rejected on contrast — see above. The adaptive pair is the *reason*
  the icon has both a field and a trail.
- **Put the palette in `QuickieCore`** so one module serves every target: Core
  would have to import SwiftUI and would start answering "what color is this?",
  which is precisely the question the App edge exists to answer. Rejected.
- **A generated `QuickieBrand.swift`**, emitted by `make-app-icon.py` like the
  SVGs are. Tempting — drift becomes impossible rather than merely detected —
  but it puts SwiftUI view code (gradients, the dynamic-color provider) inside
  a Python string, unreadable and unrefactorable, to police five numbers.
  Rejected in favor of hand-written Swift with a CI check, matching how the
  mark's literals were already handled.
- **Gold as a general secondary accent** (badges, capture confirmations,
  favorites): rejected. Two accent colors is no accent — the gold's job is to
  mark the single row Enter runs, and that job only survives scarcity.
