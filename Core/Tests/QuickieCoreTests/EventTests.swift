import Foundation
import Testing
@testable import QuickieCore

// New Event is the second multi-step quick-capture Action (issue #38), reusing the
// breadcrumb engine #37 introduced. Its steps beyond the pinned Title are the user's
// reorderable **step plan** (issue #145 follow-up). Unlike a reminder it applies the
// timed-vs-all-day duration rule and can hand off to the system event editor. With the
// Start step off the event is all-day today (from an injected clock, so Core stays
// EventKit- and wall-clock-free). These tests pin all of that.
struct EventTests {

    private let calendars = [
        ChoiceOption(id: "home", label: "Home"),
        ChoiceOption(id: "work", label: "Work"),
    ]

    /// A fixed clock for the all-day-today fallback, so tests are deterministic.
    private let now = Date(timeIntervalSince1970: 1_600_000_000)

    @Test("the Title always leads; the enabled steps follow in plan order")
    func titlePinnedThenPlanOrder() {
        let action = Action.newEvent(steps: [.location, .start, .notes, .calendar], calendars: calendars)
        #expect(action.arguments.map(\.label) == ["Title", "Location", "Start", "Notes", "Calendar"])
    }

    @Test("the default plan is Start then Calendar — today's flow")
    func defaultPlan() {
        let action = Action.newEvent(calendars: calendars)
        #expect(action.arguments.map(\.label) == ["Title", "Start", "Calendar"])
    }

    @Test("the Calendar step carries a calendar option symbol for its choice rows")
    func calendarStepCarriesCalendarSymbol() {
        let action = Action.newEvent(steps: [.calendar], calendars: calendars)
        #expect(action.arguments.first { $0.label == "Calendar" }?.optionSymbol == "calendar")
    }

    @Test("collected values resolve to a createEvent outcome with title and chosen calendar")
    func resolvesToCreateEvent() {
        let action = Action.newEvent(steps: [.start, .calendar], calendars: calendars, now: now)
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
        let action = Action.newEvent(steps: [.start], calendarTarget: "home", now: now)

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
            title: "Holiday", start: start, end: start, isAllDay: true, calendarID: "home"
        )))
    }

    @Test("Start off makes the event all-day at the injected clock")
    func startOffIsAllDayToday() {
        // No Start step: only Title collected, the event lands all-day at `now`.
        let action = Action.newEvent(steps: [], calendarTarget: "home", now: now)
        let outcome = action.run(arguments: [.text("Team lunch")])
        #expect(outcome == .createEvent(EventDraft(
            title: "Team lunch", start: now, end: now, isAllDay: true, calendarID: "home"
        )))
    }

    @Test("Calendar off routes to the target; a nil target is the system default")
    func calendarOffRoutesToTarget() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let fixed = Action.newEvent(steps: [.start], calendarTarget: "work", now: now)
        #expect(fixed.run(arguments: [.text("Sync"), .date(start, hasTime: true)])
            == .createEvent(EventDraft(
                title: "Sync",
                start: start,
                end: start.addingTimeInterval(3600),
                isAllDay: false,
                calendarID: "work"
            )))

        let systemDefault = Action.newEvent(steps: [.start], calendarTarget: nil, now: now)
        #expect(systemDefault.run(arguments: [.text("Walk"), .date(start, hasTime: false)])
            == .createEvent(EventDraft(
                title: "Walk", start: start, end: start, isAllDay: true, calendarID: nil
            )))
    }

    @Test("collected location and notes land on the created event")
    func locationAndNotesCollected() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let action = Action.newEvent(steps: [.start, .location, .notes], calendarTarget: "home", now: now)
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
        let action = Action.newEvent(steps: [.start, .location, .notes], calendarTarget: "home", now: now)
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
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let action = Action.newEvent(steps: [.start, .location, .notes, .calendar], calendars: calendars, now: now)
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

    @Test("editor mode hands the same draft to composeEvent instead of creating silently")
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

        let silent = Action.newEvent(steps: [.start], calendarTarget: "home", now: now)
        #expect(silent.run(arguments: values) == .createEvent(draft))

        let editor = Action.newEvent(steps: [.start], calendarTarget: "home", now: now, editor: true)
        #expect(editor.run(arguments: values) == .composeEvent(draft))
    }
}

// The event step plan (issue #145 follow-up): the pure ordering rules and the
// first-run/migration seed the App's `CaptureStepsStore` wraps.
struct EventStepPlanTests {

    @Test("resolving drops unknown raw ids and de-duplicates, order preserved")
    func resolvedReconciles() {
        let steps: [EventStep] = CaptureStepPlan.resolved(["calendar", "bogus", "start", "calendar"])
        #expect(steps == [.calendar, .start])
    }

    @Test("the pool is every step not enabled, in canonical order")
    func poolIsCanonicalComplement() {
        let pool = CaptureStepPlan.pool(enabled: [EventStep.start])
        #expect(pool == [.location, .notes, .calendar])
    }

    @Test("the first-run plan is Start then Calendar")
    func firstRun() {
        #expect(EventStep.firstRun == [.start, .calendar])
    }

    @Test("migration always keeps Start; Calendar follows ask-each-time")
    func migration() {
        #expect(EventStep.migrated(calendarAsksEachTime: true) == [.start, .calendar])
        #expect(EventStep.migrated(calendarAsksEachTime: false) == [.start])
    }
}
