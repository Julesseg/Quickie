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

    var body: some View {
        RoundedRectangle(cornerRadius: QuickieRadius.badge, style: .continuous)
            // The hue's own subtle top-to-bottom luminosity ramp (issue #178) — the
            // system's gradient, so the badge gains a little depth without a
            // hand-rolled shadow under it (ADR 0010: depth is the glass's job, and
            // the badge sits *on* glass; a drop shadow here would be a second, fake
            // light source arguing with the material).
            .fill(kind.tint.gradient)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: symbol ?? kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
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
