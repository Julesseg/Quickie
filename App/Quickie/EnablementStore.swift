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
        // Honors the same UI-test reset flag as SignalsStore (shared constant),
        // so a test asking for a clean launcher also gets every action enabled.
        if ProcessInfo.processInfo.arguments.contains(SignalsStore.uitestResetArgument) {
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

    /// Disables an action outright — the newly-imported-Shortcut path: every fresh
    /// import starts hidden until the user enables it, so a sync never floods
    /// results. Idempotent; persists only on a real change.
    func disable(_ id: String) {
        guard !disabled.contains(id) else { return }
        disabled.insert(id)
        defaults.set(Array(disabled), forKey: Self.disabledKey)
    }
}
