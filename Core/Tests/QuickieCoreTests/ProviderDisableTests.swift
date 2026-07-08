import Foundation
import Testing
@testable import QuickieCore

// The engine half of kind-level disable (CONTEXT.md → Disabled; issue #67): a
// disabled provider contributes nothing to typed results, while the recovery
// path — its Settings command row, which belongs to the hub's built-ins, not to
// the disableable kind — keeps answering its typed name.
struct ProviderDisableTests {

    /// A user Quicklink wired the way the app wires it: an indexed catalog
    /// attributed to the `.quicklinks` kind.
    private func quicklinksProvider() -> IndexedProvider {
        IndexedProvider(
            catalog: [.quicklink(id: "ql.docs", title: "Docs", url: URL(string: "https://example.com/docs")!)],
            id: .quicklinks
        )
    }

    private func disabled(_ providers: ProviderID...) -> ProviderEnablement {
        var enablement = ProviderEnablement()
        for provider in providers { enablement.setEnabled(false, for: provider) }
        return enablement
    }

    @Test("a disabled provider contributes nothing to typed results")
    func disabledProviderContributesNothingToTypedResults() {
        let providers: [Provider] = [IndexedProvider.builtIns(), quicklinksProvider()]

        // Enabled: typing the link's name surfaces it.
        let enabled = SearchEngine(providers: providers)
        #expect(enabled.results(for: "docs").map(\.id).contains("ql.docs"))

        // Disabled: the same query finds nothing from the kind — reversibly
        // hidden, its data untouched.
        let engine = SearchEngine(providers: providers, enablement: disabled(.quicklinks))
        #expect(!engine.results(for: "docs").map(\.id).contains("ql.docs"))
    }

    @Test("a disabled provider stays re-enableable by typing its name")
    func disabledProviderKeepsItsSettingsCommandRow() {
        // The Settings command row rides the hub's built-ins — it belongs to no
        // disableable kind — so disabling Quicklinks must not take away the one
        // typed route back to its Enabled toggle (issue #67 AC #2).
        let providers: [Provider] = [IndexedProvider.builtIns(), quicklinksProvider()]
        let engine = SearchEngine(providers: providers, enablement: disabled(.quicklinks))

        let results = engine.results(for: "quicklinks").map(\.id)
        #expect(results.contains("builtin.quicklinks-page"))
        #expect(!results.contains("ql.docs"))
    }

    @Test("disabling Calculator silences the boosted math result")
    func disabledCalculatorInjectsNothing() {
        // The dynamic injectors are kinds too (issue #67): Calculator declares
        // `.calculator`, so its type-triggered top row obeys the same switch as
        // an indexed catalog.
        let providers: [Provider] = [CalculatorProvider(), IndexedProvider.builtIns()]

        let enabled = SearchEngine(providers: providers)
        #expect(enabled.results(for: "5+5").map(\.id).contains("calc.math"))

        let engine = SearchEngine(providers: providers, enablement: disabled(.calculator))
        #expect(!engine.results(for: "5+5").map(\.id).contains("calc.math"))
        // Its settings command row still answers, so the kind is re-enableable
        // by typing its name.
        #expect(engine.results(for: "calculator").map(\.id).contains("builtin.calculator-page"))
    }

    @Test("disabling File Search silences its file rows")
    func disabledFileSearchSurfacesNoFiles() {
        let index = FilenameIndex(entries: [
            FileEntry(bookmarkID: "folder-1", relativePath: "notes/meeting.md")
        ])
        let providers: [Provider] = [FileSearchProvider(index: index), IndexedProvider.builtIns()]

        let enabled = SearchEngine(providers: providers)
        #expect(enabled.results(for: "meeting").contains { $0.kind == .file })

        let engine = SearchEngine(providers: providers, enablement: disabled(.fileSearch))
        #expect(!engine.results(for: "meeting").contains { $0.kind == .file })
    }

    @Test("disabling Fallbacks is a master switch over the whole bottom region")
    func disabledFallbacksEmptyTheFallbackRegion() {
        // The Fallback list's instances span three kinds — Fallback queries,
        // Save for later, New Snippet — and a disabled kind short-circuits its
        // instances (CONTEXT.md → Disabled, Fallback list). So the master
        // Enabled toggle empties the *whole* region, even though Save for later
        // and New Snippet ride the Pile's and Snippets' catalogs in the app's
        // wiring (issue #67: per-item disable is a later slice).
        let providers: [Provider] = [
            IndexedProvider(catalog: [Action.webSearchFallback()], id: .fallbacks),
            IndexedProvider(catalog: [.saveForLater()], id: .pile),
            IndexedProvider(catalog: [.newSnippet()], id: .snippets),
        ]
        let enabledIDs = [Action.webSearchFallbackID, Action.saveForLaterID, Action.newSnippetID]

        let enabled = SearchEngine(providers: providers, enabledFallbacks: enabledIDs)
        #expect(enabled.results(for: "anything").filter(\.isFallbackEligible).count == 3)

        let engine = SearchEngine(
            providers: providers, enabledFallbacks: enabledIDs, enablement: disabled(.fallbacks)
        )
        #expect(engine.results(for: "anything").filter(\.isFallbackEligible).isEmpty)
    }

