import Foundation

/// The **Shelf** as the user meets it in the launcher (CONTEXT.md → Shelf; ADR 0037;
/// issue #242): the horizontal, scrollable row of circular, icon-only Liquid Glass
/// buttons above the input, one per shelved [[Fallback Action]], most-important-first
/// from the leading edge. *Membership* is `FallbackTiers`' job; this owns the two pure
/// decisions the row itself makes — when it renders at all, and how wide a button is —
/// so both are exercised by `swift test` rather than only by the eye.
///
/// Nothing here knows about SwiftUI: the App reads `isVisible(for:)` to decide whether
/// to build the row and `Layout.diameter(availableWidth:memberCount:)` to size it.
public enum FallbackShelf {
    /// The query a Shelf button **seeds-and-commits** as the action's first Argument,
    /// or `nil` when there is nothing to seed.
    ///
    /// The same rule the bottom fallback region's rows run on, deliberately shared:
    /// a Shelf button and a fallback row are the same gesture on two surfaces, so they
    /// must agree on what counts as a seed. Whitespace decides *whether* there is one,
    /// never what it is — the seed is the query verbatim, because the capture's title
    /// step should receive exactly what was typed.
    public static func seed(from query: String) -> String? {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query
    }

    /// Whether the Shelf renders. It means "ways to use *this* query", so an empty
    /// (or whitespace-only) query hides it entirely — an empty capture is started from
    /// the result list or Home, never here.
    ///
    /// Defined as "there is a seed" rather than as its own emptiness check: that is
    /// what makes it impossible for the row to offer a button whose tap would open an
    /// empty breadcrumb instead of committing the query.
    public static func isVisible(for query: String) -> Bool { seed(from: query) != nil }

    /// How wide a Shelf button is, given the row's width and how many members it holds.
    ///
    /// The row has **no member cap and no overflow menu** — it scrolls — so it needs a
    /// sizing cue that says so. That cue is the *peek*: when the members run past the
    /// trailing edge, the next button is deliberately left cut by it (the iOS share
    /// sheet's app-row idiom) rather than landing at whatever offset a fixed button
    /// size happens to produce, which can leave a 3pt sliver or a whole button flush
    /// against the edge — both of which read as "that's all of them".
    public struct Layout: Equatable, Sendable {
        /// The size a button renders at whenever the row fits — the input bar's own
        /// height, so the Shelf reads as part of the bottom glass body.
        public let preferredDiameter: CGFloat
        /// The floor a shrunk button stops at: below this the circle stops being a
        /// comfortable tap target, and it is better to let the row scroll further.
        public let minimumDiameter: CGFloat
        /// The gap between two buttons.
        public let spacing: CGFloat
        /// The row's content inset, applied to **both** edges — where the most
        /// important member starts, and the breathing room the last one keeps.
        public let contentInset: CGFloat
        /// How much of the next button is left showing past the trailing edge, as a
        /// fraction of its diameter. Half a button is unmistakably "cut off".
        public let peek: CGFloat

        public init(
            preferredDiameter: CGFloat,
            minimumDiameter: CGFloat,
            spacing: CGFloat,
            contentInset: CGFloat,
            peek: CGFloat
        ) {
            self.preferredDiameter = preferredDiameter
            self.minimumDiameter = minimumDiameter
            self.spacing = spacing
            self.contentInset = contentInset
            self.peek = peek
        }

        /// **The** metrics the launcher's Shelf renders with. It lives here rather than
        /// beside the view so the sizing rule is tested against the numbers that ship,
        /// instead of a hand-copied twin in the test that nothing keeps in step.
        ///
        /// Only `preferredDiameter` is the caller's: the bar's height is App chrome
        /// (`InputBar.barHeight`), and matching it is what makes the Shelf read as part
        /// of the bottom glass body rather than a foreign strip above it. Everything
        /// else is this rule's own — a minimum that holds the HIG's comfortable tap
        /// target rather than shrinking past it, the same 8pt the bar's glass surfaces
        /// sit apart, the same 12pt inset the bar's contents keep, and a half-button
        /// peek, which is unmistakably "cut off" where a thinner sliver reads as a
        /// rendering slip.
        public static func launcher(preferredDiameter: CGFloat) -> Layout {
            Layout(
                preferredDiameter: preferredDiameter,
                minimumDiameter: 44,
                spacing: 8,
                contentInset: 12,
                peek: 0.5
            )
        }

        /// The diameter every button in the row renders at, in three cases:
        ///
        /// 1. **They fit.** Nothing to signal — the preferred diameter, and the row
        ///    doesn't scroll.
        /// 2. **They overflow, and a peek is reachable.** Shrink so that `k` whole
        ///    buttons plus `peek` of the next exactly span the row, picking the `k`
        ///    that keeps the buttons as large as possible without exceeding the
        ///    preferred diameter. `k` is a property of the *width*, not of the member
        ///    count, so a twenty-member Shelf looks like a seven-member one and simply
        ///    scrolls further.
        /// 3. **They overflow by less than a peek.** No `k` yields a small enough
        ///    button (peeking would need *bigger* ones), so shrink just enough that
        ///    every member is whole *and the row stops scrolling* — an honest "that's
        ///    all of them" beats a 4pt shave off the last button. Both insets come out
        ///    of the width here for the same reason they do in the fit check: the row
        ///    is only settled if the laid-out content, padding included, fits inside it.
        ///
        /// An unmeasured row (`availableWidth` 0, the first frame) or an empty one
        /// takes the preferred diameter; the result never drops below the minimum.
        public func diameter(availableWidth: CGFloat, memberCount: Int) -> CGFloat {
            guard memberCount > 0, availableWidth > 0 else { return preferredDiameter }
            guard width(of: memberCount, at: preferredDiameter) > availableWidth else {
                return preferredDiameter
            }
            // `peeked` strictly shrinks as `k` grows (more buttons, less room each), so
            // the first `k` that comes in under the preferred diameter is the largest
            // button that can carry a peek.
            for whole in 1..<memberCount {
                let candidate = peeked(whole: whole, availableWidth: availableWidth)
                if candidate <= preferredDiameter { return max(candidate, minimumDiameter) }
            }
            let shrunkToFit =
                (availableWidth - 2 * contentInset - CGFloat(memberCount - 1) * spacing)
                / CGFloat(memberCount)
            return max(shrunkToFit, minimumDiameter)
        }

        /// The width `count` whole buttons occupy at `diameter`, insets included — what
        /// the row actually lays out, which is why **both** insets are counted. Reserving
        /// only the leading one would call a row settled while its trailing padding
        /// pushed the content a few points past the viewport: a row that scrolls by a
        /// hair, showing the shaved sliver the peek sizing exists to avoid.
        private func width(of count: Int, at diameter: CGFloat) -> CGFloat {
            2 * contentInset + CGFloat(count) * diameter + CGFloat(count - 1) * spacing
        }

        /// The diameter at which `whole` buttons plus a `peek` of the next one exactly
        /// span the row: `contentInset + whole × (d + spacing) + peek × d == width`.
        private func peeked(whole: Int, availableWidth: CGFloat) -> CGFloat {
            (availableWidth - contentInset - CGFloat(whole) * spacing) / (CGFloat(whole) + peek)
        }
    }
}
