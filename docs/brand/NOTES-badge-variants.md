# Badge-palette variants — prototype notes (#178 / PR #189)

**Question:** the shipped provider-badge ring is one point in a knob-space
(OKLCH lightness, chroma cap, chroma fraction, arc placement). Is it the right
point, or does a different ring read better?

**Tool:** `prototype_badge_variants.py` — six rings (shipped + five single-knob
extremes), rendered as rows on light and dark, each flagged against the CI
invariants. Throwaway; delete with `prototype_badge_palette.py` once decided.

## What the sheets show

| variant | knobs | verdict | reading |
| --- | --- | --- | --- |
| **shipped** | L0.55 c0.17 f0.95 | PASS | even family, white glyph clean on all 15 |
| **muted** | L0.55 c0.11 f0.70 | FAIL ×7 | calmer *does* read as one family — but 7 pairs collapse below the separation floor. Muting trades away the badge's one job (tell 15 kinds apart). |
| **vivid** | L0.55 c0.24 f1.00 | PASS | louder; magentas/reds pop. sRGB caps the cool side, so the ring tilts warm. Viable if we want more energetic chips. |
| **lighter** | L0.62 c0.15 f0.92 | FAIL ×30 | white glyph contrast drops to ~3.4:1 — visibly weak. Demonstrates *why* L is pinned. Nonstarter. |
| **deeper** | L0.48 c0.19 f1.00 | FAIL ×30 | moody; white pops (6–7:1) but chips read heavy in a row and leave the L band. |
| **wide-accent** | L0.55 c0.17 f0.95, arcs pulled off purple | PASS | near-identical to shipped, badges sit further from the accent hue. Essentially-free extra clearance. |

## Verdict

<!-- TODO(jules): fill in the pick before deleting the prototypes. -->

The only rings that both pass CI and stay distinct are **shipped**, **vivid**,
and **wide-accent**. `muted`/`lighter`/`deeper` each fail — and each failure is
the constraint doing its job, which is itself the useful result: the shipped
knobs are pinned where they are for reasons you can now *see*, not just read in
the methodology doc.

- If shipped is right as-is → **keep it**, this prototype confirmed the point.
- Want louder badges → **vivid** (accept the warm tilt).
- Want more accent breathing room at no visual cost → **wide-accent**.
