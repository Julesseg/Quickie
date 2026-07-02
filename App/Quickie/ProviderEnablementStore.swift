import Foundation
import Observation
import QuickieCore

/// Owns the kind-level **Enabled** switches (CONTEXT.md → Disabled; ADR 0019,
/// issue #67) — the `ProviderEnablement` the engine filters by, persisted so a
/// disabled provider stays disabled across launches. Each provider page's
/// Options section leads with its toggle; flipping it writes here and the
/// launcher rebuilds its engine from the new state on the next keystroke.
///
/// Stored in the shared App Group's `UserDefaults` as the disabled ProviderID
/// raw values (ADR 0006: a future extension reads the same source of truth),
/// mirroring `SignalsStore`/`FallbacksStore`. The pure model lives in Core so
/// the filtering is covered by `swift test`; this store is only the persistence
/// edge.
@MainActor
@Observable
final class ProviderEnablementStore {
    /// The kind-level Disabled state the engine is rebuilt with.
    private(set) var enablement: ProviderEnablement

    @ObservationIgnored private let defaults: UserDefaults
    private static let disabledKey = "providers.disabled"

    init(defaults: UserDefaults = SignalsStore.sharedDefaults) {
        self.defaults = defaults
        self.enablement = ProviderEnablement(
            disabledRawValues: defaults.stringArray(forKey: Self.disabledKey) ?? []
        )
    }

    static func launch() -> ProviderEnablementStore {
        // Honors the same UI-test reset flag as SignalsStore (shared constant):
        // a test asking for a clean launcher also gets every provider enabled,
        // so one test disabling a kind can't leak a hidden provider into later
        // runs.
        if ProcessInfo.processInfo.arguments.contains(SignalsStore.uitestResetArgument) {
            SignalsStore.sharedDefaults.removeObject(forKey: disabledKey)
        }
        return ProviderEnablementStore()
    }

    /// Whether a provider currently contributes to any surface — the value the
    /// page's Enabled toggle renders.
    func isEnabled(_ provider: ProviderID) -> Bool {
        enablement.isEnabled(provider)
    }

    /// Flips a provider's Enabled switch, then persists. Reversible by design:
    /// only this hidden/shown state changes, never the provider's data.
    func setEnabled(_ enabled: Bool, for provider: ProviderID) {
        enablement.setEnabled(enabled, for: provider)
        defaults.set(enablement.disabledRawValues, forKey: Self.disabledKey)
    }
}
