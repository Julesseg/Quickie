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
/// Lock Screen exactly like a system one.
enum QuickieGlyph {
    /// The custom symbol's asset-catalog name (`QuickieMark.symbolset`).
    static let name = "QuickieMark"

    /// The mark as a SwiftUI image. Custom symbols load through `Image(_:)`, not
    /// `Image(systemName:)` — this is the one place that distinction lives.
    static var image: Image { Image(name) }
}
