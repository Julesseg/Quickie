import Foundation
import Testing
@testable import QuickieCore

// The **Bridged Action** set (CONTEXT.md → Bridged Action; ADR 0024; issue #122) is
// the union of the user's Favorites and Custom Actions, minus anything Disabled —
// the derived, never hand-curated membership the single parameterized App Shortcut
// ("Run <name> with Quickie") exposes outward. The derivation rule is pure logic in
// `QuickieCore` (`SearchEngine.bridgedActions()`), covered here so the whole
// membership/exclusion/stable-id grammar is exercised without a device; the App's
// `AppEntity` + dynamic query is a thin shell that reads this list.
struct BridgedActionTests {

    /// A Quicklink catalog attributed to the `.quicklinks` kind, so its Enabled
    /// toggle and per-instance disable can be exercised — the same wiring the App's
    /// `engine` builds.
    private func engine(
        quicklinks: [Action] = [],
        customActions: [Action] = [],
        favorites: [String] = [],
        enablement: ProviderEnablement = ProviderEnablement(),
        disabledInstances: Set<String> = []
    ) -> SearchEngine {
        SearchEngine(
            providers: [
                IndexedProvider(catalog: quicklinks, id: .quicklinks),
                IndexedProvider(catalog: customActions, id: .customActions),
            ],
            favorites: favorites,
            enablement: enablement,
            disabledInstances: disabledInstances
        )
    }

    // MARK: Tracer bullet — a favorite surfaces

    @Test("a pinned Favorite surfaces as a bridged action carrying its id and title")
    func favoriteSurfaces() {
        let link = Action.quicklink(id: "ql.docs", title: "Docs", url: URL(string: "https://docs.example")!)
        let bridged = engine(quicklinks: [link], favorites: ["ql.docs"]).bridgedActions()
        #expect(bridged == [BridgedAction(id: "ql.docs", title: "Docs")])
    }

    /// A convenience for a text-first Custom Action (the common shape — one free-text
    /// slot), so tests read as "a Custom Action named X".
    private func customAction(id: String, name: String) -> Action {
        CustomActionDefinition(name: name, template: "https://x.example/?q={query}").makeAction(id: id)!
    }

    // MARK: Union — Custom Actions surface whether or not they are pinned

    @Test("an unpinned Custom Action is still bridged — the set is Favorites ∪ Custom Actions")
    func unpinnedCustomActionSurfaces() {
        let custom = customAction(id: "ca.translate", name: "Translate")
        let bridged = engine(customActions: [custom]).bridgedActions()
        #expect(bridged == [BridgedAction(id: "ca.translate", title: "Translate")])
    }

    @Test("Favorites come first in pin order, then non-favorited Custom Actions in catalog order")
    func favoritesLeadThenCustomActions() {
        let link = Action.quicklink(id: "ql.docs", title: "Docs", url: URL(string: "https://docs.example")!)
        let translate = customAction(id: "ca.translate", name: "Translate")
        let convert = customAction(id: "ca.convert", name: "Convert")
        let bridged = engine(
            quicklinks: [link],
            customActions: [translate, convert],
            favorites: ["ql.docs"]
        ).bridgedActions()
        #expect(bridged.map(\.id) == ["ql.docs", "ca.translate", "ca.convert"])
    }

    @Test("a pinned Custom Action appears once, in its Favorite slot — not twice")
    func pinnedCustomActionIsNotDuplicated() {
        let translate = customAction(id: "ca.translate", name: "Translate")
        let convert = customAction(id: "ca.convert", name: "Convert")
        let bridged = engine(
            customActions: [translate, convert],
            favorites: ["ca.convert"]
        ).bridgedActions()
        // `ca.convert` is pinned, so it leads (favorite slot); `ca.translate` follows
        // from the catalog. `ca.convert` is emitted once, never again from the catalog.
        #expect(bridged.map(\.id) == ["ca.convert", "ca.translate"])
    }

    // MARK: Disabled exclusion — kind level

    @Test("disabling the Custom Actions kind drops every Custom Action from the set")
    func disabledCustomActionsKindExcludesAll() {
        var enablement = ProviderEnablement()
        enablement.setEnabled(false, for: .customActions)
        let custom = customAction(id: "ca.translate", name: "Translate")
        let bridged = engine(customActions: [custom], enablement: enablement).bridgedActions()
        #expect(bridged.isEmpty)
    }

