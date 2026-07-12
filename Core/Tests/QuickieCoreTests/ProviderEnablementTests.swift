import Foundation
import Testing
@testable import QuickieCore

// Kind-level enablement (CONTEXT.md → Disabled; ADR 0019, issue #67): every
// provider carries an Enabled switch that reversibly hides the whole kind while
// its data and configuration are retained. These tests pin the pure model — the
// app persists it in the shared App Group defaults, the same split as
// SignalsStore over Frecency.
struct ProviderEnablementTests {

    @Test("every provider is enabled by default, and disabling is reversible")
    func defaultsToEnabledAndDisableIsReversible() {
        var enablement = ProviderEnablement()
        for provider in ProviderID.allCases {
            #expect(enablement.isEnabled(provider))
        }

        enablement.setEnabled(false, for: .customActions)
        #expect(!enablement.isEnabled(.customActions))
        // Disable is the reversible off-switch, distinct from delete: only the
        // toggled kind changes, and toggling back restores it.
        #expect(enablement.isEnabled(.snippets))

        enablement.setEnabled(true, for: .customActions)
        #expect(enablement.isEnabled(.customActions))
    }

    @Test("enablement round-trips through raw values, dropping unknown ids")
    func roundTripsThroughRawValues() {
        var enablement = ProviderEnablement()
        enablement.setEnabled(false, for: .calculator)
        enablement.setEnabled(false, for: .fileSearch)

        // What the app writes into the App Group defaults: the ProviderID raw
        // values (the persisted identity SettingsHubTests pins), order-free.
        #expect(Set(enablement.disabledRawValues) == ["calculator", "file-search"])

        // Reading back tolerates an id this build doesn't know (a provider from
        // a newer build, or a removed one): it is dropped, never a crash and
        // never a phantom disabled kind.
        let restored = ProviderEnablement(disabledRawValues: ["calculator", "file-search", "not-a-provider"])
        #expect(restored == enablement)
        #expect(!restored.isEnabled(.calculator))
        #expect(restored.isEnabled(.customActions))
    }
}
