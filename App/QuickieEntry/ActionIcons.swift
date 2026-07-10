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
        case .customAction: return "magnifyingglass"
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

    /// The squircle's fill — one calm, distinct hue per provider.
    var tint: Color {
        switch self {
        case .quicklink: return .blue
        case .customAction: return .indigo
        case .snippet: return .teal
        case .pile: return .orange
        case .shortcut: return .indigo
        case .saveForLater: return .pink
        case .newSnippet: return .purple
        case .calculator: return .green
        case .reminder: return .red
        case .event: return .cyan
        case .settings: return .gray
        case .file: return .brown
        case .searchFiles: return .brown
        case .managementPage: return .gray
        case .system: return .gray
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
    var symbol: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(kind.tint)
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
