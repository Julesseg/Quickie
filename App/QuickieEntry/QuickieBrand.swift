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

    // MARK: - The provider-badge palette
    //
    // One hue per `ActionKind`, so a Result row's leading badge says *what kind of
    // thing this is* at a glance (issue #178). `ActionIcons` maps kind → hue; the
    // literals live here because they are brand, and because one palette is what
    // keeps the in-app rows, the Favorites grid, and both widgets on the same
    // badges (they render the same `ProviderBadge` from the folder synced into
    // both targets).
    //
    // Unlike the icon's palette above, these are not derived from anything — the
    // icon has no opinion about what colour a Snippet is. They are built to rules
    // instead, and `check-brand-assets.py` enforces the rules rather than the
    // numbers:
    //
    // - **One lightness for the whole set (OKLCH L 0.55).** Every badge carries a
    //   white glyph, so every badge owes it the same legibility: fixing lightness
    //   pins white contrast into a 4.5–5.4:1 band across all fifteen, and leaves
    //   *hue* as the only channel that varies — which is the channel that means
    //   something. It also makes the set read as one family rather than fifteen
    //   decisions, and it is why these are flat literals rather than an adaptive
    //   pair like `accent`: an opaque badge at this lightness sits correctly on
    //   both appearances, so there is nothing for dark mode to fix.
    // - **Chroma to each hue's gamut ceiling, capped at 0.17.** sRGB cannot hold a
    //   vivid teal at this lightness (h~200 tops out near 0.09), so an unclamped
    //   set would let the magentas shout over a muted cyan band. The cap keeps the
    //   family even; the ceiling keeps each hue as distinct as sRGB allows.
    // - **Spaced by perceptual difference, not by hue angle.** Equal *degrees*
    //   crowd the greens (where a 20° step is barely visible) and waste the
    //   magentas (where it is obvious). These fifteen sit at roughly equal OKLab
    //   distance along the ring, so no two kinds are much closer than any other
    //   pair — the badges are as tellable-apart as fifteen hues can be.
    // - **Two arcs are off-limits, which is why the ring has gaps.** The accent's
    //   own hue (OKLCH ~290: `lightAccent` 289.7, `lavender` 296.4) is left empty
    //   so a badge never reads as a broken accent — the exact failure the old
    //   palette had, with a *blue* static-link badge beside what was then a blue
    //   accent. And `gold`'s hue (~84) is left empty because ADR 0033 spends gold
    //   in exactly one place, the Highlighted result's hero glow; a gold-ish badge
    //   would be the "gold as a secondary accent" that ADR explicitly rejected.
    //   The ring therefore runs 104°→255° and 325°→64°, and the badges flank the
    //   accent rather than competing with it.
    //
    // Ring order below, so the neighbourhoods are visible: the cool arc after the
    // gold gap, then the warm arc after the accent gap.

    /// A File Search hit (`file`) — the manila of a folder tab.
    static let badgeFile = Color(red: 111 / 255, green: 121 / 255, blue: 18 / 255)
    /// The "Search Files" command (`searchFiles`) — beside `badgeFile`, because it
    /// is the door to the same content.
    static let badgeSearchFiles = Color(red: 80 / 255, green: 130 / 255, blue: 18 / 255)
    /// A math result (`calculator`).
    static let badgeCalculator = Color(red: 21 / 255, green: 137 / 255, blue: 42 / 255)
    /// The "New Snippet" Fallback (`newSnippet`) — beside `badgeSnippet`, the thing
    /// it creates.
    static let badgeNewSnippet = Color(red: 22 / 255, green: 135 / 255, blue: 83 / 255)
    /// A Snippet (`snippet`).
    static let badgeSnippet = Color(red: 22 / 255, green: 131 / 255, blue: 115 / 255)
    /// A System provider built-in (`system`) — first of the three chrome kinds,
    /// which take the quiet cool end of the ring together.
    static let badgeSystem = Color(red: 21 / 255, green: 128 / 255, blue: 143 / 255)
    /// A management command row (`managementPage`).
    static let badgeManagementPage = Color(red: 21 / 255, green: 123 / 255, blue: 169 / 255)
    /// The Settings command row (`settings`). The one blue in the set, and a
    /// deliberate one: it is 40° off the accent in OKLCH, far enough to read as a
    /// choice rather than as the default tint the old palette looked like.
    static let badgeSettings = Color(red: 19 / 255, green: 116 / 255, blue: 195 / 255)
    /// A slotted Custom Action (`customAction`).
    static let badgeCustomAction = Color(red: 167 / 255, green: 68 / 255, blue: 158 / 255)
    /// A static, slot-less Custom Action (`quicklink`) — **off blue**, where it used
    /// to sit. Adjacent to `badgeCustomAction` on purpose: ADR 0030 attributes both
    /// kinds to the one Custom Actions provider, so they should look related. Their
    /// glyphs (link vs. braces) carry the difference.
    static let badgeQuicklink = Color(red: 177 / 255, green: 62 / 255, blue: 138 / 255)
    /// An imported Shortcut Action (`shortcut`) — kept a clear step off
    /// `badgeCustomAction`, which it used to share an indigo with.
    static let badgeShortcut = Color(red: 186 / 255, green: 58 / 255, blue: 113 / 255)
    /// The "Save for later" Fallback (`saveForLater`) — well clear of `badgePile`,
    /// because a row must never read as the entries it creates.
    static let badgeSaveForLater = Color(red: 191 / 255, green: 57 / 255, blue: 87 / 255)
    /// A New Reminder capture (`reminder`).
    static let badgeReminder = Color(red: 193 / 255, green: 60 / 255, blue: 54 / 255)
    /// A New Event capture (`event`) — beside `badgeReminder`, its EventKit twin.
    static let badgeEvent = Color(red: 187 / 255, green: 71 / 255, blue: 17 / 255)
    /// A Pile entry (`pile`).
    static let badgePile = Color(red: 169 / 255, green: 89 / 255, blue: 17 / 255)
}

/// The corner-radius scale — three steps, one per *kind of surface*, so a radius is
/// chosen by asking "what is this?" rather than by eyeballing a neighbour (issue
/// #178). It lives beside the brand's colors because it is the same sort of token,
/// and in the folder synced into both targets so a widget cell and the in-app card
/// it mirrors cannot drift apart.
///
/// The steps track the *size* of the thing being rounded — a radius that reads as
/// generous on a 30pt badge reads as timid on a 50pt row — which is why there are
/// three rather than one, and why they are not a series anyone should extend by
/// pattern. Surfaces that are none of these three keep their own value and say so
/// at the call site (the capture panel in `Capture`): a step with one caller would
/// be a token pretending to be a rule.
enum QuickieRadius {
    /// The provider badge (30pt): tight enough that the squircle still reads as a
    /// square carrying a symbol rather than as a dot.
    static let badge: CGFloat = 8

    /// Cards and pills (~50–60pt): the Favorites card and its widget-cell mirror,
    /// the breadcrumb crumbs, the glyph-picker tiles. One step, because a crumb is
    /// just a card that happens to hold text.
    static let card: CGFloat = 16

    /// Result rows (50pt single-line): tuned to a single-line row's half-height so
    /// short rows read as clean pills, while a wrapping row keeps the *same*
    /// rounding instead of ballooning into a stadium the way a `Capsule` would.
    static let row: CGFloat = 25
}
