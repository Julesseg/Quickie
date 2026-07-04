import Foundation
import Testing
@testable import QuickieCore

// The **editor seam** of a Custom Action (CONTEXT.md → Custom Action; ADR 0021,
// issue #94): the pure reconciliation and validation the live-mirroring editor
// view-model sits on. Reconciliation turns a URL template + an existing fill
// order into ordered argument rows — mirroring the template *hard* (a vanished
// token drops immediately, no stashing) — and the validation predicate gates
// Save. Both are pure functions on `CustomActionDefinition`, exercised here with
// no SwiftUI so `cd Core && swift test` covers them.
struct CustomActionEditorTests {

    // MARK: - Reconciliation: rows mirror the template, in fill order

    @Test("rows default to URL-appearance order")
    func rowsDefaultToURLOrder() {
        let def = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}"
        )
        #expect(def.rows.map(\.name) == ["title", "notes"])
    }

    @Test("a token added to the URL grows a new row at the end")
    func tokenAddedGrowsARow() {
        var def = CustomActionDefinition(name: "x", template: "app://a?t={title}")
        #expect(def.rows.map(\.name) == ["title"])

        // Typing another slot into the URL mirrors a new row, in URL order.
        def.template = "app://a?t={title}&n={notes}"
        #expect(def.rows.map(\.name) == ["title", "notes"])
    }

    @Test("a token removed from the URL drops its row immediately — no stashing")
    func tokenRemovedDropsItsRow() {
        var def = CustomActionDefinition(name: "x", template: "app://a?t={title}&n={notes}")
        #expect(def.rows.map(\.name) == ["title", "notes"])

        // Deleting the token from the URL drops its row (hard mirror, ADR 0021):
        // nothing is stashed to reappear if the token comes back.
        def.template = "app://a?t={title}"
        #expect(def.rows.map(\.name) == ["title"])
    }

    @Test("a purely numeric token auto-labels until renamed")
    func numericTokenAutoLabels() {
        let def = CustomActionDefinition(name: "x", template: "app://a/{1}/{2}")
        #expect(def.rows.map(\.name) == ["1", "2"])
        #expect(def.rows.map(\.label) == ["Argument 1", "Argument 2"])
    }

    @Test("a name used twice yields one row")
    func duplicateNameYieldsOneRow() {
        let def = CustomActionDefinition(name: "x", template: "app://a/{q}?also={q}")
        #expect(def.rows.map(\.name) == ["q"])
    }

    // MARK: - Fill order: reorder, and its persistence across template edits

    @Test("reordering sets the breadcrumb's asking order, not the URL order")
    func reorderSetsAskingOrder() {
        var def = CustomActionDefinition(name: "x", template: "app://a?t={title}&n={notes}")
        // Drag notes above title: the URL is untouched, but the breadcrumb now asks
        // notes first (the editor states this rule explicitly).
        def.moveArguments(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(def.orderedTokenNames == ["notes", "title"])
        #expect(def.arguments.map(\.label) == ["notes", "title"])
        #expect(def.template == "app://a?t={title}&n={notes}")
    }

    @Test("a reorder persists across later template edits")
    func reorderPersistsAcrossTemplateEdits() {
        var def = CustomActionDefinition(name: "x", template: "app://a?a={a}&b={b}&c={c}")
        // User drags c to the front.
        def.moveArguments(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(def.orderedTokenNames == ["c", "a", "b"])

        // Now edit the URL: drop {b}, add {d}. The surviving reorder holds — c still
        // leads, a keeps its place, b's row drops, d appends in URL order.
        def.template = "app://a?a={a}&c={c}&d={d}"
        #expect(def.orderedTokenNames == ["c", "a", "d"])
    }

    // MARK: - Rename rewrites the URL token

    @Test("renaming an argument rewrites its URL token and keeps the fill-order slot")
    func renameRewritesToken() {
        var def = CustomActionDefinition(name: "x", template: "app://a?t={1}&n={notes}")
        // Reorder first so we can prove the renamed row keeps its fill-order position.
        def.moveArguments(fromOffsets: IndexSet(integer: 1), toOffset: 0) // notes, 1
        #expect(def.orderedTokenNames == ["notes", "1"])

        def.renameArgument("1", to: "title")
        // The URL token is rewritten in place; the row keeps its slot and drops the
        // auto-label for the chosen name.
        #expect(def.template == "app://a?t={title}&n={notes}")
        #expect(def.orderedTokenNames == ["notes", "title"])
        #expect(def.rows.map(\.label) == ["notes", "title"])
    }

    @Test("renaming rewrites every occurrence of a duplicated token")
    func renameRewritesEveryOccurrence() {
        var def = CustomActionDefinition(name: "x", template: "app://a/{q}?also={q}")
        def.renameArgument("q", to: "query")
        #expect(def.template == "app://a/{query}?also={query}")
        #expect(def.rows.map(\.name) == ["query"])
    }

    @Test("renaming onto another live token's name is a no-op — no silent merge")
    func renameCollisionIsRejected() {
        // Renaming `notes` to `title` when `title` is already a live token would merge
        // two arguments into one: the fill would write the first answer into both
        // slots and silently drop the second. Guarded — the rename is a no-op, so the
        // template and rows stay intact (two distinct rows).
        var def = CustomActionDefinition(
            name: "Add", template: "things:///add?title={title}&notes={notes}"
        )
        def.renameArgument("notes", to: "title")
        #expect(def.template == "things:///add?title={title}&notes={notes}")
        #expect(def.orderedTokenNames == ["title", "notes"])
        #expect(def.rows.map(\.name) == ["title", "notes"])
        #expect(def.arguments.count == 2)
    }

    @Test("a duplicated fill order still collapses to one row")
    func duplicatedFillOrderCollapses() {
        // Defensive: even a stored fill order carrying a duplicate (a corrupt or
        // legacy value) reconciles to one row per live token, matching `tokenNames`.
        let def = CustomActionDefinition(
            name: "x", template: "app://a?t={title}", fillOrder: ["title", "title"]
        )
        #expect(def.orderedTokenNames == ["title"])
        #expect(def.rows.map(\.name) == ["title"])
    }

    // MARK: - Provider plumbing (ADR 0019/0021, issue #94)

    @Test("the Custom Actions provider is its own configurable kind")
    func customActionsIsAProvider() {
        #expect(ProviderID.customActions.displayName == "Custom Actions")
        // Its schema leads with the Enabled toggle like every provider (no own options
        // this slice — the editor is where a Custom Action is configured).
        #expect(ProviderID.customActions.settingsSchema.map(\.kind) == [.enabled])
    }

    @Test("typing surfaces a Custom Actions command row that deeplinks to its page")
    func customActionsCommandRowDeeplinks() {
        let ids = IndexedProvider.builtIns().candidates(for: "").map(\.id)
        #expect(ids.contains("builtin.custom-actions-page"))

        let engine = SearchEngine(providers: [IndexedProvider.builtIns()])
        #expect(engine.results(for: "custom actions").map(\.id).contains("builtin.custom-actions-page"))

        #expect(Action.openCustomActionsPage().run() == .openPage(.settings(panel: .customActions)))
    }

    // MARK: - Save validation (the editor is the validator; ADR 0021)

    @Test("a whitespace-only name fails validation")
    func emptyNameIsInvalid() {
        let named = CustomActionDefinition(name: "Add", template: "app://a?t={title}")
        #expect(named.nameIsValid)

        let blank = CustomActionDefinition(name: "   ", template: "app://a?t={title}")
        #expect(!blank.nameIsValid)
        #expect(!blank.isValidForSave)
    }

    @Test("a slot-less URL fails the slot check — redirected toward a Quicklink")
    func slotlessURLHasNoSlot() {
        // A URL with no `{name}` token isn't a Custom Action (it consumes nothing);
        // the editor gently redirects it toward Quicklinks instead of saving it.
        let slotless = CustomActionDefinition(name: "GitHub", template: "https://github.com")
        #expect(!slotless.hasSlot)
        #expect(!slotless.isValidForSave)

        let slotted = CustomActionDefinition(name: "Search", template: "https://x.com/?q={q}")
        #expect(slotted.hasSlot)
    }

    @Test("the URL must parse with a scheme after the slots are probe-filled")
    func urlMustBeSchemedAfterProbe() {
        // Validation substitutes a probe value for each slot, then requires a parseable
        // URL *with a scheme* — so a template that is only a query, or bare text, is
        // rejected even though it carries a slot.
        let schemed = CustomActionDefinition(name: "Things", template: "things:///add?title={title}")
        #expect(schemed.urlIsSchemedAfterProbe)
        #expect(schemed.isValidForSave)

        let noScheme = CustomActionDefinition(name: "Broken", template: "//add?title={title}")
        #expect(!noScheme.urlIsSchemedAfterProbe)
        #expect(!noScheme.isValidForSave)

        let bareText = CustomActionDefinition(name: "Broken", template: "just {title} text")
        #expect(!bareText.urlIsSchemedAfterProbe)
    }

    @Test("the fallback flag is allowed only when the first argument by fill order is free text")
    func fallbackGatedOnFirstArgumentFreeText() {
        // This slice is text-only, so `canBeFallback` is true whenever there is a
        // first argument — but the gate keys off the *fill-order* first argument (not
        // the URL's), so it stays correct once argument types land. A slot-less URL
        // has no first argument, so it can't be a fallback.
        let text = CustomActionDefinition(name: "Search", template: "https://x.com/?q={q}")
        #expect(text.canBeFallback)

        let slotless = CustomActionDefinition(name: "Static", template: "https://x.com")
        #expect(!slotless.canBeFallback)

        // A fallback-flagged, otherwise-valid Custom Action saves; the flag rides
        // through validation because its first fill-order argument is free text.
        let fallback = CustomActionDefinition(
            name: "Search", template: "https://x.com/?q={q}", isFallback: true
        )
        #expect(fallback.isValidForSave)
    }
}
