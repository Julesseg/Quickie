import Foundation
import Observation
import QuickieCore

/// Owns the unified **Fallback list** state (CONTEXT.md → Fallback list): the
/// user's explicit, most-important-first order over every Fallback Action
/// (fallback-flagged Custom Actions + Save for later + New Snippet) plus the set of
/// **disabled** ones. Persisted in the shared App Group's `UserDefaults` so it
/// survives launches and the future Share Extension reads the same source of truth
/// (ADR 0006), mirroring `SignalsStore`.
///
/// Order and disabled state must span both stored Custom Actions *and* the two
/// permanent built-in Fallbacks (Save for later / New Snippet), which aren't
/// SwiftData entities — so they live here as id lists rather than as a column on
/// the Custom Action model. The store reconciles its persisted order against the
/// live set of ids on every read: unknown ids (a freshly added or seeded Custom
/// Action) are appended in a stable order, and ids that no longer exist are pruned.
@MainActor
@Observable
final class FallbacksStore {
    /// The two permanent, disable-only built-in Fallbacks, in their default
    /// most-important-first position (after the user's queries). Their ids match
    /// the Core factories so the persisted order lines up with the Actions.
    static let saveForLaterID = "builtin.save-for-later"
    static let newSnippetID = "builtin.new-snippet"
    static let permanentIDs = [saveForLaterID, newSnippetID]

    /// The pre-Pile id of the "New Note" Fallback (ADR 0018): mapped to Save for
    /// later on load so a user's position/disable of the old capture carries over.
    private static let legacyNewNoteID = "builtin.new-note"

    /// The persisted order, most-important-first. May lag the live id set between
    /// edits; `resolvedOrder(for:)` reconciles it.
    private(set) var order: [String]
    /// The disabled fallback ids — kept in the list, hidden from results.
    private(set) var disabled: Set<String>

    @ObservationIgnored private let defaults: UserDefaults
    private static let orderKey = "fallbacks.order"
    private static let disabledKey = "fallbacks.disabled"

    init(defaults: UserDefaults = SignalsStore.sharedDefaults) {
        self.defaults = defaults
        // Normalize the legacy New Note id on read (ADR 0018): Save for later
        // replaced it, keeping its slot in the order and its disabled state.
        self.order = (defaults.stringArray(forKey: Self.orderKey) ?? [])
            .map { $0 == Self.legacyNewNoteID ? Self.saveForLaterID : $0 }
        self.disabled = Set((defaults.stringArray(forKey: Self.disabledKey) ?? [])
            .map { $0 == Self.legacyNewNoteID ? Self.saveForLaterID : $0 })
    }

    static func launch() -> FallbacksStore {
        // Honors the same UI-test reset flag as SignalsStore (shared constant), so
        // a test asking for a clean launcher also gets a clean Fallback list —
        // order and disabled set reset alongside Favorites/Frecency.
        if ProcessInfo.processInfo.arguments.contains(SignalsStore.uitestResetArgument) {
            let defaults = SignalsStore.sharedDefaults
            defaults.removeObject(forKey: orderKey)
            defaults.removeObject(forKey: disabledKey)
        }
        return FallbacksStore()
    }

    /// Whether a fallback is currently disabled.
    func isDisabled(_ id: String) -> Bool { disabled.contains(id) }

    /// Toggles a fallback's disabled state (kept in the list either way), then
    /// persists.
    func toggleDisabled(_ id: String) {
        if disabled.contains(id) { disabled.remove(id) } else { disabled.insert(id) }
        defaults.set(Array(disabled), forKey: Self.disabledKey)
    }

    /// The fallback ids in the user's order, reconciled against the live query
    /// ids: persisted order first (pruned to what still exists), then any new
    /// query ids in `queryIDs` order, then the permanent built-ins if absent. The
    /// engine and the Fallbacks page both read this so list and results agree.
    func resolvedOrder(for queryIDs: [String]) -> [String] {
        let live = Set(queryIDs).union(Self.permanentIDs)
        var result = order.filter(live.contains)
        for id in queryIDs where !result.contains(id) { result.append(id) }
        for id in Self.permanentIDs where !result.contains(id) { result.append(id) }
        return result
    }

    /// Persists a reconciled order — called by the Fallbacks page after a move so
    /// the explicit order sticks, and after reconciliation so pruned/new ids are
    /// captured.
    func setOrder(_ ids: [String]) {
        order = ids
        defaults.set(ids, forKey: Self.orderKey)
    }
}
