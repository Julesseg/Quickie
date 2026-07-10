import Foundation
import Testing
@testable import QuickieCore

// New Event is the second multi-step quick-capture Action (issue #38), reusing the
// breadcrumb engine #37 introduced. Like New Reminder it declares ordered, typed
// Arguments and resolves to a pure outcome the app performs against EventKit — but
// it collects a **required** start, applies the timed-vs-all-day duration rule, and
// can hand off to the system event editor instead of writing silently. These tests
// pin the Argument declaration, the event-building rules, the calendar-step gating,
// and the silent-vs-editor outcome split — all in the Core, EventKit-free.
struct EventTests {

    private let calendars = [
        ChoiceOption(id: "home", label: "Home"),
        ChoiceOption(id: "work", label: "Work"),
    ]

    @Test("New Event declares title, start, and calendar Arguments in order")
    func declaresOrderedTypedArguments() {
        let action = Action.newEvent(calendar: .ask, calendars: calendars)

        let args = action.arguments
        #expect(args.map(\.label) == ["Title", "Start", "Calendar"])
        // Input method is chosen by content type / option set (ADR 0013): free text
        // uses the keyboard, the start uses the in-place date picker, and the fixed
        // calendar set uses the fuzzy choice list.
        #expect(args[0].inputMethod == .keyboard(.text))
        #expect(args[1].inputMethod == .datePicker)
        #expect(args[2].inputMethod == .choice(calendars))
    }

    @Test("the Calendar step carries a calendar option symbol for its choice rows")
    func calendarStepCarriesCalendarSymbol() {
        let action = Action.newEvent(calendar: .ask, calendars: calendars)
        // The choice step declares the glyph each option row shows, so the app
        // renders calendars with a calendar — not the reminder list's bullet.
        #expect(action.arguments[2].optionSymbol == "calendar")
    }

