import Foundation
import Testing
@testable import QuickieCore

// Settings becomes the per-action hub (ADR 0019; issue #66): a top-level page
// with a Providers section, and one unified Management page per Provider,
// reachable both from that list and as a typed deeplink. These tests pin the
// Core half of that reframe — the stable `ProviderID` and the
// `.openPage(.settings(panel:))` routing target — through the public Action
// factories and the SearchEngine, never the SwiftUI pages that render them.
struct SettingsHubTests {

    @Test("a ProviderID is a stable identity with a user-facing name")
    func providerIDIsStableIdentity() {
        // The raw value is persistence identity (future kind-level enablement
        // keys off it, ADR 0019), so it is pinned here: renaming a case must not
        // silently re-key stored state.
        #expect(ProviderID.customActions.rawValue == "custom-actions")
        #expect(ProviderID.fileSearch.rawValue == "file-search")
        // The display name is what the Providers list and the page title show.
        #expect(ProviderID.customActions.displayName == "Custom Actions")
        #expect(ProviderID.fileSearch.displayName == "File Search")
    }

    @Test("the Settings command row opens the top-level hub — panel: nil")
    func settingsCommandOpensTopLevelHub() {
        // The navigation target extends the existing `.openPage` routing (ADR
        // 0019) rather than adding a parallel mechanism: the same outcome the
        // old flat `.settings` case produced, now with room for a panel.
        #expect(Action.openSettings().run() == .openPage(.settings(panel: nil)))
    }

    @Test("each content provider's command row deeplinks to its page in the hub")
    func contentProviderCommandRowsDeeplinkIntoTheHub() {
        // The former management-page command rows keep their identity (ids,
        // titles, aliases — so pins and Frecency survive) but their *target* is
        // redirected to the provider's unified page under the hub (ADR 0019):
        // typing "custom actions" lands on the Custom Actions page, settings +
        // content in one. There is no separate content page left to open.
        #expect(Action.openCustomActionsPage().run() == .openPage(.settings(panel: .customActions)))
        #expect(Action.openFallbacksPage().run() == .openPage(.settings(panel: .fallbacks)))
        #expect(Action.openSnippetsLibrary().run() == .openPage(.settings(panel: .snippets)))
        #expect(Action.openShortcutsPage().run() == .openPage(.settings(panel: .shortcuts)))
        // The Pile is the deliberate exception (ADR 0018): its typed row opens
        // the temporary *entries* — content, not configuration — so it targets
        // its own `.pile` page; the provider's settings stay reachable from the
        // hub's Providers list (`ProviderID.pile` still exists for that row).
        #expect(Action.openPilePage().run() == .openPage(.pile))
        #expect(ProviderID.pile.displayName == "Pile")
    }

    @Test("Calculator and File Search gain a typed settings command row")
    func rowlessDynamicInjectorsGainASettingsCommandRow() {
        // The dynamic injectors never had a management-page row — there was
        // nothing to manage. The hub gives them one (ADR 0019), so every
        // provider is reachable (and, later, re-enableable) by typing its name.
        let calculator = Action.openCalculatorPage()
        #expect(calculator.title == "Calculator")
        #expect(calculator.kind == .managementPage)
        #expect(calculator.run() == .openPage(.settings(panel: .calculator)))

        let fileSearch = Action.openFileSearchPage()
        #expect(fileSearch.title == "File Search")
        #expect(fileSearch.kind == .managementPage)
        #expect(fileSearch.run() == .openPage(.settings(panel: .fileSearch)))
    }

    @Test("the capture providers gain a typed settings command row too")
    func captureProvidersGainASettingsCommandRow() {
        // Events and Reminders are in the same never-had-one boat as the
        // dynamic injectors: their typed rows ("New Event", "New Reminder")
        // *start captures*, they don't open pages. ADR 0019 says every provider
        // surfaces one Settings command row, so they get their own — distinct
        // from the capture rows, which stay untouched.
        let events = Action.openEventsPage()
        #expect(events.title == "Events")
        #expect(events.kind == .managementPage)
        #expect(events.run() == .openPage(.settings(panel: .events)))

        let reminders = Action.openRemindersPage()
        #expect(reminders.title == "Reminders")
        #expect(reminders.kind == .managementPage)
        #expect(reminders.run() == .openPage(.settings(panel: .reminders)))
    }

    @Test("typing a dynamic injector's name surfaces its settings command row")
    func typingAnInjectorNameSurfacesItsRow() {
        // The rows ride the built-in indexed catalog, so the whole loop works:
        // type the provider's name, get the row, tap to land on its page.
        // "calculator" is no math expression, so the Calculator provider itself
        // stays silent and the settings row is what answers.
        let engine = SearchEngine(providers: [CalculatorProvider(), IndexedProvider.builtIns()])
        #expect(engine.results(for: "calculator").map(\.id).contains("builtin.calculator-page"))
        #expect(engine.results(for: "file search").map(\.id).contains("builtin.file-search-page"))
        // The capture providers' rows ride the same catalog, so typing their
        // names reaches their pages too — alongside, not instead of, the "New
        // Event"/"New Reminder" capture rows the app indexes separately.
        #expect(engine.results(for: "events").map(\.id).contains("builtin.events-page"))
        #expect(engine.results(for: "reminders").map(\.id).contains("builtin.reminders-page"))
    }

    @Test("typing a provider name and pressing Enter deeplinks to its page")
    func typedProviderNameDeeplinksFromTheHighlightedRow() {
        // The whole acceptance loop in one move (issue #66 AC #1): the best
        // match for a typed provider name is its Settings command row, and
        // running it produces the panel deeplink the app pushes.
        let engine = SearchEngine(providers: [CalculatorProvider(), IndexedProvider.builtIns()])

        let customActions = engine.highlighted(for: "custom actions")
        #expect(customActions?.run() == .openPage(.settings(panel: .customActions)))

        let calculator = engine.highlighted(for: "calculator")
        #expect(calculator?.run() == .openPage(.settings(panel: .calculator)))
    }

    @Test("the File Search page absorbs Indexed Folders — one page, one typed route")
    func fileSearchPageAbsorbsIndexedFolders() {
        // The folder grants are File Search's own configuration, so the former
        // standalone Indexed Folders page folds into the File Search provider
        // page (issue #66 follow-up): its file-access aliases move onto the
        // "File Search" settings command row, which stays the single typed
        // route to `.settings(panel: .fileSearch)`.
        let engine = SearchEngine(providers: [IndexedProvider.builtIns()])
        for query in ["folders", "indexed folders", "file access"] {
            #expect(
                engine.results(for: query).map(\.id).contains("builtin.file-search-page"),
                "typing \(query) should surface the File Search settings row"
            )
        }
        // There is no separate Indexed Folders command row left to compete with.
        let ids = IndexedProvider.builtIns().candidates(for: "").map(\.id)
        #expect(!ids.contains("builtin.indexed-folders-page"))
    }

    @Test("Settings is the hub, not a provider — so it can never be disabled")
    func settingsIsNotAProvider() {
        // Non-disableable by construction (issue #66): future kind-level
        // enablement keys off ProviderID, and no such identity exists for
        // Settings — the recovery path can't be switched off.
        #expect(ProviderID(rawValue: "settings") == nil)
        #expect(ProviderID.allCases.allSatisfy { $0.displayName != "Settings" })
    }
}
