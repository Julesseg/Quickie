import SwiftUI

/// The icon-only paste control offered to the *right of the input* on Home when
/// the clipboard holds text (CONTEXT.md → Clipboard prefill; ADR 0002). It is
/// backed by the system paste control — SwiftUI's `PasteButton`, the front-end to
/// `UIPasteControl` — which reads the clipboard *only* when tapped and never
/// raises the "pasted from…" banner. Nothing here touches `UIPasteboard.string`;
/// the content arrives only through the user's tap, then seeds the input and the
/// button retires for the session (the seeded, non-empty query leaves Home).
///
/// It is a bare Liquid Glass circle: `.buttonStyle(.plain)` strips the system
/// paste control's own chrome so the only surface is our `glassEffect`, and
/// `glassEffectID` pairs that surface with the input's (`InputBar.glassID`) inside
/// the bottom `GlassEffectContainer`. Sharing one namespace is what makes the
/// button *morph out of and back into* the input's capsule as it is offered and
/// withdrawn, rather than just popping.
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
        // Defer the surface to our own glass so the button is a clean Liquid Glass
        // circle and the morph has a single shape to interpolate.
        .buttonStyle(.plain)
        .font(.title3)
        .padding(14)
        .glassEffect(.regular.interactive(), in: Circle())
        .glassEffectID(Self.glassID, in: glassNamespace)
        .accessibilityIdentifier("clipboard-paste-chip")
    }
}
