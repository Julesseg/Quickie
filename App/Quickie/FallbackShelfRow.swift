import SwiftUI
import QuickieCore

/// The **Shelf** (CONTEXT.md → Shelf; ADR 0037; issue #242): the horizontal, scrollable
/// row of circular, icon-only Liquid Glass buttons directly above the input, one per
/// shelved [[Fallback Action]], most-important-first from the leading edge. A tap
/// **seeds-and-commits** the typed query exactly like a fallback-region row — the host
/// runs the action with the `.fallback` region, so the two surfaces share one code path
/// and can never disagree about what a tap does.
///
/// The row is built on two pure rules from Core's `FallbackShelf`, so neither is
/// eyeballed here: it renders only while there is a query to seed (the host gates on
/// `isVisible`), and its buttons are sized so that when members run past the trailing
/// edge the next one is left visibly **cut** by it — the sizing cue that says "this
/// scrolls", replacing the member cap and overflow menu the share sheet's app row
/// doesn't have either.
///
/// Because the buttons are icon-only, a **long press names the action** — the agreed
/// disambiguation affordance for a glyph with no label (a design prototype settled
/// icon-only circles over icon+label pills: labels don't fit four across at readable
/// sizes). It names it in the *same* long-press menu every other Action surface carries
/// (`resultContextMenu`), as the menu's non-action first row, rather than in a bespoke
/// floating capsule on a bespoke gesture: one hold, one menu, and a Shelf button is no
/// longer the one Action on screen you cannot Copy, Share, or Pin.
struct FallbackShelfRow: View {
    /// The launcher's Shelf metrics — Core's own preset, so the sizing rule is tested
    /// against the numbers that ship. The one value passed in is the bar's height: the
    /// buttons are the same circle the paste chip is, which is what makes the Shelf read
    /// as part of the bottom glass body rather than a foreign strip above it.
    static let layout = FallbackShelf.Layout.launcher(preferredDiameter: InputBar.barHeight)

    /// The shelved Actions, most-important-first — already resolved to the live
    /// catalog and filtered of disabled instances by the host.
    let members: [Action]
    /// Seeds-and-commits the typed query as this action's first Argument. The host
    /// routes it through the same run path a `.fallback` result row takes.
    let onRun: (Action) -> Void
    /// Whether a member is pinned — drives its Pin/Unpin menu label, exactly as a
    /// result row's does.
    var isFavorite: (Action) -> Bool = { _ in false }
    /// Whether a member can still be pinned (false once the Favorites cap is hit).
    var canFavorite: (Action) -> Bool = { _ in true }
    /// Toggles a member's Favorite pin.
    var onToggleFavorite: (Action) -> Void = { _ in }
    /// Runs a one-shot secondary action on a member (CONTEXT.md → Secondary action;
    /// ADR 0017) — the same host handler the Result list's rows are given, so a
    /// shelved action's verbs behave identically to the same action's in the list.
    var onSecondaryAction: (Action, SecondaryActionKind) -> Void = { _, _ in }

    /// The row's own width, measured — the input to the peek sizing. Zero until the
    /// first layout pass, which Core reads as "unmeasured" and answers with the
    /// preferred diameter.
    @State private var rowWidth: CGFloat = 0

    private var diameter: CGFloat {
        Self.layout.diameter(availableWidth: rowWidth, memberCount: members.count)
    }

