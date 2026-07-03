import Foundation
import Testing
@testable import QuickieCore

// The Fallbacks page persists an explicit, user-reorderable order, read
// most-important-first (CONTEXT.md → Fallback list). The SearchEngine projects
// that order into the bottom fallback region of results: the most-important
// fallback sits nearest the ranked matches (the thumb), and a disabled fallback
// is kept in the list but never appears in results. These tests pin that
// projection without caring how the order is stored.
struct FallbackOrderingTests {

    // Three fallbacks — two queries plus Save for later — wired behind a
    // non-matching query so the result list is the fallback region alone.
    private func engine(order: [String] = [], disabled: Set<String> = []) -> SearchEngine {
        SearchEngine(
            providers: [
                IndexedProvider(catalog: [
                    CustomActionDefinition(name: "Search the web", template: "https://ddg/?q={q}", isFallback: true).makeAction(id: "fb.ddg")!,
                    CustomActionDefinition(name: "Search GitHub", template: "https://gh/?q={q}", isFallback: true).makeAction(id: "fb.gh")!,
                    .saveForLater(),
                ])
            ],
            fallbackOrder: order,
            disabledFallbacks: disabled
        )
    }

    @Test("fallbacks follow the user's list order, most-important-first")
    func followsUserOrder() {
        // Page order (top = most important) → nearest the thumb among fallbacks →
        // earliest in the fallback region of the results array.
        let ids = engine(order: ["fb.gh", "builtin.save-for-later", "fb.ddg"])
            .results(for: "zxcvbnm").map(\.id)
        #expect(ids == ["fb.gh", "builtin.save-for-later", "fb.ddg"])
    }

    @Test("reordering the list reorders the fallback region")
    func reorderingReorders() {
        let ids = engine(order: ["fb.ddg", "fb.gh", "builtin.save-for-later"])
            .results(for: "zxcvbnm").map(\.id)
        #expect(ids == ["fb.ddg", "fb.gh", "builtin.save-for-later"])
    }

    @Test("a disabled fallback is kept in the list but absent from results")
    func disabledIsHidden() {
        let ids = engine(order: ["fb.gh", "fb.ddg", "builtin.save-for-later"], disabled: ["fb.ddg"])
            .results(for: "zxcvbnm").map(\.id)
        #expect(ids == ["fb.gh", "builtin.save-for-later"])
    }

    @Test("a fallback missing from the order falls to the end, deterministically")
    func unorderedFallToEnd() {
        // Only one fallback is ordered; the rest still appear, after it, in a
        // stable order so results never reshuffle between runs.
        let ids = engine(order: ["fb.gh"]).results(for: "zxcvbnm").map(\.id)
        #expect(ids.first == "fb.gh")
        #expect(Set(ids) == ["fb.gh", "fb.ddg", "builtin.save-for-later"])
    }
}
