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
/// Because the buttons are icon-only, a **long press reveals the action's title** — the
/// agreed disambiguation affordance for a glyph with no label (a design prototype
/// settled icon-only circles over icon+label pills: labels don't fit four across at
/// readable sizes). The title floats *over* the content above rather than pushing the
/// row down, so revealing it never reflows the input or the result list.
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

    /// The row's own width, measured — the input to the peek sizing. Zero until the
    /// first layout pass, which Core reads as "unmeasured" and answers with the
    /// preferred diameter.
    @State private var rowWidth: CGFloat = 0
    /// The member whose title a long press is currently revealing, if any.
    @State private var revealedID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat {
        Self.layout.diameter(availableWidth: rowWidth, memberCount: members.count)
    }

    /// The revealed title, resolved from the live members so a shelf edit (or a member
    /// losing eligibility) can't leave a stale label floating.
    private var revealedTitle: String? {
        members.first { $0.id == revealedID }?.title
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
        .overlay(alignment: .top) { revealedTitleLabel }
        // Both the curve and the dwell come from Core's budget (ADR 0034), never a
        // hand-picked animation or a hand-rolled timer: `MotionStyle.animation` is what
        // degrades the fade for Reduce Motion and drops it entirely under UI test
        // (issue #79), exactly as every other animated surface degrades.
        .animation(motion.style(for: .shelfTitleReveal).animation, value: revealedID)
        // Hold the reveal long enough to read a title, then let it go on its own —
        // there is nothing to dismiss it with, and no menu to escape from. Under UI
        // test the dwell is `nil` and the reveal is held instead (see
        // `shelfTitleDwellUnlessHeld`), so the assertion is not racing a timer.
        .task(id: revealedID) {
            guard revealedID != nil, let dwell = motion.shelfTitleDwellUnlessHeld else { return }
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            revealedID = nil
        }
    }

    private var motion: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

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

    /// One Shelf member: its glyph on a circle of glass tinted by the action's hue.
    ///
    /// The tint comes from `resolvedActionTint` — the same rule the leading badge
    /// resolves, so a shelved action is recognisable as itself: a user-chosen
    /// [[Action color]] token (issue #243) if it has one, otherwise the
    /// provider-kind-derived hue. It is the *unmodified* hue held back by
    /// `tintStrength`, not a separately-tuned one, so the two surfaces can't drift.
    /// A Custom Action's chosen glyph (issue #163) overrides the kind's symbol,
    /// exactly as it does in a result row.
    private func button(for action: Action) -> some View {
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
            // **Exclusive**, not simultaneous, and not a `Button` carrying a long press
            // beside it: a SwiftUI button fires on touch-up however long the touch was
            // held, so a reveal would run the action the moment the finger lifted — the
            // exact outcome the affordance exists to prevent, since the whole point of
            // reading the title is to discover this *isn't* the button you wanted.
            // `ExclusiveGesture` makes the long press win once it recognizes, and a
            // short press fails it so the tap runs as normal.
            .gesture(
                ExclusiveGesture(
                    // The system's own long-press threshold, not a tuned one: holding
                    // to see what something is should take exactly as long here as it
                    // does everywhere else on the platform.
                    LongPressGesture().onEnded { _ in revealedID = action.id },
                    TapGesture().onEnded { run(action) }
                )
            )
            // Hand-rolled tap handling means hand-rolled semantics: without these the
            // row would be a picture, unreachable to VoiceOver and to `app.buttons` in
            // the UI suite.
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(action.title)
            .accessibilityAction { run(action) }
            // The action's own id, **prefixed**: a shelved action has vacated the bottom
            // fallback region, so a test asserting it is gone from there must not be
            // answered by its Shelf button wearing the same identifier.
            .accessibilityIdentifier("shelf.\(action.id)")
    }

    /// Seeds-and-commits the query as `action`'s first Argument, resolving any revealed
    /// title along the way — whatever the long press was disambiguating has been decided.
    private func run(_ action: Action) {
        revealedID = nil
        onRun(action)
    }

    /// The long-press disclosure: the action's title on a small glass capsule floating
    /// above the row. An `overlay` with a top alignment guide, so it takes no layout
    /// space — revealing a title must not shove the input (and the whole result list)
    /// down by a line.
    ///
    /// It is centred over the row rather than pinned under the pressed button: only one
    /// title is ever revealed, the pressed button is visibly pressed, and anchoring to a
    /// button inside a scroll view would put the label at the mercy of the scroll offset
    /// and the row's own clipping.
    @ViewBuilder
    private var revealedTitleLabel: some View {
        if let revealedTitle {
            Text(revealedTitle)
                .font(.footnote.weight(.medium))
                .fontDesign(.rounded)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: Capsule())
                .accessibilityIdentifier("shelf-title")
                // A label, not a control: it must never absorb a tap meant for the
                // button underneath it or the result row behind it.
                .allowsHitTesting(false)
                .transition(.opacity)
                // Sit the capsule's *bottom* a little above the row's top edge.
                .alignmentGuide(.top) { $0[.bottom] + 8 }
        }
    }
}
