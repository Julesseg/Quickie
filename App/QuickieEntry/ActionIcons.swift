import SwiftUI
import QuickieCore

/// The visual vocabulary for a Result row's two glyphs (issue #11): a leading
/// provider badge — a colored squircle with a white symbol, saying *what kind of
/// thing this is* — and a trailing main-action glyph — a plain symbol pushed to
/// the right, saying *what tapping it does*. The Core classifications
/// (`ActionKind`, `MainAction`) decide the meaning; this file is the dumb lookup
/// from meaning to SF Symbol and tint, kept at the App edge.
///
/// It lives in the folder synced into **both** the app and widget targets (like
/// `DeeplinkInbox`) because the Favorites widget mirrors the in-app Favorites grid
/// (ADR 0025): its cells render the same `ProviderBadge` from the same
/// symbol/tint lookup, so the two surfaces can never drift onto different badges.

extension ActionKind {
    /// The SF Symbol shown white inside the provider badge.
    var symbol: String {
        switch self {
        case .quicklink: return "link"
        // A Custom Action is defined by its `{slot}` tokens (ADR 0021) — the
        // braces are its identity. Not a magnifying glass: that read as a
        // leftover default next to the brand mark, and search is just one of
        // the things a Custom Action does.
        case .customAction: return "curlybraces"
        case .snippet: return "doc.on.clipboard"
        case .pile: return "tray.full"
        case .shortcut: return "square.stack.3d.up"
        case .saveForLater: return "tray.and.arrow.down"
        case .newSnippet: return "rectangle.and.pencil.and.ellipsis"
        case .calculator: return "function"
        case .reminder: return "checklist"
        case .event: return "calendar"
        case .settings: return "gearshape"
        case .file: return "doc"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .managementPage: return "slider.horizontal.3"
        case .system: return "gearshape.2"
        }
    }

    /// The squircle's hue — one per provider, no two alike (issue #178).
    ///
    /// Every value comes from `QuickieBrand`'s curated ring, never from a system
    /// color: the raw set this replaced had three kinds sharing `.gray`, two sharing
    /// `.brown`, `customAction`/`shortcut` both on `.indigo`, and `quicklink` on the
    /// `.blue` that used to *be* the accent — so the badge's whole job, saying which
    /// provider a row came from, quietly failed on a third of the kinds. The brand
    /// module documents how the ring is derived and why it leaves the accent's hue
    /// and gold's hue empty; `check-brand-assets.py` holds this mapping to it,
    /// failing if two kinds ever land on the same hue again.
    var tint: Color {
        switch self {
        case .quicklink: return QuickieBrand.badgeQuicklink
        case .customAction: return QuickieBrand.badgeCustomAction
        case .snippet: return QuickieBrand.badgeSnippet
        case .pile: return QuickieBrand.badgePile
        case .shortcut: return QuickieBrand.badgeShortcut
        case .saveForLater: return QuickieBrand.badgeSaveForLater
        case .newSnippet: return QuickieBrand.badgeNewSnippet
        case .calculator: return QuickieBrand.badgeCalculator
        case .reminder: return QuickieBrand.badgeReminder
        case .event: return QuickieBrand.badgeEvent
        case .settings: return QuickieBrand.badgeSettings
        case .file: return QuickieBrand.badgeFile
        case .searchFiles: return QuickieBrand.badgeSearchFiles
        case .managementPage: return QuickieBrand.badgeManagementPage
        case .system: return QuickieBrand.badgeSystem
        }
    }
}

extension RGBA {
    /// The SwiftUI color for Core's parsed channels (CONTEXT.md → Detected result;
    /// issue #217) — the App-edge half of the split that keeps Core UIKit-free:
    /// Core parses the notation and carries the numbers, this maps them to something
    /// drawable. `.sRGB` because a hex notation *is* an sRGB triple, and its opacity
    /// rides as the color's own alpha so a translucent `#ff6600cc` reads translucent.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension ActionColor {
    /// This palette token as a SwiftUI `Color` (CONTEXT.md → Action color; issue #243)
    /// — the one place a token becomes a drawable fill. The channels come straight from
    /// Core, where the palette is generated at the badge ring's OKLCH lightness and
    /// `swift test`-checked against the ring's own white-contrast band.
    ///
    /// A **flat** literal, not an appearance-adaptive pair, exactly like the
    /// `QuickieBrand.badge*` hues it sits beside: at L = 0.55 one opaque colour reads
    /// correctly on both appearances, and a chosen swatch that shifted with the
    /// appearance would be the one badge in the app that does.
    var swiftUIColor: Color {
        Color(red: components.red, green: components.green, blue: components.blue)
    }
}

/// The **one** resolution of a leading-glyph hue from its three possible sources,
/// most-specific first (CONTEXT.md → Action color, Detected result):
///
/// 1. a **detected swatch** (`tint`) — that row exists *because* the query is that
///    colour, so the hue is its content, not its decoration, and it wins outright;
/// 2. the user's chosen **Action color** token (issue #243);
/// 3. the provider kind's own hue — which is exactly what Default means.
///
/// A free function rather than a `ProviderBadge` detail because the Shelf's tinted
/// glass reads the same rule (ADR 0037), and two surfaces resolving it separately is
/// how a badge and its Shelf button end up different colours. In practice 1 and 2 are
/// disjoint — a detected row carries no stored token and has no editor to set one —
/// so the order is a stated rule rather than a contested one.
func resolvedActionTint(kind: ActionKind, color: ActionColor?, tint: Color? = nil) -> Color {
    tint ?? color?.swiftUIColor ?? kind.tint
}

