import Foundation
import Testing
@testable import QuickieCore

// The **eligible-action catalog** (CONTEXT.md → Actions widget; ADR 0027) is the
// app-written snapshot of every enabled Action except a Pile entry — the data the
// out-of-process [[Actions widget]] picker enumerates and the widget timeline / the
// [[Action control]]'s value provider join their configured ids against. Three pure
// pieces live under `swift test` here, beside the Favorites snapshot codec: the
// **eligibility rule** (`Action.isWidgetEligible` and the engine's `eligibleActions`),
// the **catalog codec**, and the **id-join** the render surfaces run.
struct EligibleActionCatalogTests {

    // MARK: Eligibility — the pure per-Action shape rule

    @Test("a Pile entry and a query-only capture are the ineligible shapes; everything else is choosable")
    func onlyNonStandaloneShapesAreIneligible() {
        // A Pile entry's main action consumes it (staging), so a button bound to one
        // would die after a single tap.
        #expect(Action.pileEntry(id: "pile.1", text: "call bank").isWidgetEligible == false)
        #expect(Action.pileEntry(id: "pile.1", text: "call bank").isPileEntry == true)

        // A query-only capture (Save for later, New Snippet) has nothing to consume
        // without a typed query, so run standalone it does nothing — also excluded.
        #expect(Action.saveForLater().isQueryOnlyCapture)
        #expect(Action.newSnippet().isQueryOnlyCapture)
        #expect(Action.saveForLater().isWidgetEligible == false)
        #expect(Action.newSnippet().isWidgetEligible == false)

        // Everything else is choosable — snippets, links, shortcuts, the
        // argument-collecting captures (they open a breadcrumb), and command rows.
        #expect(Action.snippet(id: "s.1", title: "Address", body: "1 Main St").isWidgetEligible)
        #expect(Action.quicklink(id: "ql.1", title: "Docs", url: URL(string: "https://x.example")!).isWidgetEligible)
        #expect(Action.shortcut(name: "Start Workout").isWidgetEligible)
        #expect(Action.newReminder().isWidgetEligible)
        #expect(Action.newEvent().isWidgetEligible)
        #expect(Action.openSettings().isWidgetEligible)
        // The argument-collecting captures are not query-only — they collect verb-first.
        #expect(Action.newReminder().isQueryOnlyCapture == false)
        // A text-first Custom Action declares its slot, so it is not query-only either.
        #expect(Action.webSearchFallback().isQueryOnlyCapture == false)
        #expect(Action.webSearchFallback().isWidgetEligible)
    }

    @Test("the Pile page command row is eligible — it is a durable command, not an entry")
    func pileCommandRowIsEligible() {
        // `.openPile` wears the `.pile` *kind* but carries no `.pileEntry` content, so
        // — like `isFavoriteEligible` — the rule keys off content, not kind.
        let command = Action.openPilePage()
        #expect(command.kind == .pile)
        #expect(command.isPileEntry == false)
        #expect(command.isWidgetEligible)
    }

    // MARK: Catalog codec — what the app writes, the picker/render read

    private func item(_ id: String, kind: ActionKind = .quicklink, execution: WidgetExecution = .openApp) -> WidgetAction {
        WidgetAction(id: id, title: "Title \(id)", glyph: "link", kind: kind, execution: execution)
    }

    @Test("the catalog round-trips through the codec, order preserved")
    func catalogRoundTrips() {
        let catalog = [
            item("a", kind: .snippet, execution: .copySnippet(id: "snippet.a")),
            item("b", execution: .handOff(url: URL(string: "https://x.example")!)),
            item("c", kind: .customAction),
        ]
        #expect(EligibleActionCatalog.decode(EligibleActionCatalog.encode(catalog)) == catalog)
    }

    @Test("decoding nothing or garbage yields an empty catalog — never an error")
    func decodeDegradesToEmpty() {
        #expect(EligibleActionCatalog.decode(nil) == [])
        #expect(EligibleActionCatalog.decode(Data("not json".utf8)) == [])
    }

    @Test("the catalog is uncapped — it holds the whole eligible set, not the grid's four")
    func catalogIsUncapped() {
        // Unlike the Favorites snapshot (capped at the 2×2 grid), the catalog is the
        // full picker source; the four-cell cap applies to the *chosen* list, later.
        let many = (0..<10).map { item("id.\($0)") }
        #expect(EligibleActionCatalog.decode(EligibleActionCatalog.encode(many)) == many)
    }

    // MARK: The id-join — configuration ids → rendered actions

    @Test("resolve joins configured ids against the catalog in configured order")
    func resolvePreservesConfiguredOrder() {
        let catalog = [item("a"), item("b"), item("c")]
        // The user chose c, a — the grid fills in *that* order, not catalog order.
        #expect(EligibleActionCatalog.resolve(ids: ["c", "a"], in: catalog).map(\.id) == ["c", "a"])
    }

