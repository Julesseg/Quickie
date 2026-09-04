import SwiftUI

/// The launcher's **pointer hover** treatment (CONTEXT.md → Pointer hover; issue #263),
/// applied to a tappable element: with a trackpad or mouse attached, the system
/// highlight slides under the pointer as it crosses the element and morphs to the
/// element's own shape. With a finger it does nothing at all — a hover effect only ever
/// exists while a pointer does, so the touch layouts are byte-identical either way.
///
/// It takes the shape explicitly rather than defaulting to the view's bounds because a
/// rectangular highlight sitting behind a 25pt-radius result row or a circular Shelf
/// button is worse than no highlight: it draws corners the element doesn't have. Pass
/// the same shape the element draws its own face in — its `glassEffect` if it is
/// chrome, its background fill if it is a row (ADR 0042), and its `contentShape`
/// either way. The row and card faces publish theirs (`ActionRow.shape`,
/// `FavoriteCard.shape`) so a caller can't hover in a shape that has drifted from the
/// one being drawn; taking the material off the rows changed neither.
///
/// Apply it to the **control**, not to the face inside it, so the highlight covers the
/// whole target rather than only what is drawn within it.
///
/// It is **not** a moment in the animation budget (ADR 0010) and takes no
/// `MotionPolicy` degradation, unlike every animation the app authors. The highlight is
/// the system's, drawn by UIKit's pointer machinery in response to hardware the app
/// never sees; there is no curve here to tune, and Reduce Motion is honoured upstream
/// by the same machinery. The budget governs what Quickie animates, and Quickie does
/// not animate this.
extension View {
    /// Gives this tappable element the system pointer-hover highlight, in `shape`.
    ///
    /// `isEnabled: false` leaves the element inert to the pointer — for a control that
    /// is only *sometimes* a control (the confirmation toast, which is tappable only
    /// when it has somewhere to go). It is a parameter rather than an `if` around the
    /// modifier so the view keeps one identity across the switch and an in-flight
    /// transition isn't cut short by SwiftUI rebuilding it.
    func pointerHover(in shape: some Shape, isEnabled: Bool = true) -> some View {
        // `contentShape(.hoverEffect,)` sets the geometry the highlight morphs into;
        // `.highlight` is the effect that slides the pointer under the element rather
        // than lifting the element off the surface (`.lift`), which is the right one
        // for chrome that is already floating on glass.
        contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight, isEnabled: isEnabled)
    }
}