extension ReturnKeyLabel {
    /// The SwiftUI `SubmitLabel` closest to this Core intent (CONTEXT.md →
    /// Highlighted result): the Return key reads `.search` for a web query, `.go`
    /// for a link, `.done` for a self-contained capture/copy. `.none` (Home, no
    /// highlight) falls back to a neutral `.go`.
    var submitLabel: SubmitLabel {
        switch self {
        case .search: return .search
        case .go: return .go
        case .done: return .done
        case .none: return .go
        }
    }
}

extension MainAction {
    /// The trailing glyph for what a tap performs, or `nil` when there's nothing
    /// meaningful to signal.
    var symbol: String? {
        switch self {
        case .openInBrowser: return "arrow.up.right"
        case .copyToClipboard: return "doc.on.doc"
        // Staging puts the saved text back into the input — the insert glyph.
        case .stage: return "text.insert"
        // The silent capture drops the text in and you're done — distinct from
        // the Save-for-later row's leading tray badge, so the two-glyph
        // vocabulary (what it is vs. what tapping does) holds on that row too.
        case .saveToPile: return "arrow.down.to.line"
        case .compose: return "square.and.pencil"
        case .openPage: return "chevron.right"
        case .openFile: return "arrow.up.forward.app"
        case .searchFiles: return "chevron.right"
        case .runShortcut: return "play.fill"
        case .none: return nil
        }
    }
}

/// The leading provider badge: a colored squircle with a white symbol — the
/// row's at-a-glance identity (which Provider it came from).
struct ProviderBadge: View {
    let kind: ActionKind
    /// An explicit SF Symbol overriding the kind's own lookup: the Favorites
    /// widget passes its snapshot's denormalized glyph so the badge truly renders
    /// from the snapshot alone (ADR 0025); in-app rows omit it and read the
    /// live lookup.
    ///
    /// Only the *symbol* is overridable — never the tint or the weight. A user who
    /// picks their own glyph (issue #163) gets a badge that still reads as this
    /// kind's badge with a different drawing inside it, rather than a foreign chip
    /// in the row: the chosen symbol is more specific than the derived one, not
    /// less native.
    var symbol: String? = nil
    /// The action's chosen **Action color** (CONTEXT.md → Action color; issue #243),
    /// overriding the kind's own tint. `nil` is Default — the kind-derived tint, so an
    /// action with no chosen colour renders exactly as before.
    var color: ActionColor? = nil

    /// An explicit hue overriding the kind's own — the **swatch** a detected hex
    /// color wears (CONTEXT.md → Detected result; issue #217), so that row *is* the
    /// color rather than merely naming it. This is the one case where the tint is
    /// row-specific rather than provider-specific, and it is exactly why the row
    /// exists, so it earns the exception the user-chosen `symbol` does not get.
    /// `nil` (every other row) keeps the kind's hue.
    var tint: Color? = nil

    /// The badge's edge length. Every other metric — the corner radius and the
    /// symbol's point size — is derived from it, so a badge drawn larger is the
    /// *same* badge at a bigger size rather than a second set of numbers that can
    /// drift from this one.
    ///
    /// Exists so a surface that wants a big badge (the appearance page's hero,
    /// issue #243) can ask for one **drawn** at that size instead of reaching for
    /// `.scaleEffect`. A transform scales the badge's rendered bitmap: the symbol
    /// is rasterized at `symbolSize` and then stretched, which simple solid glyphs
    /// survive and detailed ones (`doc.text.magnifyingglass`, `checklist`) visibly
    /// do not. Passing the size down keeps the glyph vector all the way to the
    /// screen, so every symbol is equally crisp.
    var size: CGFloat = Self.baseSize

    /// The proportions are authored at the row badge's 30pt and scale from there.
    private static let baseSize: CGFloat = 30

    /// How far this badge is from the authored proportions — the one factor the
    /// derived metrics multiply by.
    private var scale: CGFloat { size / Self.baseSize }

    /// The white symbol's point size: 14pt on a 30pt badge, in proportion above it.
    private var symbolSize: CGFloat { 14 * scale }

    /// The squircle's fill — the shared precedence rule, resolved once.
    private var fill: Color {
        resolvedActionTint(kind: kind, color: color, tint: tint)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: QuickieRadius.badge * scale, style: .continuous)
            // The hue's own subtle top-to-bottom luminosity ramp (issue #178) — the
            // system's gradient, so the badge gains a little depth without a
            // hand-rolled shadow under it (ADR 0010: depth is the glass's job, and
            // the badge sits *on* glass; a drop shadow here would be a second, fake
            // light source arguing with the material).
            .fill(fill.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol ?? kind.symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // Decorative: the row's meaning is its title, so the badge shouldn't
            // add to the accessibility label (nor the symbol name to it).
            .accessibilityHidden(true)
    }
}

/// The trailing main-action glyph: a plain symbol, no background, pushed to the
/// far right, signalling what a tap does (open in browser, copy, stage…).
struct MainActionGlyph: View {
    let mainAction: MainAction

    var body: some View {
        if let symbol = mainAction.symbol {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
