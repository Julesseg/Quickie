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

## Verdict (prototype #286)

**Rows wear a flat adaptive fill (b); the Highlighted result wears a gold
edge light (ii).** Judged on a 13" iPad Pro and an iPhone 17 Pro, light and
dark, across Home, a ranked list, a long list and a calculator result, with
the hero filmed settling after typing. Evidence: branch
`prototype/row-material`, `row-material-report/index.html`. Implementation:
#288.

*Row treatment.* The flat fill is one step up the purple axis in each
appearance (ADR 0033), so a row keeps the pill the input bar and the Favorites
cards share, and the launcher reads as one family in two layers: the glass
floats, the cards sit. Text, the [[Match highlight]] bolding, the alias pill
and the caption are at full contrast in both appearances.

**Amended during #288:** "one step" is not the same *lightness* step in each
appearance, and taking it as one shipped a light row that read as a white slab
on a lavender field. Against the near-black mesh there is a whole range to lift
into; against the near-white wash there is almost none, so an equal lift lands
on white and the row leaves the purple axis altogether — half the chroma of its
own field. What is held equal instead is the **separation** the eye actually
reads: each row now sits about 1.22:1 off the mesh average behind it, which is
what the dark row always had. On light that is a much smaller lift, and the row
stays purple.

- The **system material** lost because it is two different things: in light it
  is indistinguishable from the flat fill (a blur behind a near-white card
  blurs a near-white wash), and in dark it desaturates every row to neutral
  grey, taking the purple field off the one surface the eye reads. It also
  costs a blur per row for a look the fill gives for free.
- **Bare rows over a hairline** lost in dark: on the near-black mesh the
  hairline barely registers, the rows lose their shape, the list reads as
  floating text, and the hero, now the only row with a fill, reads as an
  orphan pill. The [[Pointer hover]] and the long-press highlight both need a
  shape to light.

*Hero treatment.* The ring keeps gold at full opacity in a 1.5pt edge with a
soft halo. It reads as light in both appearances and both families, the hero's
own fill stays clean so its text contrast equals its neighbours', and ADR
0034's swing-then-settle survives as a bright point travelling the edge. It
carries from across the screen because gold is the only warm hue on the
screen. ADR 0034 records a circling gold border that "never reliably drew over
the row's Liquid Glass"; over a flat card it draws every time. That failure
was the glass's.

- The **gold-tinted fill** was the best of the three in light and failed in
  dark on every row treatment: gold and purple are near-complements, so any
  partial-alpha gold over the purple card mixes to mauve, and the hero reads
  as a stained row rather than a lit one, with the slide a brownish smear.
- The **stronger fill with no shimmer** is the same stain, larger, in both
  appearances, and drops ADR 0034's motion for nothing, since the ⏎ hint was
  already on every hero.

*Also found.* With the lifted preview removed, the system's in-place
long-press highlight lifts the pressed flat row at full width and contrast
while the rest dims: it reads, so the preview can go. The preview is also
`ContextMenuPresence`'s only signal, so the implementation must hook the
menu's presence elsewhere first. Rows leaving the `GlassEffectContainer`
changed nothing visible on a keystroke. Pointer hover was not exercised
(nothing in `simctl` or XCUITest drives a pointer); the shape is unchanged,
so the highlight should be, and #288 checks it on hardware.
