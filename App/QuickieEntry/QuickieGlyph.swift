import SwiftUI

/// The **Quickie mark** — the app icon's orbital Q, isolated as a custom SF
/// Symbol in `Brand.xcassets` — and the single glyph that stands for "Quickie"
/// wherever the app names itself.
///
/// Every widget-extension [[Entry surface]] renders it for "open Quickie": the
/// deep-link widget (`EntryWidget`, #124), the widget placeholders (Favorites
/// #126, Actions ADR 0027), and both Control Center controls
/// (`QuickCaptureControl` #125, `ActionControl` ADR 0027) — so the entry surfaces
/// can never drift onto different glyphs. It replaced the placeholder magnifying
/// glass from before the brand mark existed. A custom symbol — not a plain image
/// — because Control Center renders only symbol images; as a symbol it tints,
/// scales, and renders vibrantly on the Lock Screen exactly like a system one.
///
/// The **app** target renders it too, in exactly one place: the pre-anything
/// Home's brand mark (`HomePlaceholder`, ADR 0034). That is why this file and its
/// catalog sit in the folder synced into both targets rather than in the widget
/// extension where they started — the mark a user meets on the Home Screen and
/// the mark they meet inside the app are the same mark, and one symbolset is what
/// keeps that true (the same argument `QuickieBrand` makes for the palette).
/// Being a template symbol is what lets Home paint it in the brand ramp
/// (`QuickieBrand.adaptiveMarkGradient`) while a control tints it its own way.
///
/// The icon trail's **fade rides inside the symbol**: the orbit is cut into
/// layers whose per-layer `opacity` eases up along the trajectory (see
/// `docs/brand/make-quickie-mark.py`). Baked-in layer opacity is the one styling
/// channel that reaches Control Center, which resolves only the symbol
/// *reference* and applies its own tint — view-level styling like a
/// `foregroundStyle` gradient never arrives there, and a symbol template cannot
/// hold color gradients at all (solid fills only), so the fade carries the
/// icon's motion everywhere and `QuickieBrand.markGradient` adds the color ramp
/// where SwiftUI styling does apply. The symbolset's SVG must stay a
/// *canonical* SF Symbols template (the layout the SF Symbols app exports, with
/// the layer classes `monochrome-N` / `hierarchical-N:primary` /
/// `multicolor-N:tintColor` on every variant path) — regenerate it with
/// `docs/brand/make-quickie-mark.py` rather than editing by hand: in-process
/// rendering forgives a bare hand-rolled template, but Control Center's
/// out-of-process renderer draws an unannotated symbol as empty.
enum QuickieGlyph {
    /// The custom symbol's asset-catalog name (`QuickieMark.symbolset`). Not
    /// for Control Center labels — the controls take `flatName` (see there).
    static let name = "QuickieMark"

    /// The **flat** variant's asset-catalog name (`QuickieMarkFlat.symbolset`):
    /// the same orbital Q as one fully opaque layer, with the longer flat-era
    /// arrow. This is the mark the two Control Center controls
    /// (`QuickCaptureControl`, `ActionControl`) reference via `Label(_:image:)`
    /// — a custom symbol nested as a plain `Image` view silently renders
    /// nothing there, and the *faded* mark fares no better: Control Center's
    /// out-of-process renderer washes its mostly-translucent layers (the ring's
    /// floor is 0.3) into an invisible glyph, where in-process rendering shows
    /// the fade as designed. Both symbolsets are emitted by the same generator
    /// (`docs/brand/make-quickie-mark.py`) from the same geometry, so the marks
    /// cannot drift.
    static let flatName = "QuickieMarkFlat"

    /// The mark as a SwiftUI image, for the app's Home mark and for widget and
    /// Live Activity views. Custom symbols load through `Image(_:)`, not
    /// `Image(systemName:)` — this is the one place that distinction lives. Not
    /// for Control Center labels (see `name`).
    static var image: Image { Image(name) }
}