    @Test("disabling the Pile hides its capture Fallback along with its entries")
    func disabledPileHidesItsEntriesAndCapture() {
        // Save for later feeds the Pile, and the app wires it into the Pile's
        // catalog — so the Pile's switch governs both the saved entries and the
        // capture that creates them, while the other fallbacks stay.
        let providers: [Provider] = [
            IndexedProvider(catalog: [Action.webSearchFallback()], id: .fallbacks),
            IndexedProvider(
                catalog: [.pileEntry(id: "pile.1", text: "call the bank"), .saveForLater()],
                id: .pile
            ),
        ]

        let engine = SearchEngine(
            providers: providers,
            enabledFallbacks: [Action.webSearchFallbackID, Action.saveForLaterID],
            enablement: disabled(.pile)
        )
        let results = engine.results(for: "call the bank").map(\.id)
        #expect(!results.contains("pile.1"))
        #expect(!results.contains("builtin.save-for-later"))
        #expect(results.contains("builtin.web-search"))
    }

    @Test("a disabled Favorite drops from the grid without consuming a slot")
    func disabledFavoriteDropsFromTheGridButKeepsItsPin() {
        // Two pins: a Quicklink and a built-in command. Disabling Quicklinks
        // must drop only the link's card — the other Favorite still renders, so
        // the hidden pin consumes no visible slot (issue #67 AC #3).
        let providers: [Provider] = [IndexedProvider.builtIns(), quicklinksProvider()]
        let favorites = ["ql.docs", "builtin.search-files"]

        let engine = SearchEngine(
            providers: providers,
            favorites: favorites,
            enablement: disabled(.quicklinks)
        )
        #expect(engine.home().favorites.map(\.id) == ["builtin.search-files"])

        // The pin itself survives: the app prunes pins against
        // `resolvableHomeIDs()`, and a *disabled* action still resolves — only a
        // *deleted* one is gone. Re-enabling restores the card from the kept pin.
        #expect(engine.resolvableHomeIDs().contains("ql.docs"))

        let reEnabled = SearchEngine(providers: providers, favorites: favorites)
        #expect(reEnabled.home().favorites.map(\.id) == favorites)
    }

    @Test("a disabled Pile is still re-enableable by typing — via Pile Settings")
    func disabledPileKeepsATypedRouteToItsToggle() {
        // The Pile's typed "Pile" row opens its *entries* page, which carries no
        // options (the ADR 0018 carve-out) — so without a settings command row of
        // its own, a disabled Pile would be re-enableable only from the hub's
        // Providers list, breaking issue #67 AC #2 for exactly one provider. The
        // "Pile Settings" built-in closes that: it deeplinks to the provider's
        // options-only page and, riding the built-ins, survives the disable.
        #expect(Action.openPileSettings().run() == .openPage(.settings(panel: .pile)))

        let providers: [Provider] = [
            IndexedProvider.builtIns(),
            IndexedProvider(catalog: [.pileEntry(id: "pile.1", text: "call the bank"), .saveForLater()], id: .pile),
        ]
        let engine = SearchEngine(providers: providers, enablement: disabled(.pile))
        #expect(engine.results(for: "pile").map(\.id).contains("builtin.pile-settings"))
    }

    @Test("a disabled provider's actions leave the Recent list")
    func disabledProviderLeavesTheFrecencyList() {
        // The link was used often — but its kind is switched off, so the
        // Frecency "Recent" list must not surface it; the signal itself keeps
        // recording for the day it is re-enabled.
        let providers: [Provider] = [IndexedProvider.builtIns(), quicklinksProvider()]
        var frecency = Frecency()
        let now = Date()
        frecency.record("ql.docs", at: now)
        frecency.record("builtin.search-files", at: now)

        let engine = SearchEngine(
            providers: providers,
            frecency: frecency,
            now: now,
            enablement: disabled(.quicklinks)
        )
        let recent = engine.home().frecent.map(\.id)
        #expect(!recent.contains("ql.docs"))
        #expect(recent.contains("builtin.search-files"))
    }
}
