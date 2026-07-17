# Prototyping an alternate provider-badge palette

A briefing for a fresh session. It captures *how* the shipped badge palette
(issue #178, PR #189) was derived and constrained, so you can explore different
rings without losing the properties that make the current one work. You start
with zero context — everything you need is here or linked.

> **Scope.** This is about the badge *colors* — which hue each provider kind
> wears. The gradient rendering, the shared component, and the radius scale from
> #178 are settled and out of scope; leave them alone. Your job is to try other
> palettes and judge whether one reads better than the shipped one.

---

## The problem the palette solves

A Result row's leading **provider badge** is a colored squircle with a white SF
Symbol. Its one job is *identity*: which provider did this row come from, at a
glance. There are **15 `ActionKind`s**, so there are 15 badges, and they must be
tellable apart from each other — and must sit *with* the app's purple accent
rather than fighting it.

The palette this replaced used raw SwiftUI system colors and failed that job on a
third of the kinds: three shared `.gray`, two shared `.brown`,
`customAction`/`shortcut` both used `.indigo`, and `quicklink` sat on the `.blue`
that had become the accent. So "which provider?" was unanswerable for those rows.

## Why OKLCH, not HSL or hand-picking

The whole method rests on working in **OKLCH** (a perceptual color space) rather
than HSL or eyeballing hex values:

- **Equal steps look equal.** A 20°-hue step in the greens is barely visible; the
  same step in the magentas is obvious. HSL lies about this; OKLCH doesn't. So
  "space the hues evenly" only means something in OKLCH.
- **Lightness, chroma, and hue are independent.** You can hold legibility fixed
  (lightness) while varying only the identity-carrying channel (hue). In HSL,
  changing hue at fixed "lightness" silently changes how light the color reads.
- **It exposes the sRGB gamut honestly.** A vivid teal at mid-lightness simply
  cannot exist in sRGB the way a vivid magenta can. OKLCH lets you find each
  hue's real ceiling instead of picking a chroma that clips on half the wheel.

If you take one thing from this doc: **don't pick hex values by hand.** Pick the
*rules*, let the tool place the colors, then judge the result and adjust the
rules — not the individual swatches.

## The constraint system (five rules)

The shipped ring is built to these. They are what a candidate palette has to keep
to still do the badge's job; they are not the *only* palette those rules allow, so
there is real room to explore inside them.

1. **One lightness for the whole set (OKLCH L = 0.55).** Every badge carries a
   white glyph, so every badge owes it the same legibility. Fixing lightness pins
   white-glyph contrast into a tight band (the shipped set is 4.5–5.4:1) and
   leaves **hue as the only channel that varies** — which is the channel that
   *means* something. It also makes 15 colors read as one family instead of 15
   separate decisions. (This is also why the badges are flat literals, not an
   adaptive light/dark pair like the accent: an opaque color at this lightness
   sits correctly on both appearances.)

2. **Chroma to each hue's full gamut ceiling, capped (0.24).** Push each hue as
   saturated as sRGB allows *at that lightness* (`--chroma-frac 1.0`), then cap it.
   This is the *vivid* end of the dial — the shipped ring was picked here (PR #189)
   after a side-by-side against a muted alternative, because muting collapsed too
   many kind-pairs below the separation floor. The teals top out around 0.09, so
   the cool arc stays quieter than the warm one and the family tilts warm — an
   accepted trade for bolder badges. The 0.24 cap only binds on the magentas, whose
   ceiling runs higher; it stops the loudest hues from leaving the family entirely.

3. **Space by perceptual difference, not hue angle.** Place the hues at equal
   OKLab arc-length along the allowed ring, so no neighbour-pair is much closer
   than any other. Equal *degrees* would crowd the greens and waste the magentas
   (see "Why OKLCH").

4. **Two arcs are off-limits — this is why the ring has gaps.**
   - The **accent's hue** (OKLCH ~290°: `lightAccent` 289.7°, `lavender` 296.4°)
     is left empty, so a badge never reads as a *broken accent*. This is the exact
     failure the old palette had.
   - **Gold's hue** (~84°) is left empty, because ADR 0033 spends gold in exactly
     one place — the Highlighted result's hero glow — and a gold-ish badge would
     be the "gold as a secondary accent" that ADR explicitly rejected.

   So the ring runs **104°→255°** and **325°→64°**, and the badges *flank* the
   accent rather than competing with it.

5. **No two kinds share a hue, and each is visibly distinct.** Enforced as a
   minimum OKLab distance (0.030) between any two badges — "distinct" meaning
   *perceptually*, not just "different hex."

There is also a semantic layer the geometry can't know about, encoded by the
**order** kinds sit in around the ring (`KIND_ORDER` in the script): related kinds
are placed as neighbours so they *look* related — `file`/`searchFiles` (same
content), `snippet`/`newSnippet` (the thing and the action that makes it),
`reminder`/`event` (EventKit twins), `customAction`/`quicklink` (ADR 0030: one
provider, two shapes). And `saveForLater` is kept well clear of `pile`, because a
row must never read as the entries it creates. If you reorder the ring, preserve
those adjacencies or decide deliberately to change them.

## The executable guard: `check-brand-assets.py`

There is **no app-side unit-test target** (App logic is exercised via Core's
`swift test` and the CI XCUITest suite, and ADR 0033 keeps `QuickieCore`
color-free). So the palette's invariants live in **`docs/brand/check-brand-assets.py`**,
which the CI `brand-assets` job runs on every full run. Its `badge_failures()`
enforces, against the real code:

- **Coverage** — every `ActionKind` (read from `Core/Sources/QuickieCore/Action.swift`)
  names a badge hue in `ActionIcons.swift`.
- **Uniqueness** — no two kinds name the same `QuickieBrand.badge*` token.
- **No dead hues** — every `badge*` literal is used by some kind.
- **Lightness band** `(0.53, 0.57)` and **white-contrast band** `(4.4, 5.6)`.
- **Perceptual separation** — OKLab distance ≥ `0.030` between any two.
- **Accent clearance** ≥ 25° from both accent hues; **gold clearance** ≥ 20°.

It matches literals **by name** (`badgeFile`, `badgeSnippet`, …), so the module
can grow constants without disturbing the separate icon-derivation check. It was
mutation-tested: each invariant fails on a targeted regression (a shared hue, a
badge on the accent's hue, a gold-ish badge, an over-light badge, two hues nudged
too close, a new unwired kind).

**Implication for you:** any candidate you like must still pass this script. The
bands are deliberately tight around the shipped choices. If your exploration
needs a *different lightness* (say L = 0.58), that is legitimate — but you must
widen `BADGE_LIGHTNESS` (and probably `BADGE_WHITE_CONTRAST`) **in both**
`check-brand-assets.py` **and** the prototype script, and justify the new bound
here. Don't just loosen the check to make a palette pass; the check is the point.

## The prototyping loop: `prototype_badge_palette.py`

`docs/brand/prototype_badge_palette.py` is a standalone design tool (stdlib +
optional Pillow). It builds a ring from the knobs above, prints a paste-ready
Swift block, renders swatches on light **and** dark backdrops, and runs the same
invariants as CI. Run with no args and it reproduces the shipped palette exactly
and prints `READY`.

```
python3 docs/brand/prototype_badge_palette.py                       # shipped palette (vivid)
python3 docs/brand/prototype_badge_palette.py --chroma-cap 0.13     # muter
python3 docs/brand/prototype_badge_palette.py --lightness 0.58 ...  # needs band widening (see above)
python3 docs/brand/prototype_badge_palette.py --no-render           # skip PNGs / Pillow
```

The knobs, and what each explores:

| Knob | Default | What moving it does |
|------|---------|---------------------|
| `--lightness` | 0.55 | Darker/lighter whole set. Trades contrast headroom for vividness. **Requires band edits** to pass the check. |
| `--chroma-cap` | 0.24 | How saturated the richest hues get. Higher = bolder, and lets the magentas pull ahead of the teals. |
| `--chroma-frac` | 1.00 | How close each hue hugs its own gamut ceiling. Below ~0.85 the set goes dusty. |
| `arcs` (in `main()`) | `[(104,255),(325,424)]` | The allowed ring. **Widen the gaps** to give the accent or gold more breathing room; narrow them to fit hues more loosely. The gaps *are* the reserved zones. |
| `KIND_ORDER` | (top of file) | Which kind lands in which neighbourhood. Reorder to change semantic adjacencies. |

**Workflow:** change knobs → look at `badge_palette_dark.png` and
`badge_palette_light.png` → read the `READY`/`FAIL` line → iterate. When you like
one and it says `READY`, paste the printed Swift block into `QuickieBrand.swift`
(replacing the `// MARK: - The provider-badge palette` block) and run the real
check to confirm.

## Files that matter

- `docs/brand/prototype_badge_palette.py` — the design tool. Start here.
- `docs/brand/badge-palette-methodology.md` — this document.
- `docs/brand/check-brand-assets.py` — the CI guard; `badge_failures()` and the
  `BADGE_*` thresholds near the top. Keep it and the prototype script in sync.
- `App/QuickieEntry/QuickieBrand.swift` — where the 15 `static let badge*`
  literals live (the `// MARK: - The provider-badge palette` block). This is the
  only file you edit to change the palette.
- `App/QuickieEntry/ActionIcons.swift` — `ActionKind.tint` maps kind → token.
  You only touch this if you add/rename a kind or token, not to recolor.
- `Core/Sources/QuickieCore/Action.swift` — the 15 `ActionKind` cases, with a
  comment on each explaining what it is (useful for deciding adjacencies).
- `docs/adr/0033-brand-accent-derived-from-the-icon.md` — the accent/gold rules
  the reserved arcs come from. **Read this** before moving a reserved zone.
- `docs/adr/0010-glass-over-quiet-backdrop.md` — depth is the glass's job (why the
  badge has no drop shadow, only a gradient). Don't reintroduce shadows.

## How to apply a palette you've chosen

1. Get `READY` from the prototype script; eyeball both PNGs.
2. Paste the printed `static let badge*` block into the palette section of
   `App/QuickieEntry/QuickieBrand.swift`.
3. `python3 docs/brand/check-brand-assets.py` → expect `brand assets in sync`.
4. If you changed the lightness/contrast band, edit the `BADGE_*` constants in
   `check-brand-assets.py` to match and note why in this doc.
5. `cd Core && swift test` (should be untouched — sanity only) and, on a Mac,
   optionally the app build. No UI test asserts on color (the badge is
   `accessibilityHidden`), so the suite is unaffected; CI's XCUITest job is the
   gate.

## Constraints (do not violate)

- **All 15 badge hues stay in `QuickieBrand`** (ADR 0033: one module owns every
  brand literal). No color literals in `ActionIcons.swift` or elsewhere.
- **`QuickieCore` stays color-free** (ADR 0033). The kind → look mapping is an App
  concern.
- **Never occupy the accent's hue or gold's hue** without moving the reserved
  arcs deliberately and updating ADR 0033's reasoning — those gaps are load-
  bearing, not decorative.
- **No hand-rolled shadows** on the badge (ADR 0010) — the gradient is the only
  depth cue, and it's already implemented.
- **Keep the prototype script and the CI check in agreement.** A palette that
  passes one must pass the other.
