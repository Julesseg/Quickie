# Liquid Glass is for the chrome, not for the rows

Status: accepted. Supersedes the "result rows are `glassEffect` capsules" half
of ADR 0010; the backdrop, the never-hand-roll rule and the motion budget in
that ADR stand. The replacement material is decided by prototype (#286) and
its verdict is appended here, not written as a further ADR.

## Context

ADR 0010 gave Liquid Glass to "the input bar and result rows", and the glass
spread with the rows: Home's Recent list, the [[Search Files context]]'s rows
and a capture's choice rows all reuse the same regular-interactive glass
inside a blending `GlassEffectContainer`. By the time the iPad work landed,
every row-shaped surface in the launcher was glass, sitting under a glass
input bar, over a backdrop whose contrast had been tuned down so the glass
would stay legible.

Apple's own rule for the material is narrower than that. Liquid Glass is the
**navigation and control layer**: the bars, buttons and chips that float over
content and refract it. Content underneath stays opaque or on a standard
material, and glass is not stacked on glass. A result row is content by that
test — it scrolls, it carries text the user reads (title, [[Match
highlight]], alias pill, caption, region), and it is keyed by rank so it swaps
in place on every keystroke. That every row is tappable does not make it a
control any more than a Mail row is one.

The code had been paying for the mismatch without naming it:

- The long-press menu carries a lifted *copy* of the row as its preview,
  because "the default in-place highlight barely reads against the
  translucent Liquid Glass rows".
- The [[Highlighted result]]'s gold hero glow (ADR 0033, 0034) had to leave
  the backdrop and become an overlay clipped to the row and composited *under*
  its glass, after a circling border "never reliably drew over the row's
  Liquid Glass" and a backdrop glow bled behind the neighbours.
- The blending container's morphs churn SwiftUI's display-list cache at
  automation speed, which is why the UI suite runs with `-uitest-instant-motion`
  at all (`Motion.swift`).

## Decision

**Glass stays on the chrome and leaves the rows.** The test is what the
element *does*: if it floats and gets pressed, it is chrome and wears glass; if
it scrolls and gets read, it is content and does not.

Keeps its glass: the input bar and its [[Clear button]], the [[Clipboard
prefill]] chip, the [[Shelf]]'s buttons, a capture's text field, commit
button, cancel ✕, date-picker panel, breadcrumb crumbs and notice bars, the
confirmation toast, and the [[Favorites grid]]'s cards — a band pinned to the
top of [[Home]], never adjacent to the input bar, read as four launch buttons
rather than as a list.

Loses its glass: every row of a list — the [[Result list]]'s rows, Home's
Recent rows, the Search Files context's rows and the inline capped file rows,
and a capture's choice rows. Home's Recent rows and the result rows change
material *together*, so the first keystroke, which replaces one with the other
in place, never flips material.

**The geometry is frozen; only the material changes.** `QuickieRadius.row`
(25pt, tuned to a single-line row's half height), the 6pt gap between rows,
the 12pt inset a row keeps off the screen or [[Readable command column]] edge
(ADR 0039, asserted by `CommandColumnUITests`), and the [[Pointer hover]]
shape all stay. The winning material ships without touching the column policy
or its tests.

**The replacement material is a prototype's call, not this ADR's.** #286
crosses three row treatments — bare rows over the backdrop, a flat adaptive
fill on the brand's purple axis, a standard system material — with three hero
treatments — a gold-tinted fill that keeps ADR 0034's debounced slide, an edge
light, or a stronger fill plus the ⏎ hint with no shimmer. A single content
sheet holding all rows was rejected before the prototype: the reversed list
grows and shrinks per keystroke, and a panel resizing on every keystroke is
the motion ADR 0010 keeps out. Choosing among the rest needs eyes on a device
in both appearances and both families, which is what a prototype is for.

**The [[Living backdrop]] is unchanged.** Less of it shows while typing, but
the input bar, the Shelf, the paste chip and the Favorites grid still refract
it, Home still shows it whole, and it remains the brand's field colour. Its
glossary entry no longer claims to host the hero glow, which the code had
already moved onto the row.

## Consequences

- ADR 0010's row half is superseded; its backdrop, never-hand-roll and
  budget halves are not. ADR 0034's swing-then-settle hero timing and its
  degradations stand; only the glow's composition is being re-decided. ADR
  0039's "row's glass" inset is the row's inset, whatever it wears.
- The lifted long-press preview may become unnecessary once the in-place
  highlight reads on an opaque row. The implementation ticket #286 files
  revisits it; this ADR does not decide it.
- No UI test asserts glass on a row. `ShelfTintUITests`, the one pixel-level
  glass check, samples the Shelf's buttons and is untouched.
- Rows leaving the `GlassEffectContainer` should reduce automation churn;
  `-uitest-instant-motion` stays because the input bar's and paste chip's
  morphs still use one.

## Considered options

- **Keep glass on rows and lighten it** (the `.clear` variant, or a lower
  tint). Rejected: it is still glass in the content layer, still stacked
  under the input bar's glass, and it keeps every cost above.
- **Take the glass off the Favorites grid too**, for consistency with "rows
  are content". Rejected: the grid is a pinned band of launch buttons at the
  top of Home that never meets the input bar, so neither the glass-on-glass
  nor the legibility argument applies to it.
- **Pick the fill in this ADR.** Rejected: every candidate is cheap to build
  and impossible to judge on paper against a purple mesh in two appearances.
