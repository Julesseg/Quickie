import SwiftUI
import QuickieCore

/// The reversed, bottom-anchored Result list (ADR 0008): the best match sits
/// nearest the input and the thumb, with weaker matches stacking upward and
/// scrolling away. We reverse the ranked array so rank 0 renders last (lowest),
/// and anchor the scroll view to the bottom so it opens at the best match.
///
/// One row is the **highlighted result** (CONTEXT.md → Highlighted result):
/// rendered with distinct emphasis and a `⏎` + main-action-glyph hint so it reads
/// as the default, since pressing Return runs exactly its main action. It is rank 0
/// until a hardware ↑/↓ walks it elsewhere (issue #267).
struct ResultListView: View {
    /// The ranked rows to render (CONTEXT.md → Result list; issue #195): each an
    /// Action plus its region and Match highlight, so a row bolds why it surfaced and
    /// a tap knows whether it rides the fallback region.
    let results: [ResultRow]
    /// Which rank wears the highlight — rank 0 unless the arrow keys have moved it,
    /// `nil` when there is nothing to highlight. The launcher resolves it through
    /// Core's `ResultSelection`, so the row drawn as the default and the row Return
    /// runs are decided in one place.
    var highlightedRank: Int? = 0
    let onRun: (ResultRow) -> Void
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
                // PROTOTYPE (#286): rows leave the `GlassEffectContainer`.
                Group {
                    VStack(spacing: 6) {
                        // Rows are keyed by **rank**, not by the Action they show,
                        // so a keystroke that re-ranks the results swaps each slot's
                        // content in place instead of flying rows across the screen
                        // — the bottom slot never moves, its text just changes (and
                        // a keystroke re-arms the highlight there, so the highlight
                        // does not move either). Only a change in *count* inserts or
                        // removes a slot, and only that slot animates: its transition carries
                        // its own animation (Motion.swift), so the layout around it
                        // applies instantly.
                        ForEach(results.indices.reversed(), id: \.self) { rank in
                            let row = results[rank]
                            let action = row.action
                            Button {
                                onRun(row)
                            } label: {
                                ActionRow(action: action, isHighlighted: rank == highlightedRank, match: row.match)
                            }
                            .buttonStyle(.plain)
                            // A pointer crossing the list lights each row in the row's
                            // own pill shape (CONTEXT.md → Pointer hover).
                            .pointerHover(in: ActionRow.shape)
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
                                ActionRow(action: action, match: row.match)
                                    .frame(maxWidth: .infinity)
                            }
                            .transition(rowMotion.insertionTransition)
                        }
                    }
                    // The readable command column (ADR 0039): at regular width the
                    // rows lay out in the same centred column the input bar does,
                    // instead of a label and its glyph sitting 1,300pt apart. The
                    // rows keep their own 12pt inset off the column's edge, exactly
                    // as they keep it off an iPhone's screen edge.
                    .commandColumn()
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
            // Keep a walked highlight visible (issue #267) — nothing at all while it
            // sits on rank 0 at the bottom, which is every touch-driven change.
            .keepsHighlightVisible(at: highlightedRank)
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

extension View {
    /// Keeps the walked **Highlighted result** on screen (CONTEXT.md → Highlighted
    /// result; issue #267). Applied to a result list's `ScrollView`, which it wraps
    /// in the `ScrollViewReader` the scroll needs.
    ///
    /// Both reversed lists — the root Result list and the [[Search Files context]]'s
    /// — key their rows by **rank**, so the rank *is* the scroll target, and both
    /// need exactly this: one modifier rather than the same `ScrollViewReader` twice.
    ///
    /// `scrollTo` moves the minimum distance to bring the row into view, so it does
    /// nothing at all while the highlighted row is already on screen — which is every
    /// touch-driven change, where the highlight sits on rank 0 at the bottom. The
    /// motion borrows `.inputFocus` from the budget (ADR 0010), the moment closest to
    /// a keystroke, because that is what an arrow key is: the list must not lag the
    /// hand holding the key down.
    func keepsHighlightVisible(at rank: Int?) -> some View {
        modifier(KeepsHighlightVisible(rank: rank))
    }
}

private struct KeepsHighlightVisible: ViewModifier {
    let rank: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { scroller in
            content
                .onChange(of: rank) { _, rank in
                    guard let rank else { return }
                    let motion = MotionPolicy(reduceMotion: reduceMotion).style(for: .inputFocus)
                    withAnimation(motion.animation) { scroller.scrollTo(rank) }
                }
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
    /// The **Match highlight** (CONTEXT.md → Match highlight; issue #195): which
    /// title letters to bold because the query found its place there. `nil` on a
    /// boosted, fallback, or Home row — those never name-matched, so they stay plain.
    var match: MatchHighlight? = nil

    /// The row's corner radius — a **fixed** value shared by every row, not a
    /// capsule. A `Capsule` rounds by half the height, so a single-line row reads
    /// as a clean pill but a multi-line one (a file with a wrapping name over its
    /// relative-path subtitle) balloons into an oversized stadium. A fixed radius
    /// keeps the one-line pill look while giving tall rows the *same* rounding, so
    /// the stack reads consistently. `QuickieRadius.row` is tuned to a single-line
    /// row's half-height (badge 30 + vertical padding 2×10 = 50).
    ///
    /// Static, so the surfaces that wrap a row in a button can hover the pointer in the
    /// row's *own* face (`pointerHover(in:)`) instead of restating the radius and
    /// drifting from it.
    static let shape = RoundedRectangle(cornerRadius: QuickieRadius.row, style: .continuous)

    /// Whether this row is a Computed result (the Calculator's answer / conversion
    /// or a Detected value — ADR 0032): the rows whose text is a *value*, rendered
    /// with monospaced (tabular) digits so it reads as an answer, not prose
    /// (ADR 0033). `Text.monospacedDigit()` swaps digit glyphs only, so the
    /// treatment scales with Dynamic Type like every other row.
    private var isComputed: Bool { action.kind == .calculator }

    /// Wraps a row string as `Text`, with tabular digits when this is a Computed
    /// row. Built as `Text` (not via a view modifier) because `monospacedDigit`
    /// is applied conditionally and `Text.monospacedDigit()` keeps the result a
    /// `Text`. Shared by the title and subtitle so the two channels can't
    /// disagree on the treatment.
    private func rowText(_ string: String) -> Text {
        let text = Text(string)
        return isComputed ? text.monospacedDigit() : text
    }

    /// The title as `Text`, with the **Match highlight**'s letters bold when this row
    /// name-matched (CONTEXT.md → Match highlight; issue #195). Bolding is applied as
    /// `.stronglyEmphasized` inline intent on the matched character offsets so it
    /// composes with the row's rounded face rather than replacing it; with no match
    /// (a boosted, fallback, or Home row) it falls through to plain `rowText`, so a
    /// Computed row keeps its tabular digits. The offsets index the title's Characters
    /// as the Core alignment produced them (case/diacritic folding is one grapheme to
    /// one, so an accented letter bolds correctly); an out-of-range offset from a rare
    /// count-changing fold simply doesn't bold, never crashes.
    private func titleText() -> Text {
        guard let bold = match?.titleBold, !bold.isEmpty else {
            return rowText(action.title)
        }
        return .matchHighlighted(action.title, bold: bold)
    }

    /// The row title in its rounded chrome face (ADR 0033) — the styling shared by the
    /// plain and the pill-bearing layouts, so the two can't drift. Only pill rows clamp
    /// it to one line (below); a title with no pill keeps its natural wrapping — a file
    /// row's long name still flows over its relative-path subtitle rather than truncating.
    private var styledTitle: some View {
        titleText()
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.primary)
    }

