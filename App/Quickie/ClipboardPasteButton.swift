import SwiftUI

/// The icon-only paste control offered to the *right of the input* on Home when
/// the clipboard holds text (CONTEXT.md → Clipboard prefill; ADR 0002). It is
/// backed by the system paste control — SwiftUI's `PasteButton`, the front-end to
/// `UIPasteControl` — which reads the clipboard *only* when tapped and never
/// raises the "pasted from…" banner. Nothing here touches `UIPasteboard.string`;
/// the content arrives only through the user's tap, then seeds the input and the
/// button retires for the session (the seeded, non-empty query leaves Home).
///
/// It is a bare Liquid Glass circle. `PasteButton` is a UIKit-backed control that
/// ignores `buttonStyle`, so its prominent (blue) fill can't be removed that way;
/// instead `.tint(.clear)` clears that fill, leaving just the icon over our own
/// `glassEffect`. `glassEffectID` pairs that surface with the input's
/// (`InputBar.glassID`) inside the bottom `GlassEffectContainer` — sharing one
/// namespace is what makes the button *morph out of and back into* the input's
/// capsule as it is offered and withdrawn, rather than just popping.
///
/// It sizes itself to the input's height (`maxHeight: .infinity` against the
/// bottom row, then a 1:1 `aspectRatio`) so the two read as one consistent body,
/// while the `Circle()` glass keeps it round whatever that height is.
struct ClipboardPasteButton: View {
    /// Stable identity for this button's Liquid Glass within the bottom
    /// `GlassEffectContainer`, paired with `InputBar.glassID` to drive the morph.
    static let glassID = "clipboard-paste"

    /// The shared namespace the bottom glass surfaces morph within — pairs this
    /// button's glass with the input's so SwiftUI interpolates one into the other.
    var glassNamespace: Namespace.ID

    /// Delivers the pasted text to the host on tap. The host seeds the input and
    /// retires the button for the session — the button itself stays content-unaware
    /// beyond this single hand-off.
    let onPaste: (String) -> Void

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            // Reached only on an explicit tap of the system paste control, so
            // this is the first and only moment any content is read.
            guard let text = strings.first else { return }
            onPaste(text)
        }
        .labelStyle(.iconOnly)
        // Clear the system paste control's prominent (blue) fill so only the icon
        // shows; our glass below is the button's single surface and the only shape
        // the morph has to interpolate.
        .tint(.clear)
        .font(.title3)
        // Match the input's height, then square it up so the glass stays a circle.
        .frame(maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .glassEffect(.regular.interactive(), in: Circle())
        .glassEffectID(Self.glassID, in: glassNamespace)
        .accessibilityIdentifier("clipboard-paste-chip")
    }
}
