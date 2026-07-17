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
/// The rotation order is **randomized**, not fixed: a line that always cycled in
/// the same order reads as a canned reel, and the eye learns to tune out its
/// rhythm. But it randomizes as a **shuffle bag**, not by picking each next hint
/// independently — the point of the line is that every capability gets seen, and
/// naive random would let one hint recur while another never showed in a short
/// session. Each pass is a fresh shuffle of all five, so within any five
/// consecutive rotations the user sees every capability exactly once, in an order
/// that changes each pass and never repeats a hint back to back.
///
/// Core owns the copy and the cycling; the App owns only the crossfade between
/// `current` values and asks `MotionPolicy` when to `advance()`.
public struct HintLine: Equatable, Sendable {
    /// The hints — one per capability, deliberately.
    ///
    /// The **first** entry is the one deliberate position left: it is what the
    /// line opens on before any rotation, and the single hint shown when the line
    /// is frozen (Reduce Motion, UI test). Arithmetic in a launcher is the fastest
    /// way to say "this is not a list of apps", so it earns the one guaranteed
    /// slot. After that first hint the order is shuffled (see the type comment),
    /// so the remaining four have no fixed sequence to read into.
    public static let hints: [String] = [
        "Try 2+2",
        "Paste a link",
        "Type an app name",
        "Jot something down",
        "Search the web",
    ]

    /// Which hint the line is showing, as an index into `hints`.
    private var index: Int

    /// The remaining shuffled indices for this pass, popped from the end. Refilled
    /// with a fresh shuffle of all five when it empties — that refill is where the
    /// order is randomized, and where a back-to-back repeat is ruled out.
    private var bag: [Int]

    /// A fresh line, showing the first hint. Also the frozen rendering: under
    /// Reduce Motion or UI test the App builds this and never advances it, so
    /// `hints[0]` has to stand on its own.
    public init() {
        index = 0
        bag = []
    }

    /// The hint on screen now.
    public var current: String { Self.hints[index] }

    /// Moves to the next hint at random, using the system generator. Home can sit
    /// open for as long as the user leaves it open, so the line never runs out:
    /// each exhausted pass reshuffles into the next.
    public mutating func advance() {
        var generator = SystemRandomNumberGenerator()
        advance(using: &generator)
    }

    /// `advance()` with an injected generator, so a test can drive the rotation
    /// deterministically.
    public mutating func advance<G: RandomNumberGenerator>(using generator: inout G) {
        // A single-hint line (were the list ever trimmed to one) has nowhere to
        // go; leave it where it is rather than reshuffle a bag of one forever.
        guard Self.hints.count > 1 else { return }
        if bag.isEmpty {
            refill(using: &generator)
        }
        index = bag.removeLast()
    }

    /// Fills `bag` with a fresh shuffle of every index, arranged so the *next*
    /// hint popped is never the one on screen now — the seam between two passes is
    /// the only place a plain shuffle could repeat a hint, and a repeat there
    /// would read as the crossfade stuttering on nothing.
    private mutating func refill<G: RandomNumberGenerator>(using generator: inout G) {
        var shuffled = Array(Self.hints.indices).shuffled(using: &generator)
        // The end of the array is popped first. If that would replay `index`, swap
        // it to the front (which is popped last, by which point the screen has
        // moved on). Safe because there is always more than one index here.
        if shuffled.last == index {
            shuffled.swapAt(shuffled.count - 1, 0)
        }
        bag = shuffled
    }
}
