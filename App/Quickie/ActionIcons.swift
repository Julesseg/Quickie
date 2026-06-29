import SwiftUI
import QuickieCore

/// The visual vocabulary for a Result row's two glyphs (issue #11): a leading
/// provider badge — a colored squircle with a white symbol, saying *what kind of
/// thing this is* — and a trailing main-action glyph — a plain symbol pushed to
/// the right, saying *what tapping it does*. The Core classifications
/// (`ActionKind`, `MainAction`) decide the meaning; this file is the dumb lookup
/// from meaning to SF Symbol and tint, kept at the App edge.

extension ActionKind {
    /// The SF Symbol shown white inside the provider badge.
    var symbol: String {
        switch self {
        case .quicklink: return "link"
        case .fallbackQuery: return "magnifyingglass"
        case .snippet: return "doc.on.clipboard"
        case .note: return "note.text"
        case .newNote: return "square.and.pencil"
        case .newSnippet: return "rectangle.and.pencil.and.ellipsis"
        case .calculator: return "function"
        case .settings: return "gearshape"
        case .managementPage: return "slider.horizontal.3"
        }
    }

    /// The squircle's fill — one calm, distinct hue per provider.
    var tint: Color {
        switch self {
        case .quicklink: return .blue
        case .fallbackQuery: return .indigo
        case .snippet: return .teal
        case .note: return .orange
        case .newNote: return .pink
        case .newSnippet: return .purple
        case .calculator: return .green
        case .settings: return .gray
        case .managementPage: return .gray
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
        case .openNote: return "book"
        case .compose: return "square.and.pencil"
        case .openPage: return "chevron.right"
        case .none: return nil
        }
    }
}

/// The leading provider badge: a colored squircle with a white symbol — the
/// row's at-a-glance identity (which Provider it came from).
struct ProviderBadge: View {
    let kind: ActionKind

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(kind.tint)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // Decorative: the row's meaning is its title, so the badge shouldn't
            // add to the accessibility label (nor the symbol name to it).
            .accessibilityHidden(true)
    }
}

/// The trailing main-action glyph: a plain symbol, no background, pushed to the
/// far right, signalling what a tap does (open in browser, copy, read…).
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
