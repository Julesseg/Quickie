import SwiftUI
import QuickieCore

/// The reversed, bottom-anchored Result list (ADR 0008): the best match sits
/// nearest the input and the thumb, with weaker matches stacking upward and
/// scrolling away. We reverse the ranked array so rank 0 renders last (lowest),
/// and anchor the scroll view to the bottom so it opens at the best match.
struct ResultListView: View {
    let results: [Action]
    let onRun: (Action) -> Void
    /// Whether a row's Action is pinned — drives its Pin/Unpin menu label.
    let isFavorite: (Action) -> Bool
    /// Toggles a row's Favorite pin (issue #9 AC #1).
    let onToggleFavorite: (Action) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(results.reversed()) { action in
                    Button {
                        onRun(action)
                    } label: {
                        ActionRow(action: action)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(action.id)
                    .favoriteContextMenu(
                        isFavorite: isFavorite(action),
                        toggle: { onToggleFavorite(action) }
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
    }
}

/// One row: an Action presented by its main action (title + optional subtitle).
/// Shared by the Result list and the Home Frecency list so a remembered Action
/// reads identically wherever it appears.
struct ActionRow: View {
    let action: Action

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

extension View {
    /// The Pin/Unpin affordance shared by every row that can be favorited. A
    /// long-press context menu keeps pinning out of the typing fast path; it is
    /// distinct from the deferred *secondary actions* long-press (ADR 0008),
    /// which operates on a result's content rather than its place in the index.
    func favoriteContextMenu(isFavorite: Bool, toggle: @escaping () -> Void) -> some View {
        contextMenu {
            Button {
                toggle()
            } label: {
                Label(isFavorite ? "Unpin Favorite" : "Pin as Favorite",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }
}
