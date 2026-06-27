import Testing
@testable import QuickieCore

// The Matcher answers one question: does this typed query match a candidate
// name, and if so, how well? It is the substrate of the Result list — every
// fuzzy name-match flows through it. These tests pin its observable behavior,
// not its scoring arithmetic, so the scoring can be retuned later without
// rewriting the suite.
struct MatcherTests {

    @Test("a query that is a substring of the candidate matches")
    func substringMatches() {
        #expect(Matcher.score(query: "git", candidate: "Open GitHub") != nil)
    }

    @Test("a query whose characters are absent does not match")
    func nonSubsequenceDoesNotMatch() {
        #expect(Matcher.score(query: "zzz", candidate: "Open GitHub") == nil)
    }

    @Test("matching is case-insensitive")
    func caseInsensitive() {
        #expect(Matcher.score(query: "GITHUB", candidate: "Open GitHub") != nil)
    }

    @Test("scattered characters match as a subsequence")
    func subsequenceMatches() {
        // g..h..b appear in order inside "GitHub"
        #expect(Matcher.score(query: "ghb", candidate: "GitHub") != nil)
    }

    @Test("an empty query does not produce a match signal")
    func emptyQueryHasNoSignal() {
        // The empty-query Home state is the SearchEngine's job; the matcher
        // must not claim that "" matches everything.
        #expect(Matcher.score(query: "", candidate: "Open GitHub") == nil)
    }

    @Test("an exact name scores higher than a mere prefix")
    func exactBeatsPrefix() {
        let exact = Matcher.score(query: "Calculator", candidate: "Calculator")!
        let prefix = Matcher.score(query: "Calc", candidate: "Calculator")!
        #expect(exact > prefix)
    }

    @Test("a prefix scores higher than a buried substring")
    func prefixBeatsBuried() {
        let prefix = Matcher.score(query: "open", candidate: "Open Apple")!
        let buried = Matcher.score(query: "open", candidate: "Reopen Tab")!
        #expect(prefix > buried)
    }

    @Test("a contiguous substring scores higher than a scattered subsequence")
    func substringBeatsSubsequence() {
        let contiguous = Matcher.score(query: "ith", candidate: "GitHub")!   // "ith" appears as-is
        let scattered = Matcher.score(query: "ghb", candidate: "GitHub")!     // g..h..b
        #expect(contiguous > scattered)
    }

    @Test("diacritics are folded so plain ascii still matches")
    func diacriticInsensitive() {
        #expect(Matcher.score(query: "cafe", candidate: "Café Search") != nil)
    }

    @Test("a transposed typo still matches (the dominant thumb error)")
    func transpositionMatches() {
        // "gtihub" swaps the i and t of "GitHub" — not a subsequence, so only a
        // Damerau-Levenshtein pass that knows about transpositions catches it.
        #expect(Matcher.score(query: "gtihub", candidate: "GitHub") != nil)
    }

    @Test("a clean subsequence outranks a transposed typo")
    func subsequenceBeatsTransposition() {
        // The user who typed real-but-scattered letters gets priority over the
        // user who fat-fingered a swap: typo matches are a lower-confidence tier.
        let clean = Matcher.score(query: "ghb", candidate: "GitHub")!      // subsequence
        let typo = Matcher.score(query: "gtihub", candidate: "GitHub")!    // transposition
        #expect(clean > typo)
    }

    @Test("a single dropped character still matches")
    func deletionMatches() {
        // "gthub" is missing the 'i' of "GitHub".
        #expect(Matcher.score(query: "gthub", candidate: "GitHub") != nil)
    }

    @Test("a single stray character still matches")
    func insertionMatches() {
        // "githhub" has an extra 'h'.
        #expect(Matcher.score(query: "githhub", candidate: "GitHub") != nil)
    }

    @Test("a single wrong character still matches")
    func substitutionMatches() {
        // "gothub" types 'o' where 'i' belongs.
        #expect(Matcher.score(query: "gothub", candidate: "GitHub") != nil)
    }

    @Test("a query too many edits away does not match")
    func beyondBudgetDoesNotMatch() {
        // Three wrong characters (x,y,w for i,t,h) blows the small edit budget:
        // at that distance it's a different word, not a typo.
        #expect(Matcher.score(query: "gxywub", candidate: "GitHub") == nil)
    }

    @Test("an adjacent-key typo scores higher than a distant-key typo")
    func adjacencyWeightsSubstitution() {
        // Both are a single substitution of the leading 'g' in "github". On
        // QWERTY 'f' sits right beside 'g'; 'p' is across the board — so the
        // physically plausible slip should be the better match.
        let near = Matcher.score(query: "fithub", candidate: "github", layout: .qwerty)!
        let far = Matcher.score(query: "pithub", candidate: "github", layout: .qwerty)!
        #expect(near > far)
    }

    @Test("the same typo is forgiven differently per keyboard layout")
    func adjacencyIsLayoutAdaptive() {
        // Typing 'e' for the 'z' of "Zoom": on AZERTY 'e' sits beside 'z'
        // (…a-z-e…), on QWERTY they're two rows apart. Same edit, cheaper on
        // the layout where the keys actually touch.
        let azerty = Matcher.score(query: "eoom", candidate: "Zoom", layout: .azerty)!
        let qwerty = Matcher.score(query: "eoom", candidate: "Zoom", layout: .qwerty)!
        #expect(azerty > qwerty)
    }

    @Test("multi-word queries match regardless of token order")
    func tokenOrderIndependent() {
        // "github open" hits "Open GitHub" even though the words are reversed —
        // each token finds its place independently.
        #expect(Matcher.score(query: "github open", candidate: "Open GitHub") != nil)
    }

    @Test("every query token must find a match")
    func allTokensRequired() {
        // "open zzz" fails: "open" is there but "zzz" matches nothing.
        #expect(Matcher.score(query: "open zzz", candidate: "Open GitHub") == nil)
    }

    // The trigram prefilter is the scaling layer: it lets the SearchEngine skip
    // the costly edit-distance pass for candidates that obviously can't be a
    // near-typo of the query. Its one hard contract is soundness — it must
    // never screen out something the full matcher would accept. These tests pin
    // that contract rather than the table arithmetic.

    @Test("the prefilter never screens out a real typo")
    func prefilterIsSoundForTypos() {
        // Every within-budget typo from earlier tests must survive the gate.
        #expect(Matcher.passesTrigramPrefilter("gtihub", "github"))   // transposition
        #expect(Matcher.passesTrigramPrefilter("gthub", "github"))    // deletion
        #expect(Matcher.passesTrigramPrefilter("gothub", "github"))   // substitution
    }

    @Test("short queries are too small to trigram and always pass")
    func prefilterExemptsShortQueries() {
        // A 1–2 char query has no trigram to compare; the gate can't soundly
        // reject it, so it defers to the full matcher.
        #expect(Matcher.passesTrigramPrefilter("gi", "github"))
    }

    @Test("a long query sharing no trigram with the candidate is screened out")
    func prefilterScreensOutDisjointLongQuery() {
        // Long enough to trigram, and not a single run in common — exactly the
        // unrelated candidate the prefilter exists to skip.
        #expect(!Matcher.passesTrigramPrefilter("abcdefghijklmno", "zyxwvutsrqponml"))
    }
}
