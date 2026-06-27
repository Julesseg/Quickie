import Foundation
import Testing
@testable import QuickieCore

// A Provider is the source of Actions. The skeleton ships exactly one kind —
// an Indexed Provider whose Actions are a known, enumerable set (ADR 0004).
// These tests pin that contract without reaching into how the catalog is
// stored or queried.
struct IndexedProviderTests {

    @Test("an indexed provider identifies as indexed")
    func isIndexedKind() {
        let provider = IndexedProvider(catalog: [])
        #expect(provider.kind == .indexed)
    }

    @Test("an indexed provider offers its whole catalog as candidates")
    func offersWholeCatalog() {
        let catalog = [
            Action.staticLink(id: "a", title: "Open Apple", url: URL(string: "https://apple.com")!),
            Action.staticLink(id: "g", title: "Open GitHub", url: URL(string: "https://github.com")!),
        ]
        let provider = IndexedProvider(catalog: catalog)
        // Indexed providers don't filter by query — the SearchEngine matches
        // and ranks. The provider just enumerates.
        #expect(provider.candidates(for: "anything").map(\.id) == ["a", "g"])
        #expect(provider.candidates(for: "").map(\.id) == ["a", "g"])
    }

    @Test("the built-in provider supplies several actions")
    func builtInsSupplyActions() {
        let provider = IndexedProvider.builtIns()
        #expect(provider.candidates(for: "").count >= 3)
    }

    @Test("the built-ins ship a web-search Fallback")
    func builtInsShipWebSearchFallback() {
        // The one Fallback the skeleton ships, so any typed text always has a
        // home (CONTEXT.md → Fallback Action; issue #5).
        let fallbacks = IndexedProvider.builtIns().candidates(for: "").filter(\.isFallback)
        #expect(fallbacks.contains { $0.id == "builtin.web-search" })
    }

    @Test("the built-in web-search engine is configurable")
    func builtInsAcceptCustomEngine() {
        // The app passes the user's persisted engine template here (AC #6).
        let provider = IndexedProvider.builtIns(webSearchTemplate: "https://www.google.com/search?q={query}")
        let search = provider.candidates(for: "").first { $0.id == "builtin.web-search" }!
        #expect(search.run(input: "swift")
                == .openURL(URL(string: "https://www.google.com/search?q=swift")!))
    }
}
