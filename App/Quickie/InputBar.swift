import SwiftUI
import UIKit
import QuickieCore

/// The single bottom input field — the one surface the whole app is built
/// around. It auto-focuses on launch (the binding is driven by `RootView`),
/// sits above the keyboard, and is a native Liquid Glass capsule over the quiet
/// backdrop (ADR 0010): no hand-rolled blur, so the material matches the system.
///
/// Its Return key carries the highlighted result's Enter intent (CONTEXT.md →
/// Highlighted result): the submit label maps to that row's closest system label
/// (`.search` for a web query, `.go` for a link) and pressing Return runs exactly
/// that row's main action. On Home (empty query) there is no highlight and submit
/// is a no-op.
///
/// A trailing [[Clear button]] rides *inside* the same glass capsule — one
/// surface, not a second one beside it (the paste chip is the only bottom
/// surface that gets its own glass, because it morphs in and out of this one).
struct InputBar: View {
    /// Stable identity for the input's Liquid Glass within the bottom
    /// `GlassEffectContainer`. Pairing it with the paste button's id in a shared
    /// namespace is what lets the button morph *out of and back into* this capsule
    /// as it is offered and withdrawn (see `ClipboardPasteButton`, `RootView`).
    static let glassID = "input-bar"

    /// The bottom row's height. Fixed (rather than padding-derived) so the paste
    /// button can be an exactly-matching circle beside it — see `ClipboardPasteButton`.
    static let barHeight: CGFloat = 52

    /// HIG's minimum tap target. The clear button's *glyph* is text-sized, but its
    /// target is this — the same floor the rest of the bottom row meets (the paste
    /// chip is a full `barHeight` circle).
    private static let minTapTarget: CGFloat = 44

    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    /// The field's placeholder — the neutral "Type to search…" by default, or a
    /// scoped prompt like "Search files…" inside the Search Files context (ADR 0014).
    var placeholder: String = "Type to search…"
    /// The highlighted result's Return-key label, or `.none` on Home.
    var returnKey: ReturnKeyLabel = .none
    /// Runs the highlighted result's main action; a no-op when there is none.
    var onSubmit: () -> Void = {}
    /// The shared namespace the bottom glass surfaces morph within.
    var glassNamespace: Namespace.ID

    /// Whether the glass surface is *currently* the squared-off box (issue #80). Held
    /// as state, not derived, because the wrap decision is hysteretic: it depends on
    /// the prior shape so a jittery measurement at the boundary can't flip-flop it
    /// (see `InputBarGrowth.isExpanded`). Recomputed only when the measured height
    /// changes.
    @State private var isExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The grow-and-wrap policy (issue #63): whether the surface is a Capsule or the
    /// squared-off box, and the box's corner radius. Pure and unit-tested in Core.
    private let growth = InputBarGrowth(barHeight: InputBar.barHeight)

    /// One line-height for the field's font — the yardstick the measured content
    /// height is compared against. Taken from the resolved `UIFont` so no hidden
    /// measuring view is needed.
    private var lineHeight: CGFloat { UIFont.preferredFont(forTextStyle: .title3).lineHeight }

    /// The row's own vertical padding — what keeps one line centred in `barHeight`.
    private var rowPadding: CGFloat { max(0, (Self.barHeight - lineHeight) / 2) }

    /// How far the clear button's *hit area* spills above and below its layout box.
    /// Its box is capped at one line-height (it must never be the tallest thing in
    /// the row, or the bar grows past `barHeight`), which at default Dynamic Type
    /// leaves the target well short of `minTapTarget` — so the missing height is
    /// taken back as hit area alone. Bounded by `rowPadding`, the space the target
    /// spills into, so it stays *inside* the glass capsule rather than reaching past
    /// its edge; at large Dynamic Type the line itself clears the floor and this is 0.
    private var hitSlop: CGFloat {
        min(max(0, (Self.minTapTarget - lineHeight) / 2), rowPadding)
    }

    /// The Liquid Glass surface: a Capsule on one line, a RoundedRectangle whose
    /// ends stay as round as the capsule's once the text wraps.
    private var glassShape: AnyShape {
        isExpanded
            ? AnyShape(RoundedRectangle(cornerRadius: growth.cornerRadius, style: .continuous))
            : AnyShape(Capsule())
    }

    /// Whether the trailing clear button is offered — only when there is something
    /// to clear. Derived, never stored: the query *is* the state, so the button
    /// can't drift out of step with the text beside it.
    private var showsClear: Bool { !query.isEmpty }

    /// The clear button's come-and-go, from Core's budget (ADR 0010). It borrows
    /// `.inputFocus` — the snappiest moment, the one closest to a keystroke —
    /// because that is exactly what this is: the input's own furniture reacting to
    /// the first and last character typed, so it must never lag the typing.
    private var clearMotion: MotionStyle {
        MotionPolicy(reduceMotion: reduceMotion).style(for: .inputFocus)
    }

    var body: some View {
        // Bottom-aligned so a wrapped field keeps the clear button on the *last*
        // line, beside the insertion point, rather than floating up with the box.
        HStack(alignment: .bottom, spacing: 4) {
            field
            if showsClear { clearButton }
        }
        .padding(.leading, 20)
        // Tuck the 44pt-wide button in tight: that lands its glyph on the centre of
        // the capsule's round end, where an icon reads best — the text's 20 would
        // push it off-centre and just look like a gap.
        .padding(.trailing, showsClear ? 4 : 20)
        // Keep the one-line vertical centring identical to the old fixed-height
        // capsule, and give each wrapped line the same breathing room.
        .padding(.vertical, rowPadding)
        // `minHeight` (not a fixed height) so the box can grow upward past the
        // one-line capsule as lines are added.
        .frame(minHeight: Self.barHeight)
        // The whole capsule is the field. A `TextField(axis: .vertical)` only
        // hit-tests around its *text*, not across its layout width — invisible on a
        // narrow iPhone, where a one-character query still leaves the centre within
        // reach of the glyphs, and plainly wrong on an iPad, where the bar is wide
        // enough that a tap in the empty space beside "s" landed on nothing at all
        // and the keyboard never came back (found by the iPad CI leg, ADR 0038).
        // A backing shape catches exactly those taps: it sits *behind* the row, so
        // the text view still takes the ones over the text (placing a caret) and the
        // clear button still takes its own — only what neither wanted falls through
        // to here, which is the definition of "empty space in the bar".
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { focused.wrappedValue = true }
        }
        // Scoped to the offer flipping, so the button's arrival/exit and the width
        // the field gives up for it are one gesture — and every other change here
        // (a keystroke, a wrap) still applies instantly.
        .animation(clearMotion.animation, value: showsClear)
        .glassEffect(.regular.interactive(), in: glassShape)
        .glassEffectID(Self.glassID, in: glassNamespace)
    }

