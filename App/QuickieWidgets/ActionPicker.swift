import AppIntents
import QuickieCore

/// The shared **picker** behind the [[Actions widget]] and [[Action control]]
/// configuration (ADR 0027): one `AppEntity` with a dynamic query that enumerates
/// the published **eligible-action catalog** (`EligibleActionCatalogStore`), so the
/// system Edit-Widget sheet / Control Center config offer exactly the eligible
/// Actions live *now* — every enabled Action except a Pile entry.
///
/// Everything *decidable* lives in Core: the eligibility rule is
/// `SearchEngine.eligibleActions()` and the id-join is `EligibleActionCatalog.resolve`
/// (both `swift test`-covered). This file is the thin Apple layer — App Intents is
/// Apple-only — reading the catalog from the App Group snapshot so the query works
/// out of process, where SwiftData and the engine don't exist.

/// One choosable Action in the picker — a catalog member. It carries the full
/// denormalized `WidgetAction` so the configuration parameter's chosen values can be
/// rendered richly (title + badge glyph) in the config sheet; only the **id** is
/// persisted into the configuration, and the render surfaces re-join those ids
/// against the live catalog, so a stale entity degrades rather than drawing stale.
struct EligibleActionEntity: AppEntity, Identifiable {
    let id: String
    let title: String
    let glyph: String

    init(id: String, title: String, glyph: String) {
        self.id = id
        self.title = title
        self.glyph = glyph
    }

    init(_ action: WidgetAction) {
        self.init(id: action.id, title: action.title, glyph: action.glyph)
    }

    /// How the parameter's *type* reads in the configuration UI.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Quickie Action")
    }

    /// How one member reads in the picker — its title beside its provider glyph, the
    /// same badge symbol the grid draws, so the choice and the rendered cell match.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: glyph))
    }

    // A computed property (not a stored `static var`, which Swift 6 rejects as
    // nonisolated shared mutable state): the query holds no state — it reads the
    // published snapshot each call — so a fresh value per access is free and safe.
    static var defaultQuery: EligibleActionQuery { EligibleActionQuery() }
}

/// The **dynamic** query behind the entity (ADR 0027): it enumerates the current
/// eligible catalog from the published `EligibleActionCatalogStore` snapshot. The
/// app rewrites that snapshot (publish-only-on-change) and reloads the widget /
/// control on every set change, so the picker always offers the live set.
struct EligibleActionQuery: EntityQuery {
    /// Resolve specific ids the system already holds — filtered to the ones still in
    /// the catalog. A dropped id simply isn't returned; the render path additionally
    /// guards staleness by re-joining ids live (`EligibleActionCatalog.resolve`).
    func entities(for identifiers: [String]) async throws -> [EligibleActionEntity] {
        let wanted = Set(identifiers)
        return EligibleActionCatalogStore.load()
            .filter { wanted.contains($0.id) }
            .map(EligibleActionEntity.init)
    }

    /// Every current member — the options the config sheet presents.
    func suggestedEntities() async throws -> [EligibleActionEntity] {
        EligibleActionCatalogStore.load().map(EligibleActionEntity.init)
    }
}
