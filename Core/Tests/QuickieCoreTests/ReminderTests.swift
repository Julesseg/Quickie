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
        #expect(args[0].inputMethod == .keyboard)
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
