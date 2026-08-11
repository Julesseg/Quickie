# Handoff: implement the merged Symbol & Color picker (prototype variant D)

## Task

Implement, properly and for production, the **merged "Symbol & Color" page** for
the Custom Action editor — the design validated as **variant D** of the
`prototype/color-picker-variants` branch — replacing the editor's current two
separate pickers (Symbol → `GlyphPickerView`, Color → `ActionColorPickerView`)
with one page. Include the two refinements flagged during prototyping:

1. **Pinned hero** — the large composed badge preview must stay visible while
   the glyph gallery scrolls (pin it, or collapse it to a compact version on
   scroll), instead of scrolling away as it does in the prototype.
2. **Glyph search** — the merged page must keep the shipped glyph picker's
   fuzzy search (`CustomActionGlyphCatalog.search`, the shared `Matcher`
   furniture), which the prototype omitted. A search field above the gallery,
   same ranking as the current `GlyphPickerView`.

Then delete the prototype (see Current state) and fill in its verdict.

## Context

The user disliked the shipped color picker UX (a pushed grid of checkmark
swatches). A `/prototype` session built four variants behind a DEBUG-only
floating pill; the user reviewed live simulator screenshots and chose **D**:
one pushed page where a large live composed badge (chosen SF Symbol on chosen
color) is the hero, with the color circles beneath it and the full glyph
gallery under those. Tapping any swatch or glyph restyles the hero instantly;
Back confirms. The selected glyph cell tints itself with the *current color
choice* (not the app accent) so the gallery echoes the hero.

Domain docs: `CONTEXT.md` → Custom Action, Action color; issues #163 (glyph),
#243 (color). The palette and its legibility rules live in Core
(`Core/Sources/QuickieCore/ActionColor.swift`) — do not touch them.

## Relevant files

- `App/Quickie/PrototypeColorPickerVariants.swift` — the prototype. Variant D
  is `VariantDMergedAppearance` (bottom of file): use it as the visual spec,
  then **delete this file**. The pill (`ColorPickerPrototypeSwitcher`),
  `PrototypeColorRow`, and `PrototypeSymbolRowGate` all go with it.
- `App/Quickie/CustomActionEditorView.swift` — the editor. Contains the
  shipped `GlyphPickerView`, `ActionColorPickerView`, `ActionColorSwatch`,
  `GlyphCell`/`GlyphClearCell`, and `ActionColorCell` (replace the two pushed
  pickers with the merged page; the two form rows collapse to one). Also
  contains two `#if DEBUG` prototype blocks (in `symbolSection` and the
  `.overlay` on the NavigationStack) and a `shippedSymbolRow` extraction —
  remove the DEBUG blocks with the prototype.
- `App/Quickie/PROTOTYPE-NOTES.md` — the prototype's question + verdict
  placeholder. Record the verdict ("D — merged page, with pinned hero and
  glyph search"), then delete it along with the prototype (the verdict's
  durable home is the implementation commit/PR message).
- `App/QuickieUITests/PrototypeScreenshotTests.swift` — throwaway screenshot
  test; delete.
- `App/QuickieUITests/CustomActionUITests.swift` — real UI acceptance tests.
  They reference `custom-action-symbol-row` / `custom-action-color-row`
  identifiers indirectly via the editor flow; check and update any test that
  navigates the Symbol or Color rows to the new merged row.
- `App/QuickieEntry/ActionIcons.swift` — `ProviderBadge`,
  `resolvedActionTint(kind:color:tint:)`, `ActionColor.swiftUIColor`. Reuse;
  do not duplicate.
- `Core/Sources/QuickieCore/CustomActionDefinition.swift` — the editor's view
  model (`glyph`, `color`, `normalizedGlyph`). No Core changes expected.

## Current state

- Branch `prototype/color-picker-variants` (pushed) holds the working
  prototype: 4 variants behind a DEBUG pill, plus the screenshot test.
  **Prototype code is throwaway by design — reimplement D cleanly rather than
  promoting the prototype structs.** Base the real work on `main` (or the
  branch the team prefers), not on the prototype branch.
- The shipped pickers are untouched and still what release builds show.
- Screenshots the user approved: `/tmp/proto-shots2/` (variant-D-merged-page).

## What was tried

- Variants A (inline swatch strip in the form), B (live-badge hero + colors
  only), C (full-width badge list) — all rejected in favor of D, which is B
  plus the glyph gallery underneath.
- Prototype D's hero scrolls away with the gallery — that is the motivation
  for the pinned-hero requirement, not an accepted behavior.

## Decisions

- One page for both symbol and color; one editor row opens it (the editor's
  Symbol/Color section footer text will need rewording to match).
- Hero = `ProviderBadge` composed exactly as surfaces render it
  (`normalizedGlyph` + chosen color + derived kind), live-updating, no
  auto-dismiss; Back confirms. The prototype scaled the badge with
  `.scaleEffect(2.8)` — implement a properly sized badge instead.
- Selected glyph cell highlights in the resolved action tint
  (`resolvedActionTint`), not `Color.accentColor`.
- "Default" (color) and "None" (symbol) reset cells lead their respective
  groups, per the existing pickers' convention (the reset is never buried).
- Keep the existing accessibility identifier conventions
  (`glyph-option.*`, `action-color-option.*`) or migrate the UI tests with
  them — CI's `App · XCUITest (macOS)` job is the gate.

## Acceptance criteria

- [ ] One "Symbol & Color" row in the editor pushes the merged page; the two
      old rows and pushed pickers are gone.
- [ ] Hero badge stays visible (pinned or compact-on-scroll) while the glyph
      gallery scrolls.
- [ ] Glyph fuzzy search works on the merged page, ranked like the current
      `GlyphPickerView` (`CustomActionGlyphCatalog.search`).
- [ ] Color and symbol taps restyle the hero live; selection state is visible
      on both grids; Default/None resets work.
- [ ] All prototype files, DEBUG blocks, and the screenshot test are deleted;
      `PROTOTYPE-NOTES.md` verdict recorded (then removed with the prototype).
- [ ] `cd Core && swift test` passes; `CustomActionUITests` updated for the
      new navigation and passing (CI is the canonical UI gate).
- [ ] Session ends with commit → push → PR (Conventional Commits title).

## Constraints

- Do not modify Core's `ActionColor` palette or its contrast tests.
- Do not change `ProviderBadge`'s API beyond what composition requires — the
  badge is shared with widgets and the Shelf.
- The stored model is unchanged: `glyph: String?` + `colorToken` stay as-is.
- Never commit to `main`; do not base the PR on the prototype branch.
