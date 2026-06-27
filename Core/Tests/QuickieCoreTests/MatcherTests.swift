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
}