    var body: some View {
        HStack(spacing: 12) {
            // A Custom Action's chosen glyph (issue #163) overrides the kind-derived
            // one; a user-chosen Action color replaces the kind's tint (issue #243),
            // and a detected hex color's parsed swatch overrides even that (issue #217)
            // so the row wears the color it found; `nil` throughout falls back to the
            // derived badge, so every other row is unchanged.
            ProviderBadge(
                kind: action.kind,
                symbol: action.glyph,
                color: action.color,
                tint: action.glyphTint?.color
            )
            VStack(alignment: .leading, spacing: 2) {
                // Rounded chrome type (ADR 0033), with tabular digits on a Computed
                // row so the answer reads as an answer: `5` and `1` take the same
                // advance and the value sits still as the expression grows. The
                // subtitle carries the computed *value* on a Detected row (the URL /
                // number / address) and the expression on a Calculator row, so it
                // gets the tabular treatment too — but stays in the muted default
                // design; only titles wear the rounded face.
                //
                // The **Alias pill** rides inline right after the title (issue #196),
                // reading as part of the name ("Things 〔th〕"). Only a pill row clamps
                // its title to one line — with the pill held at its intrinsic size
                // (`fixedSize`), a long title truncates around the pill rather than
                // shoving it off the row. A pill-less row keeps the title's natural
                // wrapping (a file's long name still flows over its subtitle). The pill
                // asks Core whether it owns the match (`pillBold`) rather than
                // re-deriving the single-source rule here.
                if let pill = action.aliasPill {
                    HStack(spacing: 6) {
                        styledTitle
                            .lineLimit(1)
                        AliasPill(alias: pill, bold: match?.pillBold(for: pill, aliases: action.aliases) ?? [])
                            .accessibilityIdentifier("alias-pill.\(action.id)")
                    }
                } else {
                    styledTitle
                }
                if let subtitle = action.subtitle {
                    rowText(subtitle)
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
        // The gold hero treatment lives on the row itself, not on the backdrop: a
        // glow behind the glass can't be kept to one row — it bleeds behind the
        // neighbours above it — so the Highlighted result carries its own gold
        // (issue #177). It is a *soft gradient glow* rather than a flat wash: a
        // radial gold, faint at the row's centre and gone before its edges, that
        // swings once when a new Action lands in the hero slot and settles to
        // centre about a second later (`HeroGlow`) — so the glow announces a change
        // of best match and stays calm while typing merely re-confirms it. Gold is
        // spent here and nowhere else (ADR 0033, enforced by `check-brand-assets.py`).
        // The overlay sits *before* `glassEffect`, so the glow is part of the row's
        // content and the glass renders over it — the light reads as lit within the
        // glass rather than a wash painted on top of it.
        // PROTOTYPE (#286): the glass and the glow it composited under are
        // replaced by the switchable row dress. Geometry below is untouched.
        .modifier(PrototypeRowDress(shape: Self.shape, isHighlighted: isHighlighted, heroID: action.id))
        .padding(.horizontal, 12)
        .contentShape(Self.shape)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

// PROTOTYPE (#286): `HeroGlow` moved to `HeroSwing` in RowMaterialPrototype.swift.

/// The **Alias pill** (CONTEXT.md → Alias pill; issue #196): the small, dim,
/// caption-sized capsule a Custom Action (or an aliased Shortcut) wears right after
/// its title, so the user re-learns the alias they defined — shown on every such row
/// all the time, query or not. A *memory aid*, not a match explanation on its own:
/// it stays dim by default, and the **Match highlight**'s single-source rule layers
/// bolding on top only when the alias strictly outscored the title (`bold` carries
/// the matched letters then; empty otherwise, including on every fallback-region and
/// Home row, which carry no match — so the pill never bolds there).
private struct AliasPill: View {
    let alias: String
    /// The matched-letter offsets to bold, from the winning alias's alignment — empty
    /// unless the alias claimed the match, keeping the pill dim.
    var bold: [Int] = []

    var body: some View {
        pillText
            .font(.caption)
            // Dim: the pill reads as a quiet memory aid, not a second title. When it
            // wins the match the bold letters emphasize *through* this same secondary
            // tint — weight alone marks the match, so an unmatched pill and a matched
            // one share one colour.
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule(style: .continuous).fill(.quaternary))
            // Hold the pill's intrinsic size so a long title truncates around it
            // rather than shoving it out of the row (issue #196 AC).
            .fixedSize()
    }

    /// The alias as `Text`, with its matched letters bold when the alias won — via the
    /// same shared `matchHighlighted` builder the title and the choice list use, so a
    /// match reads identically wherever it lands. Plain `Text` when `bold` is empty.
    private var pillText: Text {
        bold.isEmpty ? Text(alias) : .matchHighlighted(alias, bold: bold)
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
    ///
    /// `title` names the pressed Action as a **non-action row** at the top of the
    /// menu — for the surfaces whose control doesn't say what it is. A result row and
    /// a Favorite card both wear their title already, so they pass nothing; a
    /// [[Shelf]] button is an icon-only circle, so the name it used to reveal in a
    /// floating capsule is now the menu's first line (CONTEXT.md → Shelf). It is a
    /// plain `Text`, not a `Button`: the same non-action row the Favorites-cap hint
    /// below already uses, so it reads as a label rather than a verb that does
    /// nothing.
    func resultContextMenu<Preview: View>(
        title: String? = nil,
        secondaryActions: [SecondaryActionKind] = [],
        onSecondaryAction: @escaping (SecondaryActionKind) -> Void = { _ in },
        isFavorite: Bool,
        pinnable: Bool = true,
        canPin: Bool = true,
        toggle: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        // PROTOTYPE (#286): `-proto-plain-menu` drops the lifted preview so the
        // system's plain in-place highlight can be judged on a non-glass row.
        // (The preview is also `ContextMenuPresence`'s signal, so the keyboard
        // lift is not held under a plain menu — irrelevant to a screenshot.)
        Group {
            if RowMaterialPrototype.plainMenu {
                contextMenu {
                    prototypeMenuItems(title: title, secondaryActions: secondaryActions, onSecondaryAction: onSecondaryAction, isFavorite: isFavorite, pinnable: pinnable, canPin: canPin, toggle: toggle)
                }
            } else {
                contextMenu {
                    prototypeMenuItems(title: title, secondaryActions: secondaryActions, onSecondaryAction: onSecondaryAction, isFavorite: isFavorite, pinnable: pinnable, canPin: canPin, toggle: toggle)
                } preview: {
                    preview()
                        .onAppear { ContextMenuPresence.shared.menuAppeared() }
                        .onDisappear { ContextMenuPresence.shared.menuDisappeared() }
                }
            }
        }
    }

    @ViewBuilder
    private func prototypeMenuItems(
        title: String?,
        secondaryActions: [SecondaryActionKind],
        onSecondaryAction: @escaping (SecondaryActionKind) -> Void,
        isFavorite: Bool,
        pinnable: Bool,
        canPin: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
            if let title {
            Text(title)
            // Separated from the verbs below only when there are verbs: a menu
            // that is nothing but the title (a shelved "Save for later", whose
            // deeplink is withheld and which offers no pin) must not open with a
            // rule under a single line.
            if !secondaryActions.isEmpty || pinnable {
                Divider()
            }
        }
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
    }
}

extension Text {
    /// The shared **Match highlight** rendering (CONTEXT.md → Match highlight; issue
    /// #195): `string` as `Text` with the given character offsets bold, used by both
    /// the Result list rows and the breadcrumb's choice list so a match reads the same
    /// everywhere. Bold is applied as `.stronglyEmphasized` inline intent so it
    /// composes with whatever base font the caller sets rather than replacing it.
    /// Offsets index `string`'s Characters as the Core alignment produced them; an
    /// out-of-range offset from a rare count-changing fold simply doesn't bold, never
    /// crashes. An empty `bold` returns plain `Text`.
    static func matchHighlighted(_ string: String, bold: [Int]) -> Text {
        guard !bold.isEmpty else { return Text(string) }
        let boldOffsets = Set(bold)
        var attributed = AttributedString()
        for (offset, character) in string.enumerated() {
            var piece = AttributedString(String(character))
            if boldOffsets.contains(offset) {
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            attributed.append(piece)
        }
        return Text(attributed)
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
