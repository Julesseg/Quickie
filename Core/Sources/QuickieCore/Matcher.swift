import Foundation

/// Scores how well a typed query matches a candidate name — the forgiving,
/// layout-adaptive matcher of ADR 0005, tuned for fat-fingered phone typing.
///
/// It layers, cheapest signal first:
/// 1. **Normalization** — lowercase + diacritic folding (`cafe` ↔ `café`), and
///    token-order independence so `"github open"` hits `"Open GitHub"`.
/// 2. **Subsequence tier** (`0.40 … 1.0`) — fzf-style scoring rewarding exact
///    names, prefixes, contiguous runs, and tight fits.
/// 3. **Forgiving tier** (`0 … <0.40`) — a Damerau-Levenshtein pass within a
///    length-scaled edit budget (~1 slip per 4 chars) catches transpositions
///    and single-character slips, adjacency-weighted so physically plausible
///    slips rank higher. Always below any clean subsequence match.
/// 4. **Trigram prefilter** — a cheap, sound gate that skips the edit-distance
///    pass for hopeless candidates so it scales over a large index.
///
/// Keyboard adjacency is layout-adaptive: callers pass the active
/// `KeyboardLayout` (resolved from the keyboard's language in the App layer);
/// the Core stays platform-agnostic and defaults to QWERTY. Callers depend only
/// on the `score` shape, never on how the number is derived.
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
    public static func score(
        query: String,
        candidate: String,
        layout: KeyboardLayout = .qwerty
    ) -> Double? {
        let q = normalize(query)
        let c = normalize(candidate)
        guard !q.isEmpty, !c.isEmpty else { return nil }

        // Score the query whole — the common single-token path, and the one
        // that lets a multi-word query match the candidate's words in order.
        let whole = matchScore(q, c, layout: layout)

        // Token-order independence: a multi-word query also matches when each
        // word lands somewhere in the candidate, in any order ("github open" →
        // "Open GitHub"). Take whichever reading scores better so the in-order
        // reading is never penalised.
        let tokens = q.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count > 1 else { return whole }

        return [whole, tokenOrderScore(tokens, c, layout: layout)]
            .compactMap { $0 }
            .max()
    }

    /// One token (or a whole single-word query) against the candidate: a clean
    /// subsequence if it is one, otherwise the forgiving Damerau-Levenshtein
    /// tier, which always scores below any subsequence match. Inputs are
    /// already normalized.
    private static func matchScore(_ q: String, _ c: String, layout: KeyboardLayout) -> Double? {
        if isSubsequence(q, of: c) {
            return subsequenceScore(q, c)
        }
        return fuzzyScore(q, c, layout: layout)
    }

    /// Combined score when every query token finds its own match in the
    /// candidate, regardless of order. `nil` if any token fails to match — a
    /// query is only satisfied when all of its words are present. The mean of
    /// the per-token scores keeps the result in the same range as a whole-query
    /// match.
    private static func tokenOrderScore(_ tokens: [String], _ c: String, layout: KeyboardLayout) -> Double? {
        var total = 0.0
        for token in tokens {
            guard let s = matchScore(token, c, layout: layout) else { return nil }
            total += s
        }
        return total / Double(tokens.count)
    }

    // MARK: - Subsequence tier (0.40 … 1.0)

    /// Score for a query whose letters all appear, in order, in the candidate.
    private static func subsequenceScore(_ q: String, _ c: String) -> Double {
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

    // MARK: - Forgiving (Damerau-Levenshtein) tier (0 … <0.40)

    /// Ceiling for the fuzzy tier, held strictly below the scattered-subsequence
    /// base (0.40) so a real subsequence always wins.
    private static let fuzzyCeiling = 0.35

    /// The cheapest single edit: a substitution onto a physically adjacent key.
    private static let minEditCost = 0.5

    /// How many edit *operations* a query of this length may be from a window of
    /// the candidate and still count as a typo rather than a different word —
    /// roughly one slip per four characters. Returns `0` for very short queries
    /// (1–3 chars), which gates the fuzzy tier off for them entirely: a 2–3 char
    /// query that isn't a subsequence is two edits from *some* window of almost
    /// anything, so fuzzy-matching it would drag in the whole index.
    private static func maxEdits(forQueryLength length: Int) -> Int {
        length / 4
    }

    /// Scores `q` against `c` via the forgiving tier. The gate is the *true*
    /// (unit-cost) edit distance: at most `maxEdits` operations, where an
    /// adjacency slip still counts as one edit. Adjacency weighting then only
    /// ranks the survivors — a physically plausible slip scores higher than a
    /// distant one. The trigram prefilter screens hopeless candidates first.
    private static func fuzzyScore(_ q: String, _ c: String, layout: KeyboardLayout) -> Double? {
        let budget = maxEdits(forQueryLength: q.count)
        guard budget > 0, passesTrigramPrefilter(q, c) else { return nil }

        // Gate on the number of edits (unit cost), so an adjacency discount can
        // never smuggle in extra operations past the budget.
        guard let edits = bestEditCost(query: q, candidate: c, substitution: { _, _ in 1.0 }),
              edits <= Double(budget) else { return nil }

        // Rank by the adjacency-weighted cost: adjacent-key slips cost less.
        let weighted = bestEditCost(query: q, candidate: c) { typed, intended in
            substitutionCost(typed, intended, layout: layout)
        } ?? edits

        // Monotonic in cost: cheaper typo → higher score, always < 0.40.
        let span = Double(budget) + 1
        return fuzzyCeiling * (span - weighted) / span
    }

    // MARK: - Trigram prefilter

    /// A cheap necessary-condition gate run before the expensive edit-distance
    /// pass, so the SearchEngine can skip candidates that can't be a near-typo
    /// of the query over a large index (ADR 0005). It is **sound**: it never
    /// rejects a candidate the full matcher would accept.
    ///
    /// Each edit alters at most three trigrams, so a candidate within the
    /// query's length-scaled edit budget (`maxEdits` operations) shares at least
    /// `qTrigrams - 3·maxEdits` of the query's trigrams. We demand that many.
    /// When the query is too short to form that many trigrams the bound goes
    /// non-positive and the gate passes everything — it can't soundly reject, so
    /// it defers to the full matcher. Because the budget grows slower than the
    /// query (one edit per four chars), the gate becomes selective at everyday
    /// query lengths, not only very long ones.
    static func passesTrigramPrefilter(_ query: String, _ candidate: String) -> Bool {
        let normalized = normalize(query)
        let queryGrams = trigrams(normalized)
        guard !queryGrams.isEmpty else { return true }

        let needed = queryGrams.count - 3 * maxEdits(forQueryLength: normalized.count)
        guard needed > 0 else { return true }

        let shared = queryGrams.intersection(trigrams(normalize(candidate))).count
        return shared >= needed
    }

    /// The set of 3-character windows of `s` (empty when `s` is shorter than 3).
    private static func trigrams(_ s: String) -> Set<String> {
        let chars = Array(s)
        guard chars.count >= 3 else { return [] }
        var grams = Set<String>(minimumCapacity: chars.count - 2)
        for i in 0...(chars.count - 3) {
            grams.insert(String(chars[i ..< i + 3]))
        }
        return grams
    }

    /// Cheapest weighted Damerau-Levenshtein distance from `query` to the
    /// candidate, allowing the match to start and end anywhere inside the
    /// candidate (so "gthub" matches deep inside "Open GitHub"): the first row
    /// is zero-cost (free leading skip) and the answer is the minimum over the
    /// last row (free trailing skip).
    private static func bestEditCost(
        query: String,
        candidate: String,
        substitution: (Character, Character) -> Double
    ) -> Double? {
        let a = Array(query)
        let b = Array(candidate)
        guard !a.isEmpty, !b.isEmpty else { return nil }
        let n = a.count, m = b.count

        // d[i][j] = cost to transform a[0..<i] into some b[k..<j].
        var d = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = Double(i) }      // deleting query chars
        for j in 0...m { d[0][j] = 0.0 }            // free leading skip in candidate

        for i in 1...n {
            for j in 1...m {
                let match = a[i - 1] == b[j - 1]
                let subCost = match ? 0.0 : substitution(a[i - 1], b[j - 1])
                var best = min(
                    d[i - 1][j] + 1.0,             // delete from query
                    d[i][j - 1] + 1.0,             // insert (skip candidate char)
                    d[i - 1][j - 1] + subCost      // substitute / match
                )
                // Damerau transposition of adjacent characters.
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    best = min(best, d[i - 2][j - 2] + 1.0)
                }
                d[i][j] = best
            }
        }

        return d[n].min()
    }

    /// Cost of substituting `typed` where `intended` was expected. A slip onto
    /// a physically adjacent key (per the active layout) is the most forgivable
    /// thumb error, so it costs less than a substitution across the board.
    private static func substitutionCost(
        _ typed: Character,
        _ intended: Character,
        layout: KeyboardLayout
    ) -> Double {
        layout.areAdjacent(typed, intended) ? minEditCost : 1.0
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
