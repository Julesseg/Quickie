import Foundation
import Testing
@testable import QuickieCore

// Instance-level enablement (CONTEXT.md → Disabled; issue #68): every single
// action can be reversibly hidden — from typed results, the Frecency "Recent"
// list, and the Favorites grid — while its data and configuration are
// retained. The instance set rides the engine beside the kind-level
// `ProviderEnablement` (issue #67, `ProviderDisableTests`), and a disabled
// kind short-circuits its instances. These tests pin the engine's filtering
// through the public interface only.
struct EnablementTests {

    /// A two-snippet catalog under the Snippets provider identity — the smallest
    /// setup where "hide exactly one instance" is observable in results.
    private func snippetsProvider() -> IndexedProvider {
        IndexedProvider(
            catalog: [
                .snippet(id: "snippet.a", title: "Address home", body: "1 Main St"),
                .snippet(id: "snippet.b", title: "Address work", body: "9 Office Rd"),
            ],
            id: .snippets
        )
    }

    @Test("the engine hides a disabled instance from results; re-enabling restores it")
    func engineHidesDisabledInstanceFromResults() {
        let disabled = SearchEngine(
            providers: [snippetsProvider()],
            disabledInstances: ["snippet.a"]
        )
        let ids = disabled.results(for: "address").map(\.id)
        #expect(!ids.contains("snippet.a"))
        // A sibling under the same kind is untouched — disable is per instance.
        #expect(ids.contains("snippet.b"))

        // Re-enabled (the id left the persisted set): the same catalog surfaces
        // both again — nothing was destroyed by the hide (CONTEXT.md →
        // Disabled: a reversible hide, never a destroy).
        let reEnabled = SearchEngine(providers: [snippetsProvider()])
        let restored = reEnabled.results(for: "address").map(\.id)
        #expect(restored.contains("snippet.a"))
        #expect(restored.contains("snippet.b"))
    }

    @Test("a disabled kind hides all its instances from results, regardless of per-instance state")
    func engineShortCircuitsADisabledKind() {
        // The kind off + one instance individually disabled: the short-circuit
        // must win — no per-instance state can resurface a disabled provider.
        let engine = SearchEngine(
            providers: [snippetsProvider(), IndexedProvider.builtIns()],
            enablement: ProviderEnablement(disabled: [.snippets]),
            disabledInstances: ["snippet.a"]
        )
        let ids = engine.results(for: "address").map(\.id)
        #expect(!ids.contains("snippet.a"))
        #expect(!ids.contains("snippet.b"))

        // A provider with no disableable identity (the built-in command rows) is
        // immune to every kind switch — the Settings recovery path always exists.
        #expect(engine.results(for: "settings").map(\.id).contains("builtin.settings"))
    }

    @Test("a disabled instance drops from Home's Favorites and Recents but keeps its pin")
    func disabledInstanceLeavesHomeButKeepsItsPin() {
        var frecency = Frecency()
        let now = Date()
        frecency.record("snippet.a", at: now)
        frecency.record("snippet.b", at: now)

        let engine = SearchEngine(
            providers: [snippetsProvider()],
            favorites: ["snippet.a"],
            frecency: frecency,
            now: now,
            disabledInstances: ["snippet.a"]
        )

        // Hidden from both Home sections (CONTEXT.md → Disabled: hidden from
        // every surface) — the sibling stays.
        let home = engine.home()
        #expect(home.favorites.isEmpty)
        #expect(home.frecent.map(\.id) == ["snippet.b"])

        // But the id still *resolves*: the App prunes pins against this set, so
        // a disabled favorite keeps its pin and is restored on re-enable —
        // disable is a reversible hide, not a destroy.
        #expect(engine.resolvableHomeIDs().contains("snippet.a"))
    }

    @Test("a disabled Indexed Folder's files are hidden from results and the Search Files context")
    func disabledFolderHidesItsFilesEverywhere() {
        // Two granted folders, one file each — disabling folder A must hide its
        // file from the inline results *and* the uncapped browsing context,
        // while folder B's file stays searchable (the per-folder counterpart
        // of instance disable, issue #68 follow-up).
        let index = FilenameIndex(entries: [
            FileEntry(bookmarkID: "folder-a", relativePath: "report.txt"),
            FileEntry(bookmarkID: "folder-b", relativePath: "recipe.txt"),
        ])
        let provider = FileSearchProvider(index: index, disabledFolders: ["folder-a"])

        let inline = provider.candidates(for: "report").map(\.title)
        #expect(!inline.contains("report.txt"))
        #expect(provider.candidates(for: "recipe").map(\.title).contains("recipe.txt"))

        // The context browses everything it is *allowed* to see — a disabled
        // folder is hidden from every surface, not just the inline rows.
        let browsed = provider.contextMatches(for: "").map(\.title)
        #expect(browsed == ["recipe.txt"])

        // Re-enabling (the id leaving the set) restores the files — the grant
        // and its index were never touched.
        let reEnabled = FileSearchProvider(index: index)
        #expect(reEnabled.candidates(for: "report").map(\.title).contains("report.txt"))
    }

    @Test("the shortcut action-id derivation is public, so a row's toggle keys the id the engine sees")
    func shortcutActionIDDerivationIsShared() {
        // A Shortcut Action's id is derived from its name inside the factory;
        // the shortcut's settings page toggles enablement per row by *name*.
        // Exposing the derivation keeps the two from drifting — a toggle that
        // keyed a different string would disable nothing.
        #expect(Action.shortcutID(for: "Log Water") == Action.shortcut(name: "Log Water").id)
    }
}