    var body: some View {
        // Spacing 0: the buttons sit close enough that a blending container would fuse
        // them into one glass blob. They are separate controls and must read as such —
        // the container is here only so they share one glass rendering pass.
        GlassEffectContainer(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: Self.layout.spacing) {
                    ForEach(members) { member in
                        button(for: member)
                    }
                }
                // Both edges — and Core's sizing reserves both, so a row it calls
                // settled really does sit inside the viewport instead of scrolling by
                // the width of its own trailing padding.
                .padding(.horizontal, Self.layout.contentInset)
            }
            // No scroll bar under the thumb: the peeking button is the affordance.
            .scrollIndicators(.hidden)
            // The row's own width, not its content's — the viewport the peek is sized
            // against, and stable regardless of how many members there are.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        }
        .frame(height: diameter)
    }

    /// How much of the action's kind hue the glass carries.
    ///
    /// The full-strength colour is `ProviderBadge`'s treatment, and it belongs there:
    /// a 30pt squircle inside a row wants to be unmistakably *that provider*. At 52pt
    /// on its own above the input the same colour stops being a badge and becomes the
    /// button — four flat, saturated discs with no material left in them, louder than
    /// the input they sit over. Held back to a tint the glass carries rather than one
    /// that replaces it: the hue still says which action each button is, and the row
    /// still reads as part of the bottom glass body (ADR 0010 — depth is the glass's
    /// job). Matches the capture breadcrumb's own tinted crumbs, the only other
    /// tinted glass in the app.
    private static let tintStrength = 0.4

    /// One Shelf member: a tap seeds-and-commits the query, a long press opens the
    /// Action's own menu.
    private func button(for action: Action) -> some View {
        Button {
            onRun(action)
        } label: {
            glyphCircle(for: action)
        }
        // Plain, like every other Action surface's button: the glass circle *is* the
        // control's appearance, and a bordered style would draw a second one around it.
        .buttonStyle(.plain)
        // The one long-press menu every Action carries (CONTEXT.md → Secondary action;
        // ADR 0017), with the action's **title** as its non-action first row: an
        // icon-only button has nowhere else to say what it is, which is what the old
        // bespoke reveal existed for. Nothing here is Shelf-specific — a shelved
        // action's verbs, its Pin/Unpin item, and its cap hint are resolved exactly as
        // the same action's are in the Result list, because they run through the same
        // modifier. The system's own long press opens it, so there is no gesture to
        // hand-roll and no risk of a hold also running the action: the menu
        // interaction cancels the button's touch, as it does for every result row.
        .resultContextMenu(
            title: action.title,
            secondaryActions: secondaryActions(for: action.content, includeDeeplink: !action.isSilentQueryCapture),
            onSecondaryAction: { onSecondaryAction(action, $0) },
            isFavorite: isFavorite(action),
            pinnable: action.isFavoriteEligible,
            canPin: canFavorite(action),
            toggle: { onToggleFavorite(action) }
        ) {
            // The lifted preview: the pressed circle itself, so the button detaches
            // as the round card it is rather than a squared-off snapshot of it.
            glyphCircle(for: action)
        }
        // The label is an `Image`, so without this the button would announce its SF
        // Symbol name (or nothing) to VoiceOver.
        .accessibilityLabel(action.title)
        // The action's own id, **prefixed**: a shelved action has vacated the bottom
        // fallback region, so a test asserting it is gone from there must not be
        // answered by its Shelf button wearing the same identifier.
        .accessibilityIdentifier("shelf.\(action.id)")
    }

    /// The button's face — and its lifted preview: the action's glyph on a circle of
    /// glass tinted by its hue.
    ///
    /// The tint comes from `resolvedActionTint` — the same rule the leading badge
    /// resolves, so a shelved action is recognisable as itself: a user-chosen
    /// [[Action color]] token (issue #243) if it has one, otherwise the
    /// provider-kind-derived hue. It is the *unmodified* hue held back by
    /// `tintStrength`, not a separately-tuned one, so the two surfaces can't drift.
    /// A Custom Action's chosen glyph (issue #163) overrides the kind's symbol,
    /// exactly as it does in a result row.
    private func glyphCircle(for action: Action) -> some View {
        Image(systemName: action.glyph ?? action.kind.symbol)
            // Scaled from the diameter rather than a text style: the button itself is
            // sized by the peek rule, so a fixed glyph would swim in a wide row and
            // crowd a shrunk one.
            .font(.system(size: diameter * 0.4, weight: .semibold))
            // `.primary`, not the badge's white: white reads on a saturated badge, but
            // over a *held-back* tint on a pale backdrop it washes out. `.primary`
            // follows the theme, so the glyph stays legible in both — the same reason
            // the paste chip, the other circle on this bar, draws its icon this way.
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .glassEffect(
                .regular.tint(resolvedActionTint(kind: action.kind, color: action.color)
                    .opacity(Self.tintStrength)).interactive(),
                in: Circle()
            )
            .contentShape(Circle())
    }
}
