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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tight animation budget (ADR 0010): a subtle spring as rows insert and
    /// reorder with the ranking, degrading to a fade under Reduce Motion.
    private var rowMotion: MotionStyle {
        MotionPolicy(reduceMotion: reduceMotion).style(for: .rowInsert)
    }

    var body: some View {
        ScrollView {
            // A single container so the neighbouring glass capsules blend and
            // morph as one Liquid Glass surface rather than stacking flatly.
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 6) {
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
                        .transition(rowMotion.insertionTransition)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            // Animate insert/reorder when the set or order of results changes —
            // keystroke-fast, and never gating the keystroke itself.
            .animation(rowMotion.animation, value: results.map(\.id))
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
        HStack(spacing: 12) {
            ProviderBadge(kind: action.kind)
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
            Spacer(minLength: 8)
            MainActionGlyph(mainAction: action.mainAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 12)
        .contentShape(Capsule())
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
