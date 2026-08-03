import Foundation
import Observation
import QuickieCore

/// Owns the **instance-level Disabled state** (CONTEXT.md → Disabled; issue
/// #68): the set of single actions — a Quicklink, Snippet, Pile entry, or
/// Shortcut — the user has reversibly hidden from results, Recents, and
/// Favorites, keyed by stable Action id. Persisted in the shared App Group's
/// `UserDefaults` so it survives launches and extensions read the same source
/// of truth (ADR 0006), mirroring `SignalsStore` / `FallbacksStore`.
///
/// This one store covers every action's instance-disable, fallbacks included: the
/// Fallbacks page shows the same toggle, and disabling an action also demotes it from
/// the enabled Fallback list into the Available pool (`FallbacksStore.demoteDisabled`).
/// Ids are UUID-derived and never reused, so a deleted action's stale id is inert.
@MainActor
@Observable
final class EnablementStore {
    /// The disabled action ids — each row stays in its Management page's
    /// Actions list, hidden from every launcher surface.
    private(set) var disabled: Set<String>

    @ObservationIgnored private let defaults: UserDefaults
    private static let disabledKey = "enablement.disabledInstances"

    init(defaults: UserDefaults = SignalsStore.sharedDefaults) {
        self.defaults = defaults
        self.disabled = Set(defaults.stringArray(forKey: Self.disabledKey) ?? [])
    }

    static func launch() -> EnablementStore {
        // Cleared under UI testing so a test asking for a clean launcher gets
        // every action enabled. Keyed on `--uitesting` as well as the explicit
        // reset flag, for the same reason as `ProviderEnablementStore.launch()`:
        // this set persists in the App Group defaults, outliving the ephemeral
        // store, so a suite launching with plain `--uitesting` would inherit an
        // earlier suite's disabled instances.
        if ProcessInfo.processInfo.arguments.contains("--uitesting")
            || ProcessInfo.processInfo.arguments.contains(SignalsStore.uitestResetArgument) {
            SignalsStore.sharedDefaults.removeObject(forKey: disabledKey)
        }
        return EnablementStore()
    }

    /// Whether the action with `id` is currently disabled.
    func isDisabled(_ id: String) -> Bool { disabled.contains(id) }

    /// Toggles an action's disabled state (the row stays in its Actions list
    /// either way), then persists.
    func toggleDisabled(_ id: String) {
        if disabled.contains(id) { disabled.remove(id) } else { disabled.insert(id) }
        defaults.set(Array(disabled), forKey: Self.disabledKey)
    }

    /// Disables a batch of actions outright — the newly-imported-Shortcut path:
    /// every fresh import starts hidden until the user enables it, so a sync never
    /// floods results. One persisted write covers the whole batch; already-disabled
    /// ids are no-ops, and an all-stale batch skips the write entirely.
    func disable(_ ids: [String]) {
        let fresh = Set(ids).subtracting(disabled)
        guard !fresh.isEmpty else { return }
        disabled.formUnion(fresh)
        defaults.set(Array(disabled), forKey: Self.disabledKey)
    }
}
