import Foundation
import Testing
@testable import QuickieCore

// New Reminder is the first multi-step quick-capture Action (issue #37): it
// declares ordered, typed Arguments and, once they are collected, resolves to a
// pure `createReminder` outcome the app layer performs against EventKit. These
// tests pin the Argument declaration, the reminder-building rules (timed vs
// date-only), and the settings that gate which steps appear — all in the Core,
// EventKit-free.
struct ReminderTests {

    private let lists = [
        ChoiceOption(id: "personal", label: "Personal"),
        ChoiceOption(id: "work", label: "Work"),
    ]

    @Test("New Reminder declares title, due date, and list Arguments in order")
    func declaresOrderedTypedArguments() {
        let action = Action.newReminder(askDate: true, list: .ask, lists: lists)

        let args = action.arguments
        #expect(args.map(\.label) == ["Title", "Due Date", "List"])
        // Input method is chosen by content type / option set (ADR 0013): free
        // text uses the keyboard, a date uses the in-place picker, and a fixed
        // option set uses the fuzzy choice list.
        #expect(args[0].inputMethod == .keyboard(.text))
        #expect(args[1].inputMethod == .datePicker)
        #expect(args[2].inputMethod == .choice(lists))
    }

    @Test("collected values resolve to a createReminder outcome with title and chosen list")
    func resolvesToCreateReminder() {
        let action = Action.newReminder(askDate: false, list: .ask, lists: lists)

        let outcome = action.run(arguments: [
            .text("Buy milk"),
            .choice(ChoiceOption(id: "work", label: "Work")),
        ])

        #expect(outcome == .createReminder(ReminderDraft(
            title: "Buy milk", dueDate: nil, hasTime: false, listID: "work"
        )))
    }

    @Test("a timed due date carries an alarm flag; a date-only due date carries none")
    func dueDateAlarmRule() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        // A fixed list skips the list step, so only title + due date are collected.
        let action = Action.newReminder(askDate: true, list: .fixed(id: "personal"))

        let timed = action.run(arguments: [.text("Call mum"), .date(when, hasTime: true)])
        #expect(timed == .createReminder(ReminderDraft(
            title: "Call mum", dueDate: when, hasTime: true, listID: "personal"
        )))

        let dateOnly = action.run(arguments: [.text("Call mum"), .date(when, hasTime: false)])
        #expect(dateOnly == .createReminder(ReminderDraft(
            title: "Call mum", dueDate: when, hasTime: false, listID: "personal"
        )))
    }

    @Test("the opt-in Notes and Priority steps slot in after Due Date, before List")
    func optInStepsInOrder() {
        // All four capture toggles on: Title → Due Date → Notes → Priority → List.
        let action = Action.newReminder(
            askDate: true, askNotes: true, askPriority: true, list: .ask, lists: lists
        )
        #expect(action.arguments.map(\.label) == ["Title", "Due Date", "Notes", "Priority", "List"])
    }

    @Test("the Priority step is a choice input over None/Low/Medium/High")
    func priorityStepIsChoice() {
        let action = Action.newReminder(askPriority: true, list: .fixed(id: nil))
        let priority = action.arguments.first { $0.label == "Priority" }
        // The choice input method (fuzzy list) with the four named levels, in order.
        #expect(priority?.inputMethod == .choice([
            ChoiceOption(id: "0", label: "None"),
            ChoiceOption(id: "9", label: "Low"),
            ChoiceOption(id: "5", label: "Medium"),
            ChoiceOption(id: "1", label: "High"),
        ]))
    }

    @Test("collected notes and priority land on the created reminder")
    func notesAndPriorityCollected() {
        let action = Action.newReminder(
            askDate: false, askNotes: true, askPriority: true, list: .fixed(id: "personal")
        )
        let outcome = action.run(arguments: [
            .text("Submit taxes"),
            .text("Gather receipts first"),
            .choice(ChoiceOption(id: "5", label: "Medium")),
        ])
        #expect(outcome == .createReminder(ReminderDraft(
            title: "Submit taxes",
            dueDate: nil,
            hasTime: false,
            notes: "Gather receipts first",
            priority: 5,
            listID: "personal"
        )))
    }

    @Test("the priority levels map to EventKit's 0/9/5/1 scale")
    func priorityLevelMapping() {
        // Only Title + Priority are collected, so the two committed values line up
        // with the two declared steps (positional/labeled reading).
        let action = Action.newReminder(askDate: false, askPriority: true, list: .fixed(id: nil))
        func priority(picking id: String) -> Int {
            guard case .createReminder(let draft) = action.run(arguments: [
                .text("Task"),
                .choice(ChoiceOption(id: id, label: "")),
            ]) else { return -1 }
            return draft.priority
        }
        #expect(priority(picking: "0") == 0) // None
        #expect(priority(picking: "9") == 9) // Low
        #expect(priority(picking: "5") == 5) // Medium
        #expect(priority(picking: "1") == 1) // High
    }

    @Test("committing an empty notes step writes no notes")
    func emptyNotesWritesNoField() {
        let action = Action.newReminder(askDate: false, askNotes: true, list: .fixed(id: nil))
        // The Notes step is optional, so it can be committed empty — the draft then
        // carries no notes rather than an empty string.
        let outcome = action.run(arguments: [.text("Water plants"), .text("")])
        #expect(outcome == .createReminder(ReminderDraft(
            title: "Water plants", dueDate: nil, hasTime: false, notes: nil, priority: 0, listID: nil
        )))
        // The Notes Argument declares itself optional so the capture can commit it empty.
        #expect(action.arguments.first { $0.label == "Notes" }?.isOptional == true)
    }

    @Test("draft building stays correct with a second text step and a second choice step")
    func robustToTwoTextAndTwoChoiceSteps() {
        // Title + Notes are both text; Priority + List are both choice. By-label
        // reading keeps each on its own value where by-kind reading would collide.
        let action = Action.newReminder(
            askDate: false, askNotes: true, askPriority: true, list: .ask, lists: lists
        )
        let outcome = action.run(arguments: [
            .text("Call plumber"),
            .text("Leaky tap in kitchen"),
            .choice(ChoiceOption(id: "1", label: "High")),
            .choice(ChoiceOption(id: "work", label: "Work")),
        ])
        #expect(outcome == .createReminder(ReminderDraft(
            title: "Call plumber",
            dueDate: nil,
            hasTime: false,
            notes: "Leaky tap in kitchen",
            priority: 1,
            listID: "work"
        )))
    }

    @Test("the default capture flow is byte-for-byte today's — no notes, no priority")
    func defaultFlowUnchanged() {
        // With the new toggles off (their defaults), the breadcrumb and the draft are
        // exactly what they were before issue #145.
        let defaults = Action.newReminder()
        #expect(defaults.arguments.map(\.label) == ["Title", "Due Date"])
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(defaults.run(arguments: [.text("Walk dog"), .date(when, hasTime: false)])
            == .createReminder(ReminderDraft(
                title: "Walk dog", dueDate: when, hasTime: false, notes: nil, priority: 0, listID: nil
            )))
    }

    @Test("settings gate which Arguments are collected and route the skipped list")
    func settingsGateArguments() {
        // ask-date OFF removes the due-date step.
        let noDate = Action.newReminder(askDate: false, list: .ask, lists: lists)
        #expect(noDate.arguments.map(\.label) == ["Title", "List"])

        // The working defaults (ADR 0012): ask-date ON, default list = system
        // default — so the list step is skipped and routed to the system default
        // list (a nil id the app resolves).
        let defaults = Action.newReminder()
        #expect(defaults.arguments.map(\.label) == ["Title", "Due Date"])

        let when = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(defaults.run(arguments: [.text("Walk dog"), .date(when, hasTime: false)])
            == .createReminder(ReminderDraft(
                title: "Walk dog", dueDate: when, hasTime: false, listID: nil
            )))
    }
}
