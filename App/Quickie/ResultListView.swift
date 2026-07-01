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
    /// Runs a one-shot secondary action (Copy / Share / Reveal in Files) on a
    /// row's content (CONTEXT.md → Secondary action; ADR 0017). The App resolves
    /// the content at the edge and performs the verb.
    var onSecondaryAction: (Action, SecondaryActionKind) -> Void = { _, _ in }

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
                        .resultContextMenu(
                            secondaryActions: secondaryActions(for: action.content),
                            onSecondaryAction: { onSecondaryAction(action, $0) },
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
        // Swiping down the list dismisses the keyboard the native iOS way (issue
        // #64): the keyboard tracks the drag off-screen, the input bar drops to the
        // bottom, and the query + results are preserved — no custom gesture, just
        // the system scroll-dismiss so more results become visible.
        .scrollDismissesKeyboard(.interactively)
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
    /// A row's long-press menu: its eligible **secondary actions** (Copy / Share /
    /// Reveal in Files, keyed by the result's content — CONTEXT.md → Secondary
    /// action; ADR 0017) combined with the **Pin/Unpin** item, in **one** menu on
    /// **one** gesture. A content-less row (command / capture / shortcut) passes an
    /// empty `secondaryActions`, so it shows only Pin/Unpin, exactly as before — no
    /// dead items, a verb appears only when it can run.
    ///
    /// `canPin` reflects the Favorites cap (CONTEXT.md → Favorite): when the grid
    /// is full, the "Pin as Favorite" item is disabled with a hint rather than
    /// silently swallowing the gesture — Unpin is always available.
    func resultContextMenu(
        secondaryActions: [SecondaryActionKind] = [],
        onSecondaryAction: @escaping (SecondaryActionKind) -> Void = { _ in },
        isFavorite: Bool,
        canPin: Bool = true,
        toggle: @escaping () -> Void
    ) -> some View {
        contextMenu {
            ForEach(secondaryActions, id: \.self) { kind in
                Button {
                    onSecondaryAction(kind)
                } label: {
                    Label(kind.menuTitle, systemImage: kind.menuSymbol)
                }
                .accessibilityIdentifier("secondary.\(kind.menuIdentifier)")
            }
            // A visual break between the content verbs and the pin affordance, only
            // when there are content verbs to separate.
            if !secondaryActions.isEmpty {
                Divider()
            }
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

/// The App-side presentation of a `SecondaryActionKind` (CONTEXT.md → Secondary
/// action): its menu label, SF Symbol, and a stable identifier for UI tests.
/// Core owns the *eligibility* verb; how it reads in the menu is a view concern.
extension SecondaryActionKind {
    var menuTitle: String {
        switch self {
        case .copy: return "Copy"
        case .share: return "Share"
        case .revealInFiles: return "Reveal in Files"
        }
    }

    var menuSymbol: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .share: return "square.and.arrow.up"
        case .revealInFiles: return "folder"
        }
    }

    var menuIdentifier: String {
        switch self {
        case .copy: return "copy"
        case .share: return "share"
        case .revealInFiles: return "reveal"
        }
    }
}
