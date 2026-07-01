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

    @Test("a Shortcut Action matches by name and consumes no typed text")
    func matchesByNameNotFallback() {
        let action = Action.shortcut(name: "Start Workout")
        #expect(action.isFallback == false)
        #expect(action.inputTypes.isEmpty)
    }

    @Test("an input-accepting Shortcut Action collects one text Argument")
    func acceptsInputDeclaresOneTextArgument() {
        // With `acceptsInput` on (set on the Shortcuts page in #45), the shortcut
        // declares one `text` Argument and runs through the breadcrumb (issue #46);
        // matched by name, it is still not a Fallback.
        let action = Action.shortcut(name: "Translate", acceptsInput: true)
        #expect(action.arguments.count == 1)
        #expect(action.arguments.first?.contentType == .text)
        #expect(action.isFallback == false)
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

    @Test("its input is optional — committing nothing still runs the shortcut")
    func acceptsInputIsOptional() {
        // The `text` Argument is optional (issue #46): a user who provides no text
        // still fires the shortcut, just with empty input rather than being blocked.
        let action = Action.shortcut(name: "Translate", acceptsInput: true)
        var run = MultiStepAction(action: action)
        #expect(run.commit(.text("")) == .completed(.runShortcut(name: "Translate", input: "")))
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

    @Test("the Shortcuts command opens its own management page, not nested under Settings")
    func shortcutsCommandOpensItsPage() {
        // Typed "shortcuts" surfaces a management command row (CONTEXT.md →
        // Management page) that pushes the dedicated Shortcuts page full-screen.
        let action = Action.openShortcutsPage()
        #expect(action.title == "Shortcuts")
        #expect(action.kind == .managementPage)
        #expect(action.run() == .openPage(.shortcuts))
    }
}
