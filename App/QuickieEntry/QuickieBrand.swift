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
    /// spends it in **exactly one place** — the Highlighted result's hero
    /// treatment (#177): its soft gold glow that slides side to side while you type
    /// and settles when you stop. It marks the app's center of gravity, and only
    /// scarcity lets it keep meaning that.
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

    /// The brand's **accent wash**: the adaptive accent at the same 0.12 opacity
    /// the in-app [[Highlighted result]] row wears (`ResultListView`), so a
    /// widget's filled cell platter and the Live Activity's Lock-Screen tint read
    /// as the same faint purple the app already uses — accents, not backdrops (ADR
    /// 0033). Deliberately low: it must sit under snapshot glyphs and query text
    /// without competing, and it degrades to near-nothing when the system renders
    /// a widget in its tinted/clear mode, which is the graceful failure ADR 0033
    /// wants rather than a fight for the wallpaper. The app side reaches the
    /// identical value inline as `Color.accentColor.opacity(0.12)` (its
    /// `AccentColor` asset supplies the same adaptive pair); the widget extension
    /// has no such asset, so it names this token — the same asset/token split the
    /// `accent` itself lives under.
    static var accentWash: Color { accent.opacity(0.12) }

    /// The icon trail's color ramp — lavender whitening toward the release, top
    /// to bottom, where the arrow departs — for surfaces where SwiftUI styling
    /// actually applies: widget and Live Activity views.
    ///
    /// For marks drawn on the **icon's own field** (or another dark surface),
    /// which is every widget use of it. On the app's adaptive backdrop, reach for
    /// `adaptiveMarkGradient` instead — both ends of this ramp are chosen against
    /// a deep purple field, and neither survives white.
    ///
    /// Not for Control Center labels: a control tints its symbol itself, which is
    /// why the *fade* half of the icon's look is baked into the symbol's layers
    /// instead (see `QuickieGlyph`). The white end has no counterpart in the icon
    /// generator, so nothing can drift it.
    static var markGradient: LinearGradient {
        LinearGradient(colors: [lavender, .white], startPoint: .top, endPoint: .bottom)
    }

    /// The trail's ramp for a mark on the **app's** backdrop — Home's brand mark
    /// (ADR 0033's adaptive-on-white trade) — where the surface behind it is
    /// `systemBackground`: white on light, black on dark.
    ///
    /// The same ADR 0033 problem the accent has, in gradient form: `markGradient`
    /// is drawn on the icon's deep field everywhere else, and on white it fails at
    /// *both* ends — it starts at the lavender that ADR 0033 already says washes
    /// out there, and ends at the background exactly, erasing the release. The
    /// mark would read as a pale, clipped ghost of itself.
    ///
    /// So the ramp is expressed on the brand *axis* rather than as two literals:
    /// **the accent, lightening one step toward the release**. On dark that
    /// resolves to precisely `markGradient` — the icon's own lavender → white,
    /// unchanged. On light it becomes `lightAccent` → `lavender`: the same purple,
    /// the same direction of travel, stopping one step short of the background
    /// instead of dissolving into it. The trail still *fades* on both — that half
    /// of the look is the symbol's baked-in per-layer opacity (`QuickieGlyph`),
    /// which needs no color to do its job.
    static var adaptiveMarkGradient: LinearGradient {
        LinearGradient(colors: [accent, markRelease], startPoint: .top, endPoint: .bottom)
    }

    /// Where `adaptiveMarkGradient` lands at the release: white on dark (the
    /// icon's own end), the lavender on light. One step lighter than `accent` in
    /// each appearance, which is all the ramp ever means.
    private static let markRelease = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(lavender)
    })

    /// The icon's background gradient, for the deep-link widget tile — under
    /// `markGradient` the tile reads as the app icon writ large rather than a
    /// recolored stranger.
    static var iconBackdrop: LinearGradient {
        LinearGradient(colors: [fieldTop, fieldBottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - The Living backdrop's mesh (ADR 0034)
    //
    // The surface the Liquid Glass chrome refracts (ADR 0010) — the two-stop quiet
    // backdrop made living (ADR 0034). Nine stops, one per 3×3 mesh control point,
    // row-major, adaptive per appearance.
    //
    // The stops are deliberately *not* one hue at nine lightnesses. A near-mono
    // mesh has nothing to see move — its stops look alike, so the slow drift reads
    // as a still image no matter how far the points travel. So the palette spreads
    // across the purple axis (indigo → violet → magenta-purple, ~260–300°) with a
    // couple of stops lifted into soft blooms: distinguishable zones whose edges
    // the eye *can* follow as they drift. That is the whole reason the backdrop
    // reads as alive rather than as wallpaper.
    //
    // - **Dark** stays low in lightness everywhere (a backdrop, never a light
    //   source): the blooms are deep violets, not bright ones, so text and the
    //   glass chrome stay legible (ADR 0010) — the hue spread, not brightness, is
    //   what carries the motion.
    // - **Light** is a near-white wash with a touch more of the purple axis than a
    //   whisper, so the drift is visible without the mesh ever fighting black body
    //   text.
    //
    // These are the one part of the backdrop the icon has no opinion about, so —
    // like the badge ring — they are built to that rule rather than derived from
    // the generator. They live in `Color(uiColor:)` closures (not the `static let
    // … = Color(red:…)` shape), so `check-brand-assets.py` never scans them as
    // drifted icon literals.

    /// The dark-appearance mesh, row-major. Kept *very* dark — a near-black field
    /// with only a breath of purple — so it reads as a calm backdrop, never a lit
    /// screen; even the lifted stops (indices 4 and 7, the lower-center blooms) stay
    /// deep. The hues still fan indigo → magenta-purple across the grid so the drift
    /// keeps visible edges despite the low brightness.
    private static let backdropMeshDark: [(CGFloat, CGFloat, CGFloat)] = [
        (11, 8, 28), (13, 8, 33), (15, 9, 37),
        (13, 9, 35), (31, 19, 68), (17, 10, 44),
        (16, 10, 42), (27, 16, 60), (13, 8, 33),
    ]

    /// The light-appearance mesh, row-major: a lavender wash with real presence
    /// (not a whisper of white) so the mesh is legibly *there*, with the same
    /// indigo → magenta-purple fan and two deeper stops (4 and 7) as the blooms —
    /// still pale enough that black text over it keeps a wide contrast margin.
    private static let backdropMeshLight: [(CGFloat, CGFloat, CGFloat)] = [
        (227, 222, 248), (219, 212, 246), (212, 203, 244),
        (217, 209, 246), (201, 188, 240), (214, 205, 245),
        (210, 200, 243), (204, 192, 241), (223, 217, 247),
    ]

    /// The nine mesh colors for a 3×3 [[Living backdrop]] (ADR 0034), row-major.
    /// Each is an adaptive `Color`, so one array serves both appearances — SwiftUI
    /// resolves each stop per color scheme.
    static var backdropMesh: [Color] {
        zip(backdropMeshLight, backdropMeshDark).map { light, dark in
            Color(uiColor: UIColor { traits in
                let c = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
            })
        }
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
    // - **Chroma to each hue's full gamut ceiling, capped at 0.24.** Every hue is
    //   pushed as saturated as sRGB allows at this lightness — the vivid end of the
    //   dial (issue #189's prototype compared it against a muted set and this one won
    //   on distinctness). sRGB simply can't hold a vivid teal here (h~200 tops out
    //   near 0.09), so the cool arc stays quieter than the warm one and the set
    //   tilts warm — an accepted trade for badges that read boldly. The 0.24 cap
    //   only binds on the magentas, whose ceiling runs higher; it keeps the loudest
    //   hues from pulling clean out of the family.
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
    //   in exactly one place, the Highlighted result's hero treatment; a gold-ish badge
    //   would be the "gold as a secondary accent" that ADR explicitly rejected.
    //   The ring therefore runs 104°→255° and 325°→64°, and the badges flank the
    //   accent rather than competing with it.
    //
    // Ring order below, so the neighbourhoods are visible: the cool arc after the
    // gold gap, then the warm arc after the accent gap.

    /// A File Search hit (`file`) — the manila of a folder tab.
    static let badgeFile = Color(red: 110 / 255, green: 122 / 255, blue: 0 / 255)
    /// The "Search Files" command (`searchFiles`) — beside `badgeFile`, because it
    /// is the door to the same content.
    static let badgeSearchFiles = Color(red: 71 / 255, green: 132 / 255, blue: 0 / 255)
    /// A math result (`calculator`).
    static let badgeCalculator = Color(red: 0 / 255, green: 138 / 255, blue: 26 / 255)
    /// The "New Snippet" Fallback (`newSnippet`) — beside `badgeSnippet`, the thing
    /// it creates.
    static let badgeNewSnippet = Color(red: 0 / 255, green: 136 / 255, blue: 79 / 255)
    /// A Snippet (`snippet`).
    static let badgeSnippet = Color(red: 0 / 255, green: 132 / 255, blue: 114 / 255)
    /// A System provider built-in (`system`) — first of the three chrome kinds,
    /// which take the quiet cool end of the ring together.
    static let badgeSystem = Color(red: 0 / 255, green: 128 / 255, blue: 142 / 255)
    /// A management command row (`managementPage`).
    static let badgeManagementPage = Color(red: 0 / 255, green: 123 / 255, blue: 173 / 255)
    /// The Settings command row (`settings`). The one blue in the set, and a
    /// deliberate one: it is 40° off the accent in OKLCH, far enough to read as a
    /// choice rather than as the default tint the old palette looked like.
    static let badgeSettings = Color(red: 0 / 255, green: 116 / 255, blue: 200 / 255)
    /// A slotted Custom Action (`customAction`).
    static let badgeCustomAction = Color(red: 185 / 255, green: 20 / 255, blue: 176 / 255)
    /// A static, slot-less Custom Action (`quicklink`) — **off blue**, where it used
    /// to sit. Adjacent to `badgeCustomAction` on purpose: ADR 0030 attributes both
    /// kinds to the one Custom Actions provider, so they should look related. Their
    /// glyphs (link vs. braces) carry the difference.
    static let badgeQuicklink = Color(red: 197 / 255, green: 0 / 255, blue: 146 / 255)
    /// An imported Shortcut Action (`shortcut`) — kept a clear step off
    /// `badgeCustomAction`, which it used to share an indigo with.
    static let badgeShortcut = Color(red: 204 / 255, green: 0 / 255, blue: 113 / 255)
    /// The "Save for later" Fallback (`saveForLater`) — well clear of `badgePile`,
    /// because a row must never read as the entries it creates.
    static let badgeSaveForLater = Color(red: 210 / 255, green: 0 / 255, blue: 76 / 255)
    /// A New Reminder capture (`reminder`).
    static let badgeReminder = Color(red: 214 / 255, green: 0 / 255, blue: 14 / 255)
    /// A New Event capture (`event`) — beside `badgeReminder`, its EventKit twin.
    static let badgeEvent = Color(red: 195 / 255, green: 60 / 255, blue: 0 / 255)
    /// A Pile entry (`pile`).
    static let badgePile = Color(red: 174 / 255, green: 85 / 255, blue: 0 / 255)
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