    @Test("resolve drops an id the catalog no longer holds — a deleted or disabled action")
    func resolveDropsStaleIDs() {
        let catalog = [item("a"), item("b")]
        // "gone" was chosen but has left the catalog (deleted/disabled): it falls out,
        // its slot degrading to the dashed empty cell rather than erroring.
        #expect(EligibleActionCatalog.resolve(ids: ["a", "gone", "b"], in: catalog).map(\.id) == ["a", "b"])
    }

    @Test("resolve deduplicates a repeated id — a doubly-chosen action renders once")
    func resolveDeduplicates() {
        let catalog = [item("a"), item("b")]
        #expect(EligibleActionCatalog.resolve(ids: ["a", "a", "b"], in: catalog).map(\.id) == ["a", "b"])
    }

    @Test("resolving against an empty catalog yields nothing — every id misses")
    func resolveAgainstEmptyCatalog() {
        #expect(EligibleActionCatalog.resolve(ids: ["a", "b"], in: []) == [])
    }

    // MARK: The engine's eligible set — enabled ∧ not a Pile entry

    private func engine(
        snippets: [Action] = [],
        quicklinks: [Action] = [],
        pile: [Action] = [],
        enablement: ProviderEnablement = ProviderEnablement(),
        disabledInstances: Set<String> = []
    ) -> SearchEngine {
        SearchEngine(
            providers: [
                IndexedProvider(catalog: snippets, id: .snippets),
                IndexedProvider(catalog: quicklinks, id: .quicklinks),
                IndexedProvider(catalog: pile, id: .pile),
            ],
            enablement: enablement,
            disabledInstances: disabledInstances
        )
    }

    @Test("eligibleActions lists enabled Actions, excluding Pile entries")
    func eligibleActionsExcludesPileEntries() {
        let snippet = Action.snippet(id: "s.1", title: "Address", body: "1 Main St")
        let link = Action.quicklink(id: "ql.1", title: "Docs", url: URL(string: "https://x.example")!)
        let entry = Action.pileEntry(id: "pile.1", text: "call bank")
        let eligible = engine(snippets: [snippet], quicklinks: [link], pile: [entry]).eligibleActions()
        // The Pile entry is filtered out; the snippet and quicklink survive.
        #expect(eligible.map(\.id) == ["s.1", "ql.1"])
    }

    @Test("eligibleActions excludes a query-only capture — it does nothing run standalone")
    func eligibleActionsExcludesQueryOnlyCapture() {
        let link = Action.quicklink(id: "ql.1", title: "Docs", url: URL(string: "https://x.example")!)
        // Save for later rides an indexed provider (its real home is the pile/capture
        // catalog); it must not surface as a widget/control choice.
        let engine = SearchEngine(
            providers: [
                IndexedProvider(catalog: [link], id: .quicklinks),
                IndexedProvider(catalog: [.saveForLater()], id: .pile),
            ]
        )
        #expect(engine.eligibleActions().map(\.id) == ["ql.1"])
    }

    @Test("a disabled instance drops out — eligibility mirrors runnability")
    func eligibleActionsExcludesDisabledInstance() {
        let a = Action.quicklink(id: "ql.a", title: "A", url: URL(string: "https://a.example")!)
        let b = Action.quicklink(id: "ql.b", title: "B", url: URL(string: "https://b.example")!)
        let eligible = engine(quicklinks: [a, b], disabledInstances: ["ql.a"]).eligibleActions()
        #expect(eligible.map(\.id) == ["ql.b"])
    }

    @Test("a disabled kind drops all its instances — the master switch is honoured")
    func eligibleActionsExcludesDisabledKind() {
        let a = Action.quicklink(id: "ql.a", title: "A", url: URL(string: "https://a.example")!)
        let snippet = Action.snippet(id: "s.1", title: "Address", body: "1 Main St")
        let eligible = engine(
            snippets: [snippet],
            quicklinks: [a],
            enablement: ProviderEnablement(disabled: [.quicklinks])
        ).eligibleActions()
        // Quicklinks disabled → its instance is gone; the enabled Snippet remains.
        #expect(eligible.map(\.id) == ["s.1"])
    }

    @Test("eligibleActions denormalizes cleanly into the shared WidgetAction shape")
    func eligibleActionsDenormalize() {
        let link = Action.quicklink(id: "ql.1", title: "Docs", url: URL(string: "https://x.example")!)
        let eligible = engine(quicklinks: [link]).eligibleActions()
        let projected = eligible.map { WidgetAction(action: $0, glyph: "link") }
        #expect(projected == [
            WidgetAction(id: "ql.1", title: "Docs", glyph: "link", kind: .quicklink,
                         execution: .handOff(url: URL(string: "https://x.example")!)),
        ])
    }
}
