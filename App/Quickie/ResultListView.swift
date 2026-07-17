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
    /// The live query, forwarded to the highlighted row so its gold glow can stir
    /// on each keystroke and settle when typing stops (issue #177).
    var query: String = ""
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
                                ActionRow(action: action, isHighlighted: rank == 0, query: query)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(action.id)
                            .resultContextMenu(
                                secondaryActions: secondaryActions(for: action.content, includeDeeplink: !action.isSilentQueryCapture),
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
        // Weak matches scroll up under the status bar; without a band the status
        // bar sits directly on row text and both turn unreadable. Anchored inside
        // the list so it slides out with it as one block during a capture
        // transition (`statusBarBleed`), like the Home Favorites band.
        .overlay(alignment: .top) {
            StatusBarBlurBand()
        }
    }
}

/// The bare progressive-blur band behind the status bar: solid at the screen's
/// top edge, fading clear just below the status area so scrolling content
/// dissolves under it rather than colliding with the status bar's text. The
/// gradient-masked-material idiom the breadcrumb bars use (kept private there),
/// but with no content riding it — shared by the surfaces that scroll to the top
/// with no chrome of their own (the Result list, a grid-less Home). Ultra-thin,
/// like Home's Favorites band: with nothing floating on it, the blur alone
/// separates the status bar from the rows — a heavier wash would read as chrome.
struct StatusBarBlurBand: View {
    var body: some View {
        Color.clear
            .frame(height: 0)
            .statusBarBleed(topPadding: 16) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.6),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            // Purely decorative — it must never swallow a tap or a scroll that
            // starts under the status area.
            .allowsHitTesting(false)
    }
}

/// One row: an Action presented by its main action (title + optional subtitle).
/// Shared by the Result list and the Home Frecency list so a remembered Action
/// reads identically wherever it appears. The highlighted row (`results[0]`)
/// carries extra emphasis and a `⏎` Enter hint.
struct ActionRow: View {
    let action: Action
    var isHighlighted: Bool = false
    /// The live query, passed only by the result lists so the highlighted row's
    /// gold glow can stir back into motion on each keystroke and settle when typing
    /// stops (issue #177). Empty everywhere the row is never highlighted (Home, the
    /// lifted preview), where it does nothing.
    var query: String = ""

    /// The row's corner radius — a **fixed** value shared by every row, not a
    /// capsule. A `Capsule` rounds by half the height, so a single-line row reads
    /// as a clean pill but a multi-line one (a file with a wrapping name over its
    /// relative-path subtitle) balloons into an oversized stadium. A fixed radius
    /// keeps the one-line pill look while giving tall rows the *same* rounding, so
    /// the stack reads consistently. `QuickieRadius.row` is tuned to a single-line
    /// row's half-height (badge 30 + vertical padding 2×10 = 50).
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: QuickieRadius.row, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 12) {
            // A Custom Action's chosen glyph (issue #163) overrides the kind-derived
            // one; `nil` falls through to the derived glyph, so an unset action is
            // unchanged.
            ProviderBadge(kind: action.kind, symbol: action.glyph)
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
        // The gold hero treatment lives on the row itself, not on the backdrop: a
        // glow behind the glass can't be kept to one row — it bleeds behind the
        // neighbours above it — so the Highlighted result carries its own gold
        // (issue #177). It is a *soft gradient glow* rather than a flat wash: a
        // radial gold, faint at the row's centre and gone before its edges, that
        // slides gently side to side while a query is still being typed and settles
        // to centre about a second after the last keystroke (`HeroGlow`) — so the
        // hero row feels alive while you type and calm once you've stopped. Gold is
        // spent here and nowhere else (ADR 0033, enforced by `check-brand-assets.py`).
        .overlay {
            if isHighlighted {
                HeroGlow(shape: rowShape, query: query)
            }
        }
        .padding(.horizontal, 12)
        .contentShape(rowShape)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// The Highlighted result's gold glow: a soft radial gold, clipped to the row, that
/// **slides gently side to side while the query is still being typed** and settles
/// back to centre about a second after the last keystroke (issue #177). So the hero
/// row shimmers while you type and comes to rest once you've stopped — the "alive at
/// rest / calm in use" budget (ADR 0034) read the other way round: the one flicker
/// of life is *tied to* the act of typing and ends with it, rather than running
/// forever under settled results.
///
/// Motion is driven off the `query` string, not per-keystroke view work: each change
/// stirs the swing (if it isn't already going) and *debounces* a settle ~1s out, so
/// a burst of keystrokes keeps it moving smoothly and only the pause at the end lands
/// it. It degrades like the rest of the budget — under Reduce Motion and UI test the
/// glow is simply static and centred, no swing, no timer.
private struct HeroGlow: View {
    var shape: RoundedRectangle
    /// The live query; each change re-stirs the swing and resets the settle timer.
    var query: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The glow's horizontal offset, animated between ∓`amplitude` while swinging.
    @State private var swing: CGFloat = 0
    /// Whether the repeating swing is currently running (so a keystroke mid-swing
    /// doesn't restart it — it just pushes the settle further out).
    @State private var swinging = false
    /// The debounced "typing has stopped" task, cancelled and rescheduled per change.
    @State private var settleTask: Task<Void, Never>?
    /// The short delay that lets the glow glide to one extreme before the repeating
    /// swing begins (see `stir`), cancelled if typing stops inside that window.
    @State private var startTask: Task<Void, Never>?

    /// The glow swings only when motion is allowed; otherwise it is a plain centred
    /// radial with no animation and no timer (Reduce Motion, UI test).
    private var animates: Bool { !reduceMotion && !MotionStyle.isInstantForUITesting }

    /// How far the glow swings to each side of centre while typing — small enough to
    /// read as a shimmer of the light, not the row sliding. At rest `swing == 0`, so
    /// the glow sits dead centre; while typing it oscillates `-amplitude … +amplitude`.
    private let amplitude: CGFloat = 16

    var body: some View {
        RadialGradient(
            colors: [QuickieBrand.gold.opacity(0.2), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 220
        )
        .offset(x: swing)
        // Keep the drifting glow inside the row — its bright centre slides, but the
        // light never spills past the capsule onto a neighbour.
        .clipShape(shape)
        .allowsHitTesting(false)
        .onChange(of: query) { _, _ in stir() }
        .onDisappear { settleTask?.cancel(); startTask?.cancel() }
    }

    /// A keystroke: start the side-to-side swing if it isn't already going, and push
    /// the settle a fresh second into the future so a run of keystrokes keeps it
    /// alive and only the final pause brings it to rest.
    private func stir() {
        guard animates else { return }
        if !swinging {
            swinging = true
            // `repeatForever(autoreverses:)` oscillates between the value it starts at
            // and its target, so a *symmetric* swing about centre has to begin at one
            // extreme. Glide there first (a soft ease from centre, no jump), then —
            // once arrived — start the repeating leg that carries it across to the far
            // side and back forever. Sequenced with a task rather than a delayed
            // animation because two `withAnimation`s on the same value in one tick
            // would just clobber each other (only the last target survives).
            withAnimation(.easeInOut(duration: 0.6)) { swing = -amplitude }
            startTask?.cancel()
            startTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                if Task.isCancelled || !swinging { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    swing = amplitude
                }
            }
        }
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            swinging = false
            // Replace the repeating animation with a single ease back to centre —
            // "on the last keystroke it takes a second to settle."
            withAnimation(.easeOut(duration: 1.0)) { swing = 0 }
        }
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
