import Foundation

/// The Home **Hint line** (ADR 0034): five quiet, instructive examples shown
/// under the brand mark on the pre-anything Home, rotating slowly so the app
/// teaches its own breadth by suggestion.
///
/// It exists because ADR 0012 rules out the usual way to say what a launcher
/// accepts — there is no first-run wall, no tour, no empty-state paragraph. A
/// user who only ever learns that Quickie opens apps has an app launcher, not
/// Quickie. The line is the whole onboarding, so it is **one capability per
/// hint** (arithmetic, links, apps, capture, the web) rather than five phrasings
/// of one trick — that invariant is what `HintLineTests` guards, and it is the
/// reason the copy lives in Core next to the capabilities it advertises rather
/// than as loose strings in a view.
///
/// It only ever *suggests*: each hint is an example the user could type, never
/// an instruction or a call to action. The placeholder still says what to do
/// ("Start typing"); the hint says what is worth typing, and is a separate
/// element precisely so the two never blur into one changing sentence.
///
/// Core owns the copy and the cycling; the App owns only the crossfade between
/// `current` values and asks `MotionPolicy` when to `advance()`.
public struct HintLine: Equatable, Sendable {
    /// The hints, in rotation order — one per capability, deliberately.
    ///
    /// Ordered to open on the least expected: arithmetic in a launcher is the
    /// fastest way to say "this is not a list of apps", and the app-name hint —
    /// the one thing a user would already assume — sits in the middle where it
    /// reads as one capability among several rather than as the headline.
    public static let hints: [String] = [
        "Try 2+2",
        "Paste a link",
        "Type an app name",
        "Jot something down",
        "Search the web",
    ]

    /// Which hint the line is showing, as an index into `hints`.
    private var index: Int

    /// A fresh line, showing the first hint. Also the frozen rendering: under
    /// Reduce Motion or UI test the App builds this and never advances it, so
    /// `hints[0]` has to stand on its own.
    public init() {
        index = 0
    }

    /// The hint on screen now.
    public var current: String { Self.hints[index] }

    /// Moves to the next hint, wrapping at the end. Home can sit open for as
    /// long as the user leaves it open, so the line cycles rather than running
    /// out and stranding whichever hint happened to be last.
    public mutating func advance() {
        index = (index + 1) % Self.hints.count
    }
}
