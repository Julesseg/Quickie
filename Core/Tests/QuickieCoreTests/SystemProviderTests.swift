import Foundation
import Testing
@testable import QuickieCore

// The System umbrella provider (CONTEXT.md → System provider; ADR 0029; issue
// #144): a grouping over Reminders and Events with two OS-integration built-ins
// (App Store Search, Open iOS Settings) and a **cascading** Enabled toggle. These
// tests pin the Core half — the provider identity, the declared schema, the two
// built-in Actions, and the umbrella cascade — through the public surface.
struct SystemProviderTests {

    // MARK: Provider identity & the top-level Providers list

    @Test("System is a stable provider identity that folds in Reminders and Events")
    func systemIsUmbrellaIdentity() {
        #expect(ProviderID.system.rawValue == "system")
        #expect(ProviderID.system.displayName == "System")
        // Reminders and Events live under the umbrella; nothing else does.
        #expect(ProviderID.reminders.umbrellaParent == .system)
        #expect(ProviderID.events.umbrellaParent == .system)
        #expect(ProviderID.system.umbrellaParent == nil)
        #expect(ProviderID.quicklinks.umbrellaParent == nil)
    }

    @Test("the top-level Providers list shows System, not Reminders or Events")
    func topLevelProvidersFoldMembersUnderSystem() {
        let list = ProviderID.topLevelProviders
        #expect(list.contains(.system))
        // The umbrella members are gone from the top level — reachable through
        // System (and by typing their names), not as their own rows.
        #expect(!list.contains(.reminders))
        #expect(!list.contains(.events))
        // Every non-member provider still lists itself.
        #expect(list.contains(.quicklinks))
        #expect(list.contains(.calculator))
    }

    // MARK: The declared schema

    @Test("System's schema is Enabled plus link rows to Reminders and Events")
    func systemSchemaLeadsWithEnabledThenLinks() {
        let schema = ProviderID.system.settingsSchema
        // Enabled first (issue #67), as for every provider.
        #expect(schema.first?.kind == .enabled)
        // Then two navigation rows (the schema's `link` kind) into the unchanged
        // Reminders and Events pages (ADR 0029) — linked, not merged.
        let links = schema.compactMap { option -> ManagementPage? in
            if case .link(let page) = option.kind { return page }
            return nil
        }
        #expect(links == [.settings(panel: .reminders), .settings(panel: .events)])
    }

    @Test("Reminders and Events keep their own unchanged schemas")
    func memberSchemasAreUnchanged() {
        // System groups them; it does not absorb their options. Each still leads
        // with its own Enabled toggle and carries its own options.
        #expect(ProviderID.reminders.settingsSchema.first?.kind == .enabled)
        #expect(ProviderID.reminders.settingsSchema.contains { $0.key == SettingsKey.reminderList })
        #expect(ProviderID.events.settingsSchema.contains { $0.key == SettingsKey.eventCalendar })
    }

    // MARK: App Store Search

    @Test("App Store Search collects one free-text argument and opens the store search")
    func appStoreSearchOpensStoreSearch() {
        let action = Action.appStoreSearch()
        #expect(action.id == Action.appStoreSearchID)
        #expect(action.kind == .system)
        // One free-text argument — the seeded query lands here.
        #expect(action.arguments.count == 1)
        #expect(action.arguments.first?.contentType == .text)

        // Committing the breadcrumb opens the App Store's public search URL.
        let outcome = action.run(arguments: [.text("threes")])
        guard case .openURL(let url) = outcome else {
            Issue.record("expected an openURL outcome, got \(outcome)")
            return
        }
        #expect(url.scheme == "itms-apps")
        #expect(url.absoluteString.contains("term=threes"))
        #expect(url.absoluteString.contains("media=software"))
    }

    @Test("App Store Search is fallback-eligible by its text-first shape")
    func appStoreSearchIsFallbackEligible() {
        // A free-text first slot admits it to the Fallback list's pool (CONTEXT.md
        // → Fallback Action) — derived from shape, no flag.
        #expect(Action.appStoreSearch().isFallbackEligible)
    }

    @Test("an empty App Store query falls back to the bare store search, not a broken open")
    func appStoreSearchEmptyTermFallsBackToLanding() {
        // The URL builder refuses to term an empty query…
        #expect(Action.appStoreSearchURL(term: "   ") == nil)
        // …but the action's outcome stays a real `.openURL` (the bare software
        // search landing), so the row's glyph/label classify like web search's and
        // never dead-ends. The required slot never actually commits empty in use.
        #expect(Action.appStoreSearch().run(arguments: [.text("  ")]) == .openURL(Action.appStoreSearchLandingURL))
    }

