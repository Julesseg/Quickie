import Foundation
import Testing
@testable import QuickieCore

// The Fallbacks page persists a single ordered **enabled list**, read
// most-important-first (CONTEXT.md → Fallback list) — the only fallback fact. The
// SearchEngine projects it into the bottom fallback region: the most-important
// enabled fallback sits nearest the ranked matches (the thumb), and an eligible
// action absent from the list (the derived disabled pool) never rides the region.
// These tests pin that projection without caring how the list is stored.
struct FallbackOrderingTests {

    // Three eligible fallbacks — two text-first Custom Actions plus Save for later —
    // behind a non-matching query so the result list is the fallback region alone.
    private func engine(enabled: [String]) -> SearchEngine {
        SearchEngine(
            providers: [
                IndexedProvider(catalog: [
                    CustomActionDefinition(name: "Search the web", template: "https://ddg/?q={q}").makeAction(id: "fb.ddg")!,
                    CustomActionDefinition(name: "Search GitHub", template: "https://gh/?q={q}").makeAction(id: "fb.gh")!,
                    .saveForLater(),
                ])
            ],
            enabledFallbacks: enabled
        )
    }

    @Test("fallbacks follow the user's enabled-list order, most-important-first")
    func followsUserOrder() {
        // List order (top = most important) → nearest the thumb among fallbacks →
        // earliest in the fallback region of the results array.
        let ids = engine(enabled: ["fb.gh", "builtin.save-for-later", "fb.ddg"])
            .results(for: "zxcvbnm").map(\.id)
        #expect(ids == ["fb.gh", "builtin.save-for-later", "fb.ddg"])
    }

    @Test("reordering the enabled list reorders the fallback region")
    func reorderingReorders() {
        let ids = engine(enabled: ["fb.ddg", "fb.gh", "builtin.save-for-later"])
            .results(for: "zxcvbnm").map(\.id)
        #expect(ids == ["fb.ddg", "fb.gh", "builtin.save-for-later"])
    }

    @Test("an eligible action absent from the enabled list stays in the pool — off the region")
    func pooledIsHidden() {
        // fb.ddg is eligible but not enabled → it is a pool member, so it never
        // appears in the bottom region (and, matching nothing by name here, nowhere).
        let ids = engine(enabled: ["fb.gh", "builtin.save-for-later"])
            .results(for: "zxcvbnm").map(\.id)
        #expect(ids == ["fb.gh", "builtin.save-for-later"])
    }

    @Test("only enabled-list members ride the region, exactly those, in order")
    func onlyEnabledMembersRide() {
        let ids = engine(enabled: ["builtin.save-for-later", "fb.ddg"])
            .results(for: "zxcvbnm").map(\.id)
        #expect(ids == ["builtin.save-for-later", "fb.ddg"])
    }

    @Test("an empty enabled list means no fallback region at all")
    func emptyEnabledMeansNoRegion() {
        #expect(engine(enabled: []).results(for: "zxcvbnm").isEmpty)
    }
}