    /// The trailing clear affordance: one tap empties the query and leaves the
    /// keyboard up. It lives inside the input's own glass — no second surface, no
    /// `glassEffect` of its own — so the row still reads as a single body.
    private var clearButton: some View {
        Button(action: clear) {
            Image(systemName: "xmark.circle.fill")
                // The field's own text style, so the glyph scales with Dynamic Type
                // exactly as `lineHeight` (its layout box, below) does.
                .font(.system(.title3, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                // A full-width tap target, but only one line-height tall: the button
                // must never be the tallest thing in the row, or it would inflate the
                // bar past `barHeight` and break the paste chip's matching circle.
                .frame(width: Self.minTapTarget, height: lineHeight)
                // So the height it can't take in layout, it takes in hit area: pad
                // out to the 44pt floor, claim *that* as the tappable shape, then
                // hand the space straight back so the row's geometry is untouched.
                // The reclaimed strip is the row's own padding — inside the glass —
                // so the target grows into the capsule, never past it.
                .padding(.vertical, hitSlop)
                .contentShape(Rectangle())
                .padding(.vertical, -hitSlop)
        }
        // Plain, so nothing tints or platters the glyph over the glass.
        .buttonStyle(.plain)
        .accessibilityIdentifier("clear-input")
        .accessibilityLabel("Clear text")
        .transition(clearMotion.inPlaceTransition)
    }

    /// The search field itself.
    private var field: some View {
        // `axis: .vertical` is what lets the field wrap and grow instead of scrolling
        // sideways; `lineLimit(1...maxLines)` caps the growth and then scrolls
        // internally. Because the bar is anchored in the bottom safe-area inset, the
        // extra height pushes the *top* edge up while the bottom stays put above the
        // keyboard.
        TextField(placeholder, text: $query, axis: .vertical)
            .textFieldStyle(.plain)
            // Rounded launcher chrome (ADR 0033): the input pairs with the
            // squircle/glass language; a text style (not a fixed size) so it keeps
            // scaling with Dynamic Type.
            .font(.system(.title3, design: .rounded))
            .lineLimit(1...InputBarGrowth.maxLines)
            .focused(focused)
            .submitLabel(returnKey.submitLabel)
            .onSubmit(onSubmit)
            .accessibilityIdentifier("search-input")
            // Autocorrect stays on: the field doubles as a thought-capture surface
            // ("Buy milk"), where system autocorrect helps more than it hurts, and
            // matching is forgiving enough that a corrected query still finds its
            // target.
            // Sentence-case autocapitalization: the keyboard opens shifted so a
            // captured thought ("Buy milk") starts capitalized without a reach for
            // the shift key. Matching is case-insensitive throughout, so a
            // capitalized query never changes what search finds.
            .textInputAutocapitalization(.sentences)
            // On a vertical-axis field the software keyboard's Return key inserts a
            // newline rather than firing `onSubmit`. A *lone trailing* newline is
            // that Return keypress: drop it and run the highlighted result's Enter
            // (CONTEXT.md → Highlighted result). Any other newline content — a
            // programmatic set (clipboard prefill, Pile staging) or a multi-line
            // paste — is left intact so it simply wraps.
            .onChange(of: query) { oldValue, newValue in
                guard newValue == oldValue + "\n" else { return }
                query = oldValue
                onSubmit()
            }
            // Measure the text's natural height (before the min-height frame and the
            // vertical padding) so a single line reads as one line-height and a wrap
            // reads as two — that difference is what flips the shape.
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateHeight(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, height in updateHeight(height) }
                }
            }
    }

    /// Empties the query and keeps the keyboard up: clearing is "start over", not
    /// "done", so the very next keystroke lands in the field the user just emptied.
    /// (Asserting focus is belt-and-braces — the button is inside the same glass as
    /// the field, so a tap here should never have resigned it in the first place.)
    private func clear() {
        query = ""
        focused.wrappedValue = true
    }

    /// Records a fresh content-height measurement and re-derives the glass shape
    /// through the hysteretic wrap decision (issue #80). Feeding the *current*
    /// `isExpanded` back in is what gives the box its dead band: a height wobbling
    /// at the wrap boundary — as a `TextField(axis: .vertical)` reports mid-reflow
    /// under rapid backspace — holds the existing shape instead of flip-flopping it
    /// and firing a burst of Liquid Glass morphs that stalls the main runloop.
    private func updateHeight(_ height: CGFloat) {
        isExpanded = growth.isExpanded(
            contentHeight: height,
            lineHeight: lineHeight,
            wasExpanded: isExpanded
        )
    }
}
