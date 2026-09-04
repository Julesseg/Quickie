import SwiftUI

/// The **row material** (ADR 0042; CONTEXT.md → Result list): the flat fill every
/// list row in the launcher draws behind its content — the [[Result list]]'s rows,
/// [[Home]]'s Recent rows, the [[Search Files context]]'s rows and a capture's
/// choice rows.
///
/// A row is *content*, not chrome: it scrolls, and it carries text the user reads.
/// So it is not Liquid Glass — the glass stays on the bars, buttons and chips that
/// float over content and refract it — and it is not a blurring material either.
/// It is one opaque-ish colour a step up the brand's purple axis from the [[Living
/// backdrop]] behind it, so a row reads as a card lifted off the field.
///
/// A modifier rather than a `.background` at each call site, for the same reason
/// `pointerHover(in:)` is one: the *value* is what has to be shared. ADR 0042 turns
/// on Home's Recent rows and the result rows changing material together — the first
/// keystroke swaps one list for the other in place, and a difference of a shade
/// would show as a flicker — and two call sites each spelling out a fill are two
/// places for that to drift. The colour itself lives one level further down, in
/// `QuickieBrand.rowFill` (ADR 0033: no brand colour literal outside that module).
///
/// It takes the shape for the same reason the hover does: a row draws a
/// 25pt-radius pill and a capture's choice row draws a capsule, and a fill in the
/// wrong shape shows at the corners.
extension View {
    /// Fills `shape` behind this row with the shared row material.
    func rowMaterial(in shape: some Shape) -> some View {
        background {
            shape.fill(QuickieBrand.rowFill)
        }
    }
}