    @Test("disabling a favorited Action's kind drops it from the set (but keeps the pin)")
    func disabledFavoriteKindExcludesFavorite() {
        var enablement = ProviderEnablement()
        enablement.setEnabled(false, for: .quicklinks)
        let link = Action.quicklink(id: "ql.docs", title: "Docs", url: URL(string: "https://docs.example")!)
        let bridged = engine(quicklinks: [link], favorites: ["ql.docs"], enablement: enablement).bridgedActions()
        #expect(bridged.isEmpty)
    }

    // MARK: Disabled exclusion — instance level

    @Test("an instance-disabled Custom Action drops from the set while its kind stays enabled")
    func disabledInstanceExcludesOne() {
        let translate = customAction(id: "ca.translate", name: "Translate")
        let convert = customAction(id: "ca.convert", name: "Convert")
        let bridged = engine(
            customActions: [translate, convert],
            disabledInstances: ["ca.translate"]
        ).bridgedActions()
        #expect(bridged.map(\.id) == ["ca.convert"])
    }

    @Test("an instance-disabled favorite drops from the set (the pin itself is untouched)")
    func disabledInstanceExcludesFavorite() {
        let link = Action.quicklink(id: "ql.docs", title: "Docs", url: URL(string: "https://docs.example")!)
        let bridged = engine(
            quicklinks: [link],
            favorites: ["ql.docs"],
            disabledInstances: ["ql.docs"]
        ).bridgedActions()
        #expect(bridged.isEmpty)
    }

    // MARK: Graceful staleness — an unresolvable reference contributes nothing

    @Test("a favorite id whose target was deleted drops out — the set never dangles")
    func deletedFavoriteDropsOut() {
        // "ql.gone" is pinned but no longer in the catalog (its Quicklink was deleted).
        let link = Action.quicklink(id: "ql.docs", title: "Docs", url: URL(string: "https://docs.example")!)
        let bridged = engine(quicklinks: [link], favorites: ["ql.gone", "ql.docs"]).bridgedActions()
        #expect(bridged.map(\.id) == ["ql.docs"])
    }

    @Test("every offered member resolves through action(for:) — offered ⟺ tap-equivalent")
    func offeredMembersAllResolve() {
        let link = Action.quicklink(id: "ql.docs", title: "Docs", url: URL(string: "https://docs.example")!)
        let custom = customAction(id: "ca.translate", name: "Translate")
        let e = engine(quicklinks: [link], customActions: [custom], favorites: ["ql.docs"])
        for member in e.bridgedActions() {
            #expect(e.action(for: member.id) != nil)
        }
    }

    // MARK: The set is derived, never invented

    @Test("with four Favorites and Custom Actions, the set is exactly their union — no invented member")
    func neverInventsMembers() {
        let links = (1...4).map {
            Action.quicklink(id: "ql.\($0)", title: "Link \($0)", url: URL(string: "https://x.example/\($0)")!)
        }
        let custom = customAction(id: "ca.translate", name: "Translate")
        let bridged = engine(
            quicklinks: links,
            customActions: [custom],
            favorites: ["ql.1", "ql.2", "ql.3", "ql.4"]
        ).bridgedActions()
        // Exactly the four pins plus the one Custom Action — nothing more.
        #expect(bridged.map(\.id) == ["ql.1", "ql.2", "ql.3", "ql.4", "ca.translate"])
    }

    @Test("re-enabling a disabled member restores it to the set — disable is reversible")
    func reEnableRestoresMembership() {
        let translate = customAction(id: "ca.translate", name: "Translate")
        // Disabled instance → absent…
        var enablement = ProviderEnablement()
        #expect(engine(customActions: [translate], disabledInstances: ["ca.translate"]).bridgedActions().isEmpty)
        // …disabled kind → absent…
        enablement.setEnabled(false, for: .customActions)
        #expect(engine(customActions: [translate], enablement: enablement).bridgedActions().isEmpty)
        // …both switches back on → present again, unchanged.
        let restored = engine(customActions: [translate]).bridgedActions()
        #expect(restored == [BridgedAction(id: "ca.translate", title: "Translate")])
    }

    // MARK: Persisted snapshot round-trip

    @Test("the derived set round-trips through Codable — the App persists it as the sync snapshot")
    func setRoundTripsThroughCodable() throws {
        // The App can't run here (Linux/cloud), and it persists `bridgedActions()`
        // to the shared store as JSON so the out-of-process entity query reads it —
        // so lock the encode/decode contract in Core, where the gate reaches it.
        let set = [
            BridgedAction(id: "ql.docs", title: "Docs"),
            BridgedAction(id: "ca.translate", title: "Translate"),
        ]
        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode([BridgedAction].self, from: data) == set)
    }
}
