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
}
