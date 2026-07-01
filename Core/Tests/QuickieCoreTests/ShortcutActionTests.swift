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

    @Test("a Shortcut Action is inert this slice — tapping it does nothing")
    func isInertThisSlice() {
        // Triggering goes through x-callback-url in the next slice; here the row
        // is present and rankable but its main action is a no-op.
        let action = Action.shortcut(name: "Start Workout")
        #expect(action.run() == .none)
        #expect(action.run(input: "ignored") == .none)
        #expect(action.mainAction == .none)
    }

    @Test("a Shortcut Action matches by name and consumes no typed text")
    func matchesByNameNotFallback() {
        let action = Action.shortcut(name: "Start Workout")
        #expect(action.isFallback == false)
        #expect(action.inputTypes.isEmpty)
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
