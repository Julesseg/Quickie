import Foundation

/// Which of the [[Result list]]'s three structural regions a row rides (CONTEXT.md
/// → Result list; ADR 0008, ADR 0015), decided by **how** the row earned its place
/// rather than which Provider it came from:
///
/// - `boosted` — a type-triggered [[Computed]] hit that floats to the top unscored
///   (a math result, a detected value): the Provider already decided it applies, so
///   it was never name-matched.
/// - `ranked` — a name-scored survivor blended by the user's signals: an Indexed
///   catalog entry *or* a ranked-dynamic File Search hit. These are the only rows
///   whose presence was decided by a name match, so these are the only rows the
///   **Match highlight** ever bolds.
/// - `fallback` — pinned to the bottom region, consuming the typed query rather than
///   being found by name (CONTEXT.md → Fallback list).
///
/// The region is what the app's seed-and-commit decision keys off (a `.fallback`
/// tap seeds-and-commits the query; anything else opens verb-first), so it is
/// carried on the row rather than re-derived from "is this an enabled fallback?".
public enum ResultRegion: Equatable, Sendable {
    case boosted
    case ranked
    case fallback
}

/// How a name-matched row explains **why** it surfaced — the **Match highlight**
/// (CONTEXT.md → Match highlight; issue #195): the letters of the query that found
/// their place in the row's name render bold. Present only on `ranked` rows, whose
/// presence a name match decided; a boosted, fallback, or Home row carries none.
public struct MatchHighlight: Equatable, Sendable {
    /// Which of an Action's names — its title or one of its aliases — won the match
    /// that surfaced the row. Groundwork for the **single-source rule**: the title
    /// bolds only when it was the winning candidate; when an alias outscored it
    /// (including a hidden alias like a built-in command's or a Pile entry's
    /// body-as-alias) the title stays plain and the alias-pill ticket adds the
    /// pill-side bolding.
    public enum Candidate: Equatable, Sendable {
        case title
        /// The winning alias, by its index into `Action.aliases`.
        case alias(Int)
    }

    /// The name that won the match — the single source the bolding attributes to.
    public let winningCandidate: Candidate

    /// Character offsets into `Action.title` to bold, ascending — the query letters
    /// that found their place in the title. Empty when an alias outscored the title
    /// (the single-source rule: a non-winning title stays fully plain).
    public let titleBold: [Int]

    /// Character offsets into the **winning alias** to bold, ascending — the query
    /// letters that found their place there (CONTEXT.md → Alias pill; issue #196).
    /// Non-empty only when an alias was the strict match winner; empty when the title
    /// won or tied (the single-source rule, mirrored: a non-winning alias's pill stays
    /// dim). The offsets index the alias `winningCandidate` names, which for an
    /// alias-pill-bearing Action is its sole alias — the one the pill renders — so the
    /// view bolds the pill with exactly these.
    public let aliasBold: [Int]

    public init(winningCandidate: Candidate, titleBold: [Int], aliasBold: [Int] = []) {
        self.winningCandidate = winningCandidate
        self.titleBold = titleBold
        self.aliasBold = aliasBold
    }

    /// The bold offsets for the [[Alias pill]] showing `pill` — the pill-side of the
    /// **single-source rule**, resolved here rather than in the view so the
    /// winner↔pill correlation lives next to the spans it gates (CONTEXT.md → Alias
    /// pill; issue #196). Returns `aliasBold` only when an alias was the match winner
    /// *and* it is the very alias the pill renders (`aliases[index] == pill`); empty
    /// when the title won, or when some other alias won than the one shown. `aliases`
    /// is the rendered Action's `aliases`, the array `winningCandidate`'s index points
    /// into — for a pill-bearing Action that is its sole alias, so the guard is exact.
    public func pillBold(for pill: String, aliases: [String]) -> [Int] {
        guard case .alias(let index) = winningCandidate,
              aliases.indices.contains(index),
              aliases[index] == pill else { return [] }
        return aliasBold
    }

    /// The highlight for a row whose **title** is the matched candidate — the common
    /// case, and the only shape a file row (which has no aliases) can take. Bolds the
    /// query letters that found their place in the title, or returns `nil` when the
    /// query doesn't match it at all. The one builder the inline File Search rows and
    /// the Search Files context share, so a file bolds identically on both surfaces.
    public static func titleMatch(
        query: String,
        title: String,
        layout: KeyboardLayout = .qwerty
    ) -> MatchHighlight? {
        guard let offsets = Matcher.matchOffsets(query: query, candidate: title, layout: layout) else {
            return nil
        }
        return MatchHighlight(winningCandidate: .title, titleBold: offsets)
    }
}

/// A single row of the [[Result list]] — the Action plus **why** it is here: its
/// `region` (how it earned its place) and its optional Match highlight (which title
/// letters to bold). The engine's `rows(for:)` returns these; the flat
/// `results(for:)` is the `action`-only projection over the same list, so the two
/// can never drift.
public struct ResultRow: Identifiable, Sendable {
    public let action: Action
    public let region: ResultRegion
    /// The Match highlight, present only on a name-matched (`ranked`) row; `nil` on a
    /// boosted or fallback row, which never bold.
    public let match: MatchHighlight?

    public var id: String { action.id }

    public init(action: Action, region: ResultRegion, match: MatchHighlight? = nil) {
        self.action = action
        self.region = region
        self.match = match
    }
}
