import SwiftUI
import QuickieCore

/// The reversed, bottom-anchored Result list (ADR 0008): the best match sits
/// nearest the input and the thumb, with weaker matches stacking upward and
/// scrolling away. We reverse the ranked array so rank 0 renders last (lowest),
/// and anchor the scroll view to the bottom so it opens at the best match.
///
/// `results[0]` is the **highlighted result** (CONTEXT.md → Highlighted result):
/// rendered with distinct emphasis and a `⏎` + main-action-glyph hint so it reads
/// as the default, since pressing Return runs exactly its main action.
struct ResultListView: View {
    let results: [Action]
    let onRun: (Action) -> Void
    /// Whether a row's Action is pinned — drives its Pin/Unpin menu label.
    let isFavorite: (Action) -> Bool
    /// Whether a row can still be pinned (false once the Favorites cap is hit).
    var canFavorite: (Action) -> Bool = { _ in true }
    /// Toggles a row's Favorite pin (issue #9 AC #1).
    let onToggleFavorite: (Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The id of the highlighted result — `results[0]`, nearest the thumb.
    private var highlightedID: String? { results.first?.id }

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
                            ActionRow(action: action, isHighlighted: action.id == highlightedID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(action.id)
                        .favoriteContextMenu(
                            isFavorite: isFavorite(action),
                            canPin: canFavorite(action),
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
/// reads identically wherever it appears. The highlighted row (`results[0]`)
/// carries extra emphasis and a `⏎` Enter hint.
struct ActionRow: View {
    let action: Action
    var isHighlighted: Bool = false

    /// The row's corner radius — a **fixed** value shared by every row, not a
    /// capsule. A `Capsule` rounds by half the height, so a single-line row reads
    /// as a clean pill but a multi-line one (a file with a wrapping name over its
    /// relative-path subtitle) balloons into an oversized stadium. A fixed radius
    /// keeps the one-line pill look while giving tall rows the *same* rounding, so
    /// the stack reads consistently. Tuned to a single-line row's half-height
    /// (badge 30 + vertical padding 2×10 = 50) so short rows are unchanged.
    private let cornerRadius: CGFloat = 25

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

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
            if isHighlighted {
                EnterHint(mainAction: action.mainAction)
            } else {
                MainActionGlyph(mainAction: action.mainAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: rowShape)
        // A hairline accent ring plus a soft accent wash lift the highlighted row
        // above the stack so it reads as the default without shouting (ADR 0010
        // budget).
        .overlay {
            if isHighlighted {
                rowShape
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay {
                        rowShape.strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    }
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .contentShape(rowShape)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// The `⏎` + main-action-glyph hint shown on the highlighted row: it spells out
/// precisely what pressing Return will do (CONTEXT.md → Highlighted result).
private struct EnterHint: View {
    let mainAction: MainAction

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "return")
            if let symbol = mainAction.symbol {
                Image(systemName: symbol)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The Pin/Unpin affordance shared by every row that can be favorited. A
    /// long-press context menu keeps pinning out of the typing fast path; it is
    /// distinct from the deferred *secondary actions* long-press (ADR 0008),
    /// which operates on a result's content rather than its place in the index.
    ///
    /// `canPin` reflects the Favorites cap (CONTEXT.md → Favorite): when the grid
    /// is full, the "Pin as Favorite" item is disabled with a hint rather than
    /// silently swallowing the gesture — Unpin is always available.
    func favoriteContextMenu(
        isFavorite: Bool,
        canPin: Bool = true,
        toggle: @escaping () -> Void
    ) -> some View {
        contextMenu {
            Button {
                toggle()
            } label: {
                Label(isFavorite ? "Unpin Favorite" : "Pin as Favorite",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
            .disabled(!isFavorite && !canPin)
            if !isFavorite && !canPin {
                Text("Favorites are full (max \(SignalsStore.maxFavorites)). Unpin one first.")
            }
        }
    }
}
