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
struct InputBar: View {
    /// Stable identity for the input's Liquid Glass within the bottom
    /// `GlassEffectContainer`. Pairing it with the paste button's id in a shared
    /// namespace is what lets the button morph *out of and back into* this capsule
    /// as it is offered and withdrawn (see `ClipboardPasteButton`, `RootView`).
    static let glassID = "input-bar"

    /// The bottom row's height. Fixed (rather than padding-derived) so the paste
    /// button can be an exactly-matching circle beside it — see `ClipboardPasteButton`.
    static let barHeight: CGFloat = 52

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

    /// The grow-and-wrap policy (issue #63): whether the surface is a Capsule or the
    /// squared-off box, and the box's corner radius. Pure and unit-tested in Core.
    private let growth = InputBarGrowth(barHeight: InputBar.barHeight)

    /// One line-height for the field's font — the yardstick the measured content
    /// height is compared against. Taken from the resolved `UIFont` so no hidden
    /// measuring view is needed.
    private var lineHeight: CGFloat { UIFont.preferredFont(forTextStyle: .title3).lineHeight }

    /// The Liquid Glass surface: a Capsule on one line, a RoundedRectangle whose
    /// ends stay as round as the capsule's once the text wraps.
    private var glassShape: AnyShape {
        isExpanded
            ? AnyShape(RoundedRectangle(cornerRadius: growth.cornerRadius, style: .continuous))
            : AnyShape(Capsule())
    }

    var body: some View {
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
            .autocorrectionDisabled()
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
            .padding(.horizontal, 20)
            // Keep the one-line vertical centring identical to the old fixed-height
            // capsule, and give each wrapped line the same breathing room.
            .padding(.vertical, max(0, (Self.barHeight - lineHeight) / 2))
            // `minHeight` (not a fixed height) so the box can grow upward past the
            // one-line capsule as lines are added.
            .frame(minHeight: Self.barHeight)
            .glassEffect(.regular.interactive(), in: glassShape)
            .glassEffectID(Self.glassID, in: glassNamespace)
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
