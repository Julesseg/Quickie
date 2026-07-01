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
        #expect(ProviderID.quicklinks.rawValue == "quicklinks")
        #expect(ProviderID.fileSearch.rawValue == "file-search")
        // The display name is what the Providers list and the page title show.
        #expect(ProviderID.quicklinks.displayName == "Quicklinks")
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
        // typing "quicklinks" lands on the Quicklinks page, settings + content
        // in one. There is no separate content page left to open.
        #expect(Action.openQuicklinksPage().run() == .openPage(.settings(panel: .quicklinks)))
        #expect(Action.openFallbacksPage().run() == .openPage(.settings(panel: .fallbacks)))
        #expect(Action.openNotesLibrary().run() == .openPage(.settings(panel: .notes)))
        #expect(Action.openSnippetsLibrary().run() == .openPage(.settings(panel: .snippets)))
        #expect(Action.openShortcutsPage().run() == .openPage(.settings(panel: .shortcuts)))
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

    @Test("typing a dynamic injector's name surfaces its settings command row")
    func typingAnInjectorNameSurfacesItsRow() {
        // The rows ride the built-in indexed catalog, so the whole loop works:
        // type the provider's name, get the row, tap to land on its page.
        // "calculator" is no math expression, so the Calculator provider itself
        // stays silent and the settings row is what answers.
        let engine = SearchEngine(providers: [CalculatorProvider(), IndexedProvider.builtIns()])
        #expect(engine.results(for: "calculator").map(\.id).contains("builtin.calculator-page"))
        #expect(engine.results(for: "file search").map(\.id).contains("builtin.file-search-page"))
    }

    @Test("typing a provider name and pressing Enter deeplinks to its page")
    func typedProviderNameDeeplinksFromTheHighlightedRow() {
        // The whole acceptance loop in one move (issue #66 AC #1): the best
        // match for a typed provider name is its Settings command row, and
        // running it produces the panel deeplink the app pushes.
        let engine = SearchEngine(providers: [CalculatorProvider(), IndexedProvider.builtIns()])

        let quicklinks = engine.highlighted(for: "quicklinks")
        #expect(quicklinks?.run() == .openPage(.settings(panel: .quicklinks)))

        let calculator = engine.highlighted(for: "calculator")
        #expect(calculator?.run() == .openPage(.settings(panel: .calculator)))
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
