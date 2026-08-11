# PROTOTYPE — Custom Action color picker UX variants

**Question:** what should the Custom Action color picker feel like? The shipped
one (a pushed grid of checkmark swatches, `ActionColorPickerView`) reads flat.

**How to evaluate:** DEBUG build → Settings → Custom Actions → create/edit an
action. A floating ◀ ▶ pill at the bottom of the editor cycles three variants
of the Color control (persisted across pushes/relaunches):

- **A — Inline strip:** the Color row expands in place into a horizontal strip
  of circular swatches. Zero navigation; the badge preview in the Symbol row
  above updates live as you tap.
- **B — Live preview:** pushed page with a large composed badge (your symbol on
  the candidate color) as the hero; swatches below restyle it live, Back
  confirms.
- **C — Badge list:** pushed page of full-width rows, each showing the real
  composed badge in that color beside its name; tap selects and pops.

**Files:** `PrototypeColorPickerVariants.swift` + two `#if DEBUG` blocks in
`CustomActionEditorView.swift`.

**Verdict:** _(fill in: winning variant — or the mix, e.g. "A's inline strip
but with B's live badge above it" — then fold it in properly and delete the
prototype files and DEBUG blocks.)_
