import Foundation

/// Scores how well a typed query matches a candidate name.
///
/// This is the deliberately *naive* placeholder matcher for the walking
/// skeleton (issue #3): a case- and diacritic-insensitive subsequence test
/// with a contiguity/position score. It is the seam where the forgiving,
/// layout-adaptive matcher of ADR 0005 (Damerau-Levenshtein, keyboard
/// adjacency, trigram prefilter) will later drop in — callers depend only on
/// the `score(query:candidate:)` shape, never on how the number is derived.
public enum Matcher {

    /// Returns a score in `(0, 1]` when `query` matches `candidate`, or `nil`
    /// when it does not. Higher is a better match. An empty query never
    /// matches: the empty-query Home state is owned by the SearchEngine, not
    /// the matcher.
    ///
    /// Ordering guarantees the result list relies on:
    /// - an exact name beats a prefix,
    /// - a prefix beats a buried (mid-string) substring,
    /// - a contiguous substring beats a scattered subsequence,
    /// - within a tier, a shorter candidate (tighter fit) scores higher.
    public static func score(query: String, candidate: String) -> Double? {
        let q = normalize(query)
        let c = normalize(candidate)
        guard !q.isEmpty, !c.isEmpty else { return nil }
        guard isSubsequence(q, of: c) else { return nil }

        if q == c { return 1.0 }

        // Contiguity tier: prefix > buried substring > scattered subsequence.
        let base: Double
        if c.hasPrefix(q) {
            base = 0.80
        } else if c.contains(q) {
            base = 0.60
        } else {
            base = 0.40
        }

        // Tie-breaker within a tier: the closer the lengths, the tighter the
        // fit. Capped at 0.15 so it can never lift one tier above the next.
        let lengthBonus = 0.15 * (Double(q.count) / Double(c.count))
        return base + lengthBonus
    }

    /// Case- and diacritic-insensitive folding so "cafe" matches "Café" and
    /// "GITHUB" matches "GitHub".
    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// True when every character of `query` appears in `candidate`, in order.
    private static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        var qi = query.startIndex
        for ch in candidate {
            if qi == query.endIndex { break }
            if ch == query[qi] { qi = query.index(after: qi) }
        }
        return qi == query.endIndex
    }
}
