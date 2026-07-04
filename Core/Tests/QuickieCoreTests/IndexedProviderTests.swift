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
            Action.quicklink(id: "a", title: "Open Apple", url: URL(string: "https://apple.com")!),
            Action.quicklink(id: "g", title: "Open GitHub", url: URL(string: "https://github.com")!),
        ]
        let provider = IndexedProvider(catalog: catalog)
        // Indexed providers don't filter by query — the SearchEngine matches
        // and ranks. The provider just enumerates.
        #expect(provider.candidates(for: "anything").map(\.id) == ["a", "g"])
        #expect(provider.candidates(for: "").map(\.id) == ["a", "g"])
    }

    @Test("the built-in provider supplies the management command rows")
    func builtInsSupplyCommands() {
        // Quickie ships no default Quicklinks and no privileged web search (ADR
        // 0013); the built-in indexed catalog is the typed-to management commands.
        let ids = IndexedProvider.builtIns().candidates(for: "").map(\.id)
        #expect(ids.contains("builtin.settings"))
        #expect(ids.contains("builtin.quicklinks-page"))
        #expect(ids.contains("builtin.fallbacks-page"))
        // The Search Files command enters the scoped file-browsing context (ADR 0014).
        #expect(ids.contains("builtin.search-files"))
    }

    @Test("the File Search command is matchable by its file-access aliases")
    func fileSearchMatchesByAlias() {
        // Folder management is reached by typing, not chrome (issue #49; folded
        // into the File Search provider page by issue #66) — so aliases like
        // "folders" and "file access" must surface the command even though its
        // title is "File Search".
        let engine = SearchEngine(providers: [IndexedProvider.builtIns()])
        #expect(engine.results(for: "folders").map(\.id).contains("builtin.file-search-page"))
        #expect(engine.results(for: "file access").map(\.id).contains("builtin.file-search-page"))
    }

    @Test("the built-ins ship no Fallbacks and wear command badges, not data ones")
    func builtInsShipNoFallbacksOrLinks() {
        let actions = IndexedProvider.builtIns().candidates(for: "")
        // The default web-search Custom Action is seeded into the store as
        // ordinary data, not shipped here; the built-ins are command rows only.
        #expect(actions.allSatisfy { !$0.isFallback })
        // A command row never wears a data kind — so the "Quicklinks" command
        // can't be mistaken for a user's Quicklink, nor "Fallbacks" for a Custom Action, nor
        // the "Search Files" entry point for a file result row.
        #expect(actions.allSatisfy { $0.kind == .settings || $0.kind == .managementPage || $0.kind == .searchFiles })
    }
}
