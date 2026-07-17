import SwiftUI
import UIKit

/// The one place a brand color literal lives (ADR 0033) — so nothing can drift
/// back onto system blue, or onto a purple the icon doesn't actually contain.
///
/// It reaches its surfaces two ways, deliberately. The **app** target mostly
/// doesn't name this module at all: its `AccentColor` asset carries `accent`, so
/// `Color.accentColor` and `.tint` resolve to brand purple — the ring and wash
/// (`ResultListView`), the backdrop glow (`RootView`), the breadcrumb pills
/// (`Capture`) all read the asset, which `check-brand-assets.py` pins to the
/// literals below. (The asset is not quite enough on its own: a `Toggle`'s
/// switch ignores the accent and renders system green, so `QuickieApp` also
/// claims the *ambient* tint once at the root — see ADR 0033.) The
/// **widget** extension names this module directly instead (`EntryWidget`,
/// `PendingQueryLiveActivity`), because it has **no** `AccentColor` asset — and
/// deliberately must not gain one: an accent asset tints an extension's every
/// surface by default, including the compact/minimal Dynamic Island, which ADR
/// 0033 keeps system-tinted precisely because it is shared chrome. Naming the
/// token per-surface is what makes that line drawable.
///
/// It lives in the folder synced into **both** targets (like `ActionIcons` and
/// `DeeplinkInbox`) because the brand is one brand: the widget extension
/// previously hand-copied the icon's gradients into `QuickieGlyph`, which is
/// exactly the drift this module exists to end.
///
/// The literals are hand-copied from `docs/brand/make-app-icon.py` — Swift can't
/// read the Python constants — so `docs/brand/check-brand-assets.py` re-derives
/// the palette from that generator on every full CI run and fails on drift,
/// naming the constant and printing the number to paste. It matches them **by
/// name**, in the exact `static let ... = Color(red:green:blue:)` shape below,
/// and fails loudly on a name it can't find — so renaming one here means
/// renaming its key in that script's `brand_palette`, and the check will say so
/// rather than fall silent.
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

    // MARK: - Roles

    /// Light mode's accent: a mid-purple, the field's hue and saturation lifted
    /// to HSL lightness 0.45 — 8.3:1 on white. Derived rather than picked, and so
    /// filed here rather than above: it appears nowhere in the icon, because the
    /// field's own `BG_TOP` is legible on white but reads as near-black, and an
    /// accent has to look chosen. `check-brand-assets.py` runs the same lift, so
    /// this tracks the icon's field automatically.
    static let lightAccent = Color(red: 88 / 255, green: 50 / 255, blue: 180 / 255)

    /// The brand accent, adaptive: `lightAccent` on light, the icon's `lavender`
    /// on dark. Neither value survives both appearances — the lavender washes out
    /// on white, the mid-purple sinks into a dark backdrop — which is why there
    /// is no single accent literal to point at (ADR 0033), and why this is the
    /// one token that can't be a plain constant.
    ///
    /// A dynamic `UIColor` rather than a colorset in each target's catalog: one
    /// definition beats two assets that can disagree. The app's `AccentColor`
    /// carries the same pair for ambient tinting (see the type comment), and
    /// `check-brand-assets.py` holds the two together.
    static let accent = Color(uiColor: UIColor { traits in
        UIColor(traits.userInterfaceStyle == .dark ? lavender : lightAccent)
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
