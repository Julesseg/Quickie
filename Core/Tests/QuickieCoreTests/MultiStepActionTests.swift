import Foundation
import Testing
@testable import QuickieCore

// MultiStepAction is the reusable breadcrumb engine (issue #37): it drives an
// Action's ordered Arguments one slot at a time, sealing each committed value
// into a pill and advancing, until the final commit resolves to the Action's
// outcome. These tests pin that lifecycle through a synthetic multi-Argument
// Action so the engine stays decoupled from any one capture.
struct MultiStepActionTests {

    /// A three-step Action whose values resolve to a `copyText` of the joined
    /// texts, so the engine's completion carries an observable outcome without any
    /// capture-specific machinery.
    private func sample() -> Action {
        Action(
            id: "sample",
            title: "Sample",
            outputType: .text,
            arguments: [
                Argument(label: "First", contentType: .text),
                Argument(label: "Second", contentType: .text),
                Argument(label: "Third", contentType: .text),
            ],
            effect: { _ in .none },
            multiStepEffect: { values in
                let texts = values.map { value -> String in
                    if case .text(let s) = value { return s }
                    return ""
                }
                return .copyText(texts.joined(separator: " "))
            }
        )
    }

    @Test("a fresh session prompts the first Argument with no pills")
    func startsAtFirstArgument() {
        let action = sample()
        let session = MultiStepAction(action: action)

        #expect(session.actionTitle == "Sample")
        #expect(session.pills.isEmpty)
        #expect(session.current == action.arguments.first)
    }

    @Test("isFinalStep is true only while collecting the last Argument")
    func reportsFinalStep() {
        var session = MultiStepAction(action: sample()) // 3 steps
        #expect(session.isFinalStep == false)
        _ = session.commit(.text("a"))
        #expect(session.isFinalStep == false)
        _ = session.commit(.text("b")) // now collecting the third (last) step
        #expect(session.isFinalStep == true)
    }

    @Test("committing seals a pill and advances to the next Argument")
    func commitAdvances() {
        let action = sample()
        var session = MultiStepAction(action: action)

        let step = session.commit(.text("buy milk"))

        #expect(step == .collecting)
        #expect(session.pills == [.text("buy milk")])
        #expect(session.current == action.arguments[1])
    }

    @Test("committing the final Argument completes with the Action's outcome")
    func finalCommitCompletes() {
        let action = sample()
        var session = MultiStepAction(action: action)

        _ = session.commit(.text("a"))
        _ = session.commit(.text("b"))
        let step = session.commit(.text("c"))

        #expect(step == .completed(.copyText("a b c")))
        #expect(session.current == nil)
    }

    @Test("re-editing an earlier pill updates it in place and keeps the later pills")
    func editPillInPlace() {
        let action = sample()
        var session = MultiStepAction(action: action)
        _ = session.commit(.text("a"))
        _ = session.commit(.text("b"))
        // Collecting the third step; tap the first pill to fix it.
        session.editPill(at: 0)
        #expect(session.current == action.arguments[0])

        let step = session.commit(.text("A"))

        #expect(step == .collecting)
        #expect(session.pills == [.text("A"), .text("b")])
        // Resumed at the first unfilled step, the later pill untouched.
        #expect(session.current == action.arguments[2])
    }

    @Test("backspace on an empty input pops the last pill and returns to that step")
    func backspacePopsLastPill() {
        let action = sample()
        var session = MultiStepAction(action: action)
        _ = session.commit(.text("a"))
        _ = session.commit(.text("b"))

        let step = session.backspaceOnEmpty()

        #expect(step == .collecting)
        #expect(session.pills == [.text("a")])
        #expect(session.current == action.arguments[1])
    }

    @Test("backspace with no pills abandons the capture back to normal search")
    func backspaceWithNoPillsAbandons() {
        var session = MultiStepAction(action: sample())

        #expect(session.backspaceOnEmpty() == .abandoned)
    }

    @Test("steps exposes every Argument from the start with its value and the cursor")
    func stepsShowAllFromStart() {
        let action = sample() // First, Second, Third
        var session = MultiStepAction(action: action)

        // All three crumbs are visible immediately, none filled, the first current.
        #expect(session.steps.map(\.label) == ["First", "Second", "Third"])
        #expect(session.steps.map(\.value) == [nil, nil, nil])
        #expect(session.steps.map(\.isCurrent) == [true, false, false])

        _ = session.commit(.text("a"))

        // The first crumb now carries its value; the cursor has advanced.
        #expect(session.steps.map(\.value) == [.text("a"), nil, nil])
        #expect(session.steps.map(\.isCurrent) == [false, true, false])
    }

    @Test("re-editing marks the tapped step current while the later pills still show")
    func stepsDuringReedit() {
        var session = MultiStepAction(action: sample())
        _ = session.commit(.text("a"))
        _ = session.commit(.text("b")) // collecting the third step
        session.editPill(at: 0)

        #expect(session.steps.map(\.isCurrent) == [true, false, false])
        #expect(session.steps.map(\.value) == [.text("a"), .text("b"), nil])
    }

    @Test("a choice step filters and ranks its options with the matcher")
    func choiceOptionsFilterAndRank() {
        let lists = [
            ChoiceOption(id: "work", label: "Work"),
            ChoiceOption(id: "personal", label: "Personal"),
            ChoiceOption(id: "wishlist", label: "Wishlist"),
        ]
        let action = Action.newReminder(askDate: false, list: .ask, lists: lists)
        var session = MultiStepAction(action: action)
        _ = session.commit(.text("Buy milk")) // now on the list choice step

        // An empty filter shows every option in the supplied order.
        #expect(session.options(matching: "") == lists)

        // Typing filters out non-matches and ranks best-first — "Work" (a tighter
        // prefix) above "Wishlist", and "Personal" excluded entirely.
        #expect(session.options(matching: "w").map(\.id) == ["work", "wishlist"])
    }
}
