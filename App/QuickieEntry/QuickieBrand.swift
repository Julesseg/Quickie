import SwiftUI
import UIKit

/// The one place a brand color literal lives (ADR 0033). Every tinted surface —
/// the [[Highlighted result]]'s ring and wash, the backdrop glow, the breadcrumb
/// pills, the Enter hint, the Live Activity glyphs, the widget tiles — reads its
/// color from here, so the app can never drift back onto system blue or onto a
/// purple the icon doesn't actually contain.
///
/// It lives in the folder synced into **both** the app and widget targets (like
/// `ActionIcons` and `DeeplinkInbox`) because the brand is one brand: the widget
/// extension previously hand-copied the icon's gradients into `QuickieGlyph`,
/// which is exactly the drift this module exists to end.
///
/// The literals are hand-copied from `docs/brand/make-app-icon.py` — Swift can't
/// read the Python constants — so `docs/brand/check-brand-assets.py` re-derives
/// the whole palette from that generator on every full CI run and fails on
/// drift, naming the constant and printing the number to paste. **Rename or
/// retype one of the `static let ... = Color(red:green:blue:)` literals below
/// and the check stops seeing it**: it matches them by name, in that exact
/// shape.
enum QuickieBrand {
    // MARK: - The icon's palette
    //
    // The icon's field and its trail sit on the same hue (~257 degrees) and
    // differ only in lightness and saturation: the brand is a purple *axis*, not
    // a purple value (ADR 0033).

    /// The icon trail's lavender (`make-app-icon.py`'s `LAVENDER`) — the trail's
    /// color before it whitens toward the release, and dark mode's accent.
    static let lavender = Color(red: 203 / 255, green: 184 / 255, blue: 255 / 255)

    /// The icon's warm mass, the thing the comet orbits (`DOT_COLOR`). ADR 0033
    /// spends it in **exactly one place** — the Highlighted result's hero glow
    /// (#177). It marks the app's center of gravity, and only scarcity lets it
    /// keep meaning that.
    static let gold = Color(red: 255 / 255, green: 201 / 255, blue: 79 / 255)

    /// The icon field's deep purples, top and bottom (`BG_TOP` / `BG_BOTTOM`).
    static let fieldTop = Color(red: 46 / 255, green: 26 / 255, blue: 94 / 255)
    static let fieldBottom = Color(red: 15 / 255, green: 7 / 255, blue: 38 / 255)

    /// Light mode's accent: the field's hue and saturation lifted to a mid HSL
    /// lightness (0.45), 8.3:1 on white. Derived rather than picked — the field's
    /// own `BG_TOP` is legible on white but reads as near-black, and an accent
    /// has to look chosen. `check-brand-assets.py` runs the lift itself, so this
    /// tracks the icon's field automatically.
    static let midPurple = Color(red: 88 / 255, green: 50 / 255, blue: 180 / 255)

    // MARK: - Roles

    /// The brand accent, adaptive: the mid-purple on light, the icon's lavender
    /// on dark. Neither value survives both appearances — the lavender washes out
    /// on white, the mid-purple sinks into a dark backdrop — which is why there
    /// is no single accent literal to point at (ADR 0033).
    ///
    /// The app also carries this in its `AccentColor` asset, so *default* tinting
    /// (every toggle and system control that names no color) is brand purple with
    /// no per-view opt-in; the asset and these two literals are held together by
    /// `check-brand-assets.py`. This token is for the widget extension, which has
    /// no such asset, and for the places that need a `Color` rather than an
    /// ambient tint. A dynamic `UIColor` rather than an asset in each catalog:
    /// one definition beats two colorsets that can disagree.
    static let accent = Color(uiColor: UIColor { traits in
        UIColor(traits.userInterfaceStyle == .dark ? lavender : midPurple)
    })

    /// The icon trail's color ramp — lavender whitening toward the release, top
    /// to bottom, where the arrow departs — for surfaces where SwiftUI styling
    /// actually applies: widget and Live Activity views.
    ///
    /// Not for Control Center labels: a control tints its symbol itself, which is
    /// why the *fade* half of the icon's look is baked into the symbol's layers
    /// instead (see `QuickieGlyph`). The white end has no counterpart in the icon
    /// generator, so nothing can drift it.
    static var markGradient: LinearGradient {
        LinearGradient(colors: [lavender, .white], startPoint: .top, endPoint: .bottom)
    }

    /// The icon's background gradient, for the deep-link widget tile — under
    /// `markGradient` the tile reads as the app icon writ large rather than a
    /// recolored stranger.
    static var iconBackdrop: LinearGradient {
        LinearGradient(colors: [fieldTop, fieldBottom], startPoint: .top, endPoint: .bottom)
    }
}
