# The launcher's command surfaces share one readable column

## Context

Quickie ships universal, and since ADR 0038 the UI suite runs on an iPad as
well as an iPhone. An iPad UI audit (branch `prototype/ipad-ui-audit`, report
`ipad-report/index.html`) drove the app on a 13" canvas and found the same
defect on every command surface at once (finding F1): the input bar, the
[[Shelf]], the paste chip, the [[Result list]], the [[Search Files context]]'s
rows and a capture's breadcrumb are all `maxWidth: .infinity` with a 12–16pt
inset, so each one stretches the full 1,376pt of the window. A ranked result
row puts its label at the far left and its main-action glyph at the far right
with ~85% of the row empty between them — the eye has to travel the window to
connect a result to what tapping it does.

Two downstream rules degrade with it rather than independently:

- The breadcrumb gives each crumb an equal weighted share of the width it is
  handed (F3), so a one-word `DUE DATE` becomes a ~450pt card.
- The [[Shelf]]'s peek sizing solves for a diameter at which *k* buttons plus
  half of the next exactly span the row (ADR 0037). Handed a 1,376pt row it
  always resolves to the preferred diameter, never scrolls, and the
  half-button cue that says "there are more" disappears (F10).

Neither is a bug in those rules. Both are the same rule being handed a width
no phone ever produced.

## Decision

**The launcher's command surfaces lay out inside one centred, readable-width
column on a regular-width window.** The surfaces are the input bar, the Shelf,
the paste chip, the Result list's rows, [[Home]]'s Favorites grid and Recent
list, the Search Files context's rows and breadcrumb, and a capture's
breadcrumb crumbs and bottom bar. The column is **680pt**, tracking UIKit's readable-content guide, which tops out in the same
neighbourhood for the same reason a line of text does.

**The switch is the horizontal size class, never the device idiom.** A
half-screen iPad window and a narrow Stage Manager window are compact and must
come out identical to the iPhone; the same window dragged wide must become a
column, and dragged narrow must revert, with nothing torn down in between. An
idiom check gets both of those wrong permanently, because the idiom never
changes. This is the same boundary SwiftUI itself adapts on (ADR 0038), so
the column moves with the sheet, the popover and the split view rather than
against them.

**The decision lives in `QuickieCore.CommandColumn`, not beside a view.**
`maxWidth(for:)` answers with the cap or `nil`, and `columnWidth(inWindowOf:for:)`
resolves it against a real window — which is what lets `swift test` assert the
thing that actually matters downstream: that the Shelf's solver is handed the
*column's* width, and its peek comes back. One number, one switch, tested,
consumed by every surface. A column the results share but the input bar misses
by 8pt is worse than no column: the whole effect is one edge running down the
screen through every surface, and a near-miss is what the eye lands on.

**`nil` means "no cap", not "a cap wider than any window".** The compact path
applies the same `.infinity` frame that shipped before this policy existed, so
"pixel-identical to today" is structural rather than arithmetic.

**The column edge stands in for the window edge; every surface keeps its own
inset off it.** A result row's and the input bar's glass stay 12pt inside it, a
breadcrumb's crumbs 16pt — exactly the insets they keep off an iPhone's screen
edge, so the relationships between the surfaces are carried over rather than
renegotiated. In practice that means the clamp is applied *outside* a surface's
own horizontal padding.

Home is included for the reason the column exists at all: it is the launcher's
*default* screen, and it is the one place the mismatch shows without typing
anything — a centred input bar over an edge-to-edge Recent list. Its Favorites
grid clamps as a container here; how many columns that grid lays out at regular
width is a separate decision (#265), not this one. *(#265 has since answered it
inside this policy rather than beside it: `CommandColumn.FavoritesGrid` — four
across at regular width, the 2×2 at compact, keyed off the same size class and
never off the number of pinned Favorites. CONTEXT.md → Favorites grid.)*

**Only content clamps.** The [[Living backdrop]] and the progressive-blur bands
still span the whole window: the clamp's outer frame stays full-width, so a
background applied outside it (`statusBarBleed`) is unaffected. A blur band
that stopped at the column would draw the column's two edges as hard lines,
which is exactly the chrome ADR 0010 keeps out — depth is the glass's job.

## Consequences

- The Shelf's peek cue returns on a full-screen iPad with no change to
  `FallbackShelf.Layout`, and the breadcrumb's equal-share maths divides the
  column instead of the window. Only the first of those is *asserted*: the
  Shelf's solver is a Core rule, so a test can hand it the column's width and
  check the peek comes back. The breadcrumb's weighting lives in the App
  (`BreadcrumbSteps`) and is not covered — the clamp fixes F3 by construction,
  by handing that maths a narrower container, but nothing pins it.
- Compact width is untouched, so the iPhone suite is the regression gate it
  always was; the iPad leg of the matrix (ADR 0038) is what covers the new
  branch, and `CommandColumnUITests` asserts the shared centre line on both.
- Surfaces outside the launcher — the pushed [[Management page]]s, the editor
  sheets — are not covered here. They reuse this policy in their own tickets
  (#266, #264) rather than growing a second width constant. *(#266 has since
  done exactly that for every pushed management page — the Settings hub, the
  provider pages, Custom Actions, Fallbacks, Snippets, Shortcuts and a
  shortcut's detail page, File Search, the Pile, the Catalog, and the Symbol &
  Color page. The clamp rides the page's `List`/`Form`, not its rows, so the
  grouped style's own margins are measured against the column instead of the
  window; the one thing added is the full-bleed layer, which a management page
  does not have a backdrop to supply — the App restates the list's grouped
  background outside the clamp, exactly the "only content clamps" split above.
  The editor sheets stay out: they present ~540pt wide, which is compact, and a
  cap can only subtract.)*

## Considered options

- **Clamp on device idiom (`UIDevice.userInterfaceIdiom == .pad`).** Rejected:
  it is wrong for every iPad multitasking configuration, and wrong in a way
  that cannot self-correct — the idiom is fixed for the process's life, so a
  window dragged to half-width would keep a 680pt column inside a ~500pt frame.
- **Keep the constant in the SwiftUI modifier.** Rejected: it is a number every
  surface must agree on, and the only way to prove they do — and that the
  Shelf's and breadcrumb's downstream maths sees it — is a test that doesn't
  need a simulator.
- **`.frame(idealWidth:)` / `readableContentGuide`.** UIKit's readable-content
  guide is the right *reference*, but it is a UIKit layout guide with no direct
  SwiftUI equivalent, and its width is derived from the font's point size — a
  moving target that would make a row's width depend on Dynamic Type. A pinned
  point value is inspectable, testable, and identical across text sizes.
- **A wider column, or none, in landscape.** Rejected: the column is about how
  far the eye travels between a row's two ends, which orientation doesn't
  change. One number keeps the surfaces aligned in both.
- **Clamp inside each surface's padding instead of outside it.** Rejected: it
  compresses each surface's own inset by a different amount, so the input bar's
  glass and a result row's glass stop lining up — the near-miss above.
