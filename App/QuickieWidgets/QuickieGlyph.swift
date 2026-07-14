import SwiftUI

/// The single glyph every widget-extension [[Entry surface]] renders for "open
/// Quickie" — the **Quickie mark** (the app icon's orbital Q, isolated as a custom
/// SF Symbol in this extension's asset catalog), replacing the placeholder
/// magnifying glass from before the brand mark existed. Shared by the deep-link
/// widget (`EntryWidget`, #124), the widget placeholders (Favorites #126, Actions
/// ADR 0027), and both Control Center controls (`QuickCaptureControl` #125,
/// `ActionControl` ADR 0027) so the entry surfaces can never drift onto different
/// glyphs. A custom symbol — not a plain image — because Control Center renders
/// only symbol images; as a symbol it tints, scales, and renders vibrantly on the
/// Lock Screen exactly like a system one. The symbolset's SVG must stay a
/// *canonical* SF Symbols template (the layout the SF Symbols app exports, with
/// the layer classes `monochrome-0` / `hierarchical-0:primary` /
/// `multicolor-0:tintColor` on every variant path) — regenerate it with
/// `docs/brand/make-quickie-mark.py` rather than editing by hand: in-process
/// rendering forgives a bare hand-rolled template, but Control Center's
/// out-of-process renderer draws an unannotated symbol as empty.
enum QuickieGlyph {
    /// The custom symbol's asset-catalog name (`QuickieMark.symbolset`). Control
    /// Center labels must reference it by name via `Label(_:image:)` — a custom
    /// symbol nested as a plain `Image` view silently renders nothing there.
    static let name = "QuickieMark"

    /// The mark as a SwiftUI image, for widget and Live Activity views. Custom
    /// symbols load through `Image(_:)`, not `Image(systemName:)` — this is the
    /// one place that distinction lives. Not for Control Center labels (see
    /// `name`).
    static var image: Image { Image(name) }
}