    @Test("collected values resolve to a createEvent outcome with title and chosen calendar")
    func resolvesToCreateEvent() {
        let action = Action.newEvent(calendar: .ask, calendars: calendars)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let outcome = action.run(arguments: [
            .text("Standup"),
            .date(start, hasTime: true),
            .choice(ChoiceOption(id: "work", label: "Work")),
        ])

        #expect(outcome == .createEvent(EventDraft(
            title: "Standup",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            calendarID: "work"
        )))
    }

    @Test("a timed start gets a one-hour duration; a date-only start becomes all-day")
    func durationRule() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // A fixed calendar skips the calendar step, so only title + start are collected.
        let action = Action.newEvent(calendar: .fixed(id: "home"))

        let timed = action.run(arguments: [.text("Lunch"), .date(start, hasTime: true)])
        #expect(timed == .createEvent(EventDraft(
            title: "Lunch",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            calendarID: "home"
        )))

        let allDay = action.run(arguments: [.text("Holiday"), .date(start, hasTime: false)])
        #expect(allDay == .createEvent(EventDraft(
            title: "Holiday",
            start: start,
            end: start,
            isAllDay: true,
            calendarID: "home"
        )))
    }

    @Test("the opt-in Location and Notes steps slot in after Start, before Calendar")
    func optInStepsInOrder() {
        // Both step toggles on with an ask-calendar: Title → Start → Location → Notes → Calendar.
        let action = Action.newEvent(
            calendar: .ask, calendars: calendars, askLocation: true, askNotes: true
        )
        #expect(action.arguments.map(\.label) == ["Title", "Start", "Location", "Notes", "Calendar"])
        // Both new steps are free text, committable empty to skip them per event.
        #expect(action.arguments.first { $0.label == "Location" }?.isOptional == true)
        #expect(action.arguments.first { $0.label == "Notes" }?.isOptional == true)
    }

    @Test("collected location and notes land on the created event")
    func locationAndNotesCollected() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let action = Action.newEvent(
            calendar: .fixed(id: "home"), askLocation: true, askNotes: true
        )
        let outcome = action.run(arguments: [
            .text("Dentist"),
            .date(start, hasTime: true),
            .text("12 Main St"),
            .text("Bring insurance card"),
        ])
        #expect(outcome == .createEvent(EventDraft(
            title: "Dentist",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            location: "12 Main St",
            notes: "Bring insurance card",
            calendarID: "home"
        )))
    }

    @Test("committing an empty location or notes step writes no field")
    func emptyTextStepsWriteNoField() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let action = Action.newEvent(
            calendar: .fixed(id: "home"), askLocation: true, askNotes: true
        )
        let outcome = action.run(arguments: [
            .text("Focus block"),
            .date(start, hasTime: true),
            .text(""),
            .text(""),
        ])
        #expect(outcome == .createEvent(EventDraft(
            title: "Focus block",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            location: nil,
            notes: nil,
            calendarID: "home"
        )))
    }

    @Test("draft building stays correct with a location, a notes, and a calendar step")
    func robustToTwoTextStepsPlusChoice() {
        // Location + Notes are both text; the by-label reader keeps each on its own
        // value, and the Calendar choice still resolves where by-kind reading would
        // have handed the first text value to the title regardless of position.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let action = Action.newEvent(
            calendar: .ask, calendars: calendars, askLocation: true, askNotes: true
        )
        let outcome = action.run(arguments: [
            .text("Team offsite"),
            .date(start, hasTime: true),
            .text("Rooftop"),
            .text("Agenda in the deck"),
            .choice(ChoiceOption(id: "work", label: "Work")),
        ])
        #expect(outcome == .createEvent(EventDraft(
            title: "Team offsite",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            location: "Rooftop",
            notes: "Agenda in the deck",
            calendarID: "work"
        )))
    }

    @Test("editor mode carries the collected location and notes into composeEvent")
    func editorCarriesLocationAndNotes() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let action = Action.newEvent(
            calendar: .fixed(id: "home"), askLocation: true, askNotes: true, editor: true
        )
        let outcome = action.run(arguments: [
            .text("1:1"),
            .date(start, hasTime: true),
            .text("Coffee shop"),
            .text("Career chat"),
        ])
        #expect(outcome == .composeEvent(EventDraft(
            title: "1:1",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            location: "Coffee shop",
            notes: "Career chat",
            calendarID: "home"
        )))
    }

    @Test("the calendar setting gates the Calendar step and routes the skipped calendar")
    func calendarSettingGatesStep() {
        // ask-every-time keeps the three-step breadcrumb.
        let asked = Action.newEvent(calendar: .ask, calendars: calendars)
        #expect(asked.arguments.map(\.label) == ["Title", "Start", "Calendar"])

        // A fixed default calendar drops the calendar step and routes every event to it.
        let fixed = Action.newEvent(calendar: .fixed(id: "work"))
        #expect(fixed.arguments.map(\.label) == ["Title", "Start"])
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(fixed.run(arguments: [.text("Sync"), .date(start, hasTime: true)])
            == .createEvent(EventDraft(
                title: "Sync",
                start: start,
                end: start.addingTimeInterval(3600),
                isAllDay: false,
                calendarID: "work"
            )))

        // The working default (ADR 0012): a fixed system-default calendar (nil id
        // the app resolves), so the calendar step is skipped with no preset id.
        let defaults = Action.newEvent()
        #expect(defaults.arguments.map(\.label) == ["Title", "Start"])
        #expect(defaults.run(arguments: [.text("Walk"), .date(start, hasTime: false)])
            == .createEvent(EventDraft(
                title: "Walk", start: start, end: start, isAllDay: true, calendarID: nil
            )))
    }

    @Test("the editor setting hands the same draft to composeEvent instead of creating silently")
    func editorSettingComposesInstead() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let values: [ArgumentValue] = [.text("Review"), .date(start, hasTime: true)]
        let draft = EventDraft(
            title: "Review",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            calendarID: "home"
        )

        // Silent (the default) writes directly.
        let silent = Action.newEvent(calendar: .fixed(id: "home"))
        #expect(silent.run(arguments: values) == .createEvent(draft))

        // Editor mode collects the identical breadcrumb but routes to the system
        // event editor for final review, carrying the same draft.
        let editor = Action.newEvent(calendar: .fixed(id: "home"), editor: true)
        #expect(editor.run(arguments: values) == .composeEvent(draft))
    }
}
