import SwiftUI
import QuickieCore

/// The empty-query Home state (CONTEXT.md → Home; issue #9 AC #1, #2): a row of
/// pinned **Favorites** above an auto **Frecency** list of recently/often-used
/// Actions. Bottom-anchored like the Result list so the most relevant rows sit
/// nearest the thumb. Before the user has pinned or used anything it falls back
/// to the minimal "start typing" placeholder.
struct HomeView: View {
    let content: SearchEngine.HomeContent
    let onRun: (Action) -> Void
    let isFavorite: (Action) -> Bool
    let onToggleFavorite: (Action) -> Void

    private var isEmpty: Bool {
        content.favorites.isEmpty && content.frecent.isEmpty
    }

    var body: some View {
        if isEmpty {
            HomePlaceholder()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !content.frecent.isEmpty {
                        frecencySection
                    }
                    if !content.favorites.isEmpty {
                        favoritesSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    /// The pinned Favorites, as tappable chips in pin order — the
    /// tap-without-typing shortcuts. Rendered closest to the input (last in the
    /// stack) so the fast path sits under the thumb.
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Favorites")
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(content.favorites) { action in
                        Button {
                            onRun(action)
                        } label: {
                            Text(action.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("favorite.\(action.id)")
                        .favoriteContextMenu(isFavorite: true) { onToggleFavorite(action) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    /// The Frecency list: recently/often-used Actions, best-first, each a full
    /// row that runs on tap and can be pinned via long-press.
    private var frecencySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Recent")
                .padding(.horizontal, 20)
            ForEach(content.frecent) { action in
                Button {
                    onRun(action)
                } label: {
                    ActionRow(action: action)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(action.id)
                .favoriteContextMenu(isFavorite: isFavorite(action)) { onToggleFavorite(action) }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// The minimal pre-anything Home: shown before the user has pinned a Favorite or
/// used any Action, its only job is to fill the space above the input.
struct HomePlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Start typing")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("home-placeholder")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
