import Foundation

/// The kind-level **Disabled** state (CONTEXT.md → Disabled; ADR 0019, issue
/// #67): which Providers the user has reversibly hidden from every surface —
/// typed results, the Frecency "Recent" list, and the Favorites grid — while
/// their data and configuration are retained. Disable is the reversible
/// off-switch, distinct from delete.
///
/// The model stores only the *disabled* ids, so every provider — including one
/// added in a future build — is enabled by default. Settings itself has no
/// `ProviderID`, so it can never appear here: non-disableable by construction.
/// The app persists this in the shared App Group defaults
/// (`ProviderEnablementStore`), the same pure-model/edge-store split as
/// `Frecency` under `SignalsStore`.
public struct ProviderEnablement: Equatable, Sendable {
    /// The kinds the user has switched off.
    public private(set) var disabled: Set<ProviderID>

    public init(disabled: Set<ProviderID> = []) {
        self.disabled = disabled
    }

    /// Whether `provider` currently contributes to any surface.
    public func isEnabled(_ provider: ProviderID) -> Bool {
        !disabled.contains(provider)
    }

    /// Flips a provider's Enabled switch — the first entry of its Management
    /// page's Options section.
    public mutating func setEnabled(_ enabled: Bool, for provider: ProviderID) {
        if enabled {
            disabled.remove(provider)
        } else {
            disabled.insert(provider)
        }
    }

    /// Restores persisted state from `ProviderID` raw values. An id this build
    /// doesn't know — a provider from a newer build, or one since removed — is
    /// dropped: never a crash, never a phantom disabled kind.
    public init(disabledRawValues: [String]) {
        self.disabled = Set(disabledRawValues.compactMap(ProviderID.init(rawValue:)))
    }

    /// The disabled kinds as their persisted identities — what the app writes
    /// into the shared App Group defaults.
    public var disabledRawValues: [String] {
        disabled.map(\.rawValue)
    }
}