    // MARK: Open iOS Settings

    @Test("Open iOS Settings is an argument-less command row opening Quickie's Settings page")
    func openIOSSettingsOpensSettingsApp() {
        let action = Action.openIOSSettings()
        #expect(action.id == Action.openIOSSettingsID)
        #expect(action.kind == .system)
        // No arguments — a plain command row, no breadcrumb.
        #expect(action.arguments.isEmpty)
        // Opens `app-settings:` — the value of UIApplication.openSettingsURLString.
        #expect(action.run() == .openURL(URL(string: "app-settings:")!))
    }

    @Test("Open iOS Settings is never fallback-eligible and has no result content")
    func openIOSSettingsIsNeverFallbackEligible() {
        let action = Action.openIOSSettings()
        // No free-text first slot → never in the Fallback pool.
        #expect(!action.isFallbackEligible)
        // A plain command row carries no Result content, so it exposes no
        // copy/share secondary actions (ADR 0017).
        #expect(action.content == .none)
    }

    // MARK: The umbrella cascade

    @Test("System off short-circuits Reminders and Events; their own toggles restore")
    func umbrellaCascadeShortCircuitsMembers() {
        var enablement = ProviderEnablement()
        // All on by default — every member effectively enabled.
        #expect(enablement.isEffectivelyEnabled(.reminders))
        #expect(enablement.isEffectivelyEnabled(.events))

        // System off silences every member beneath it…
        enablement.setEnabled(false, for: .system)
        #expect(!enablement.isEffectivelyEnabled(.reminders))
        #expect(!enablement.isEffectivelyEnabled(.events))
        #expect(!enablement.isEffectivelyEnabled(.system))
        // …while their own toggles stay set — the raw switch is untouched.
        #expect(enablement.isEnabled(.reminders))
        #expect(enablement.isEnabled(.events))

        // Turning System back on restores exactly the members' own states: here
        // Reminders was independently disabled underneath, so it stays off; Events
        // comes back.
        enablement.setEnabled(false, for: .reminders)
        enablement.setEnabled(true, for: .system)
        #expect(!enablement.isEffectivelyEnabled(.reminders))
        #expect(enablement.isEffectivelyEnabled(.events))
    }

    /// The providers wired the way the app wires them: the two captures under
    /// their kinds, the System built-ins under `.system`, and the built-in command
    /// rows (which include the System page's typed recovery row).
    private func systemProviders() -> [Provider] {
        [
            IndexedProvider.builtIns(),
            IndexedProvider(catalog: [.newReminder()], id: .reminders),
            IndexedProvider(catalog: [.newEvent()], id: .events),
            IndexedProvider(catalog: [.appStoreSearch(), .openIOSSettings()], id: .system),
        ]
    }

    @Test("System off hides New Reminder, New Event, and both built-ins from results")
    func systemOffHidesEveryMemberAction() {
        let providers = systemProviders()

        // Enabled: each member surfaces by name.
        let on = SearchEngine(providers: providers)
        #expect(on.results(for: "reminder").map(\.id).contains(Action.newReminderID))
        #expect(on.results(for: "event").map(\.id).contains(Action.newEventID))
        #expect(on.results(for: "app store").map(\.id).contains(Action.appStoreSearchID))
        #expect(on.results(for: "ios settings").map(\.id).contains(Action.openIOSSettingsID))

        // System off: every member action goes dark, even though its own kind
        // toggle is untouched (the cascade, ADR 0029).
        var enablement = ProviderEnablement()
        enablement.setEnabled(false, for: .system)
        let off = SearchEngine(providers: providers, enablement: enablement)
        #expect(!off.results(for: "reminder").map(\.id).contains(Action.newReminderID))
        #expect(!off.results(for: "event").map(\.id).contains(Action.newEventID))
        #expect(!off.results(for: "app store").map(\.id).contains(Action.appStoreSearchID))
        #expect(!off.results(for: "ios settings").map(\.id).contains(Action.openIOSSettingsID))

        // The System page's typed row still answers, so it is re-enableable by name.
        #expect(off.results(for: "system").map(\.id).contains("builtin.system-page"))
    }
}
