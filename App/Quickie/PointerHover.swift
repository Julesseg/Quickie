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
/// the same shape the element's `glassEffect`/`contentShape` uses — the row and card
/// faces publish theirs (`ActionRow.shape`, `FavoriteCard.shape`) so a caller can't
/// hover in a shape that has drifted from the one being drawn.
///
/// Apply it to the **control**, not to the face inside it. Several of these faces are
/// also used as the lifted preview of a long-press menu (`resultContextMenu`), and a
/// detached, floating preview card must not light up under the pointer as though it
/// were still a target.
extension View {
    /// Gives this tappable element the system pointer-hover highlight, in `shape`.
    func pointerHover(in shape: some Shape) -> some View {
        // `contentShape(.hoverEffect,)` sets the geometry the highlight morphs into;
        // `.highlight` is the effect that slides the pointer under the element rather
        // than lifting the element off the surface (`.lift`), which is the right one
        // for chrome that is already floating on glass.
        contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
    }
}
