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
    /// Reports whether the list is mid-drag, so the launcher can tell an intentional
    /// swipe-dismiss (issue #64 — drop the bar) from a context-menu keyboard
    /// dismissal (issue #58 — hold the layout in place).
    var onScrollActive: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tight animation budget (ADR 0010): a subtle spring as row slots appear
    /// and disappear with the result count, degrading to a fade under Reduce Motion.
    private var rowMotion: MotionStyle {
        MotionPolicy(reduceMotion: reduceMotion).style(for: .rowInsert)
    }

    var body: some View {
        // The viewport height pins the stack to the ScrollView's bottom edge (the
        // `minHeight` + `.bottom` frame below), so every slot's position is
        // measured from a fixed bottom — a slot appearing or disappearing at the
        // weak (top) end cannot shift the rows beneath it. Without the pin the
        // undersized content is only bottom-aligned by the scroll anchor, whose
        // re-alignment during an animated resize sets the whole list adrift.
        GeometryReader { viewport in
            ScrollView {
                // A single container so the neighbouring glass capsules blend and
                // morph as one Liquid Glass surface rather than stacking flatly.
                GlassEffectContainer(spacing: 6) {
                    VStack(spacing: 6) {
                        // Rows are keyed by **rank**, not by the Action they show,
                        // so a keystroke that re-ranks the results swaps each slot's
                        // content in place instead of flying rows across the screen
                        // — the highlighted slot (rank 0) never moves, its text just
                        // changes. Only a change in *count* inserts or removes a
                        // slot, and only that slot animates: its transition carries
                        // its own animation (Motion.swift), so the layout around it
                        // applies instantly.
                        ForEach(results.indices.reversed(), id: \.self) { rank in
                            let action = results[rank]
                            Button {
                                onRun(action)
                            } label: {
                                ActionRow(action: action, isHighlighted: rank == 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(action.id)
                            .resultContextMenu(
                                secondaryActions: secondaryActions(for: action.content, includeDeeplink: !action.isQueryOnlyCapture),
                                onSecondaryAction: { onSecondaryAction(action, $0) },
                                isFavorite: isFavorite(action),
                                pinnable: action.isFavoriteEligible,
                                canPin: canFavorite(action),
                                toggle: { onToggleFavorite(action) }
                            ) {
                                // The lifted preview: a copy of this row, so the
                                // long-pressed result detaches as a floating card.
                                ActionRow(action: action)
                                    .frame(maxWidth: .infinity)
                            }
                            .transition(rowMotion.insertionTransition)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .bottom)
            }
            .defaultScrollAnchor(.bottom)
            // Swiping down the list dismisses the keyboard the native iOS way (issue
            // #64): the keyboard tracks the drag off-screen, the input bar drops to
            // the bottom, and the query + results are preserved — no custom gesture,
            // just the system scroll-dismiss so more results become visible.
            .scrollDismissesKeyboard(.interactively)
            // Report drag state so the launcher can tell this swipe-dismiss (drop
            // the bar) from a context-menu keyboard dismissal (hold the layout in
            // place). Only an active drag counts — *not* `.tracking`, the
            // finger-down-but-still state a long-press sits in, which must read as
            // "not scrolling" so the context menu freezes the layout.
            .onScrollPhaseChange { _, phase in
                onScrollActive(phase == .interacting || phase == .decelerating)
            }
        }
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
    /// Reveal in Files / Edit keyed by the result's content, plus the universal
    /// **Copy action deeplink** keyed by its id — CONTEXT.md → Secondary action;
    /// ADR 0017, issue #120) combined with the **Pin/Unpin** item, in **one** menu on
    /// **one** gesture. Every row carries at least Copy action deeplink now, so even a
    /// content-less command/capture row shows that plus Pin/Unpin (its content verbs
    /// stay absent) — no dead items, a verb appears only when it can run.
    ///
    /// `pinnable` reflects **favorite eligibility** (`Action.isFavoriteEligible`):
    /// a Pile entry — consumed by its own main action, so a pin would ghost a grid
    /// slot — omits the Pin/Unpin item entirely (no dead items), leaving only its
    /// content verbs. `canPin` reflects the Favorites cap (CONTEXT.md → Favorite):
    /// when the grid is full, the "Pin as Favorite" item is disabled with a hint
    /// rather than silently swallowing the gesture — Unpin is always available.
    ///
    /// `preview` supplies the **lifted preview** (`contextMenu(menuItems:preview:)`):
    /// the system renders it as a detached card floating over a dimmed backdrop, so
    /// the long-pressed row visibly separates from the list. Without it the default
    /// in-place highlight barely reads against the translucent Liquid Glass rows —
    /// the lifted snapshot looks like the resting row. Each caller passes its own
    /// row (an `ActionRow`, or a `FavoriteCard` for the grid) so the preview matches
    /// what was pressed.
    func resultContextMenu<Preview: View>(
        secondaryActions: [SecondaryActionKind] = [],
        onSecondaryAction: @escaping (SecondaryActionKind) -> Void = { _ in },
        isFavorite: Bool,
        pinnable: Bool = true,
        canPin: Bool = true,
        toggle: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        contextMenu {
            ForEach(secondaryActions, id: \.self) { kind in
                Button {
                    onSecondaryAction(kind)
                } label: {
                    Label(kind.menuTitle, systemImage: kind.menuSymbol)
                }
                // No explicit accessibilityIdentifier: it would override the
                // label-based lookup XCUITest uses (`app.buttons["Copy"]`), just as
                // the Pin item is found by its "Pin as Favorite" label. The verb's
                // menu title *is* its stable identifier.
            }
            if pinnable {
                // A visual break between the content verbs and the pin affordance,
                // only when there are content verbs to separate.
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
        } preview: {
            preview()
        }
    }
}

/// The App-side presentation of a `SecondaryActionKind` (CONTEXT.md → Secondary
/// action): its menu label and SF Symbol. The label doubles as the button's
/// accessibility identifier (no explicit one is set), so UI tests find it by
/// title. Core owns the *eligibility* verb; how it reads in the menu is a view
/// concern.
extension SecondaryActionKind {
    var menuTitle: String {
        switch self {
        case .copy: return "Copy"
        case .share: return "Share"
        case .revealInFiles: return "Reveal in Files"
        case .edit: return "Edit"
        case .copyDeeplink: return "Copy action deeplink"
        }
    }

    var menuSymbol: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .share: return "square.and.arrow.up"
        case .revealInFiles: return "folder"
        case .edit: return "pencil"
        case .copyDeeplink: return "link"
        }
    }
}
