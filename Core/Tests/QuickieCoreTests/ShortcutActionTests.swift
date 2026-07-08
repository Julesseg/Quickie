import Foundation
import Testing
@testable import QuickieCore

// A Shortcut Action (CONTEXT.md → Shortcut Action; issue #45) runs one of the
// user's iOS Shortcuts by name. This slice lands only up to "my shortcuts show
// up and are searchable" — actually triggering one is the next slice, so a
// Shortcut Action is deliberately **inert** here. It matches by name like a
// Quicklink or Snippet and is registered solely by the Sync Shortcut import.
struct ShortcutActionTests {

    @Test("a Shortcut Action carries its name and reads as a shortcut")
    func carriesNameAndKind() {
        let action = Action.shortcut(name: "Start Workout")
        #expect(action.title == "Start Workout")
        #expect(action.kind == .shortcut)
    }

    @Test("a Shortcut Action without input fires immediately, carrying its name")
    func firesImmediatelyWithoutInput() {
        // acceptsInput off (the import default): the row runs the shortcut straight
        // away with no input (issue #46). The outcome carries only the name; the app
        // edge turns it into the `shortcuts://x-callback-url/run-shortcut` open.
        let action = Action.shortcut(name: "Start Workout")
        #expect(action.run() == .runShortcut(name: "Start Workout", input: nil))
        // It collects no Arguments, so it never enters the breadcrumb.
        #expect(action.arguments.isEmpty)
    }

    @Test("a no-input Shortcut Action matches by name and is not fallback-eligible")
    func matchesByNameNotEligible() {
        // No accepts-input → no Argument to seed → nowhere for a query to land, so
        // it is not fallback-eligible and never rides the bottom region.
        let action = Action.shortcut(name: "Start Workout")
        #expect(action.isFallbackEligible == false)
        #expect(action.inputTypes.isEmpty)
    }

    @Test("an input-accepting Shortcut Action collects one optional text Argument")
    func acceptsInputDeclaresOneOptionalTextArgument() {
        // With `acceptsInput` on (set on the Shortcuts page in #45), the shortcut
        // declares one **optional** `text` Argument and runs through the breadcrumb
        // (issue #46) — optional so the user can submit it empty and still run the
        // shortcut. That free-text first Argument makes it **fallback-eligible** by
        // shape (issue #114) — it can enter the Fallback list's pool — while still
        // being matched by name and startable verb-first.
        let action = Action.shortcut(name: "Translate", acceptsInput: true)
        #expect(action.arguments.count == 1)
        #expect(action.arguments.first?.contentType == .text)
        #expect(action.arguments.first?.isOptional == true)
        #expect(action.isFallbackEligible == true)
    }

    @Test("an input-accepting Shortcut Action passes the collected value as input")
    func acceptsInputPassesCollectedValue() {
        // The breadcrumb collects the text, then the final commit fires the shortcut
        // with that value as its x-callback input (issue #46).
        let action = Action.shortcut(name: "Translate", acceptsInput: true)
        var run = MultiStepAction(action: action)
        let step = run.commit(.text("bonjour"))
        #expect(step == .completed(.runShortcut(name: "Translate", input: "bonjour")))
    }

    @Test("submitting the optional input empty runs the shortcut with no input")
    func acceptsInputEmptyRunsWithNoInput() {
        // The `text` Argument is optional (issue #46): a user who provides no text
        // still fires the shortcut. An empty submission reads as **no input** (nil),
        // the same as an `acceptsInput`-off shortcut — not an empty-string input.
        let action = Action.shortcut(name: "Translate", acceptsInput: true)
        var run = MultiStepAction(action: action)
        #expect(run.commit(.text("")) == .completed(.runShortcut(name: "Translate", input: nil)))
    }

    @Test("a Shortcut Action declares shortcut content so it can offer Edit")
    func declaresShortcutContent() {
        // The row carries `.shortcut(name:)` content, not the `.none` its run
        // outcome would derive (ADR 0017): the name is what lets the long-press menu
        // add **Edit** — a deeplink into the Shortcuts app's editor.
        let action = Action.shortcut(name: "Start Workout")
        #expect(action.content == .shortcut(name: "Start Workout"))
        #expect(secondaryActions(for: action.content) == [.edit])
    }

    @Test("a Shortcut Action's tap reads as running the shortcut")
    func mainActionReadsAsRunShortcut() {
        // The trailing glyph must signal a hand-off to Shortcuts, for both shapes —
        // read off the real outcome (no input) and off the multi-step outcome (input).
        #expect(Action.shortcut(name: "Timer").mainAction == .runShortcut)
        #expect(Action.shortcut(name: "Translate", acceptsInput: true).mainAction == .runShortcut)
    }

    @Test("a Shortcut Action's id is stable and derived from its name")
    func idIsStableFromName() {
        // Identity is the name (ADR 0007), so the id is derived from it — the same
        // name yields the same id across launches, keeping a pinned Favorite or its
        // Frecency attached. Case-folded so casing drift can't split the identity.
        #expect(Action.shortcut(name: "Start Workout").id == Action.shortcut(name: "start workout").id)
        #expect(Action.shortcut(name: "Timer").id != Action.shortcut(name: "Scan").id)
    }

    @Test("the Shortcuts command deeplinks to the Shortcuts provider page")
    func shortcutsCommandOpensItsPage() {
        // Typed "shortcuts" surfaces the provider's Settings command row
        // (CONTEXT.md → Settings command row; ADR 0019): same id/title/aliases as
        // the old management command, now targeting the unified page in the hub.
        let action = Action.openShortcutsPage()
        #expect(action.title == "Shortcuts")
        #expect(action.kind == .managementPage)
        #expect(action.run() == .openPage(.settings(panel: .shortcuts)))
    }
}
