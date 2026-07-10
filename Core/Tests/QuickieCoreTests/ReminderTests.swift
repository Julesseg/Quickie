import Foundation
import Testing
@testable import QuickieCore

// New Reminder is the first multi-step quick-capture Action (issue #37): it declares
// ordered, typed Arguments and, once collected, resolves to a pure `createReminder`
// outcome the app performs against EventKit. Its steps beyond the pinned Title are the
// user's reorderable **step plan** (issue #145 follow-up): the enabled steps, in order,
// become the breadcrumb. These tests pin the plan-driven Argument declaration, the
// reminder-building rules, and the by-label draft reading — all in the Core, EventKit-free.
struct ReminderTests {

    private let lists = [
        ChoiceOption(id: "personal", label: "Personal"),
        ChoiceOption(id: "work", label: "Work"),
    ]

    @Test("the Title always leads; the enabled steps follow in plan order")
    func titlePinnedThenPlanOrder() {
        // An arbitrary plan order is honoured verbatim after the pinned Title.
        let action = Action.newReminder(steps: [.priority, .dueDate, .notes, .list], lists: lists)
        #expect(action.arguments.map(\.label) == ["Title", "Priority", "Due Date", "Notes", "List"])
        #expect(action.arguments[0].inputMethod == .keyboard(.text))
    }

    @Test("an empty plan collects only the Title")
    func emptyPlanIsTitleOnly() {
        let action = Action.newReminder(steps: [])
        #expect(action.arguments.map(\.label) == ["Title"])
    }

    @Test("the default plan is Due Date then List — today's flow")
    func defaultPlan() {
        let action = Action.newReminder(lists: lists)
        #expect(action.arguments.map(\.label) == ["Title", "Due Date", "List"])
    }

    @Test("collected values resolve to a createReminder outcome with title and chosen list")
    func resolvesToCreateReminder() {
        let action = Action.newReminder(steps: [.list], lists: lists)

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
        // List off → routed to a fixed target, so only title + due date are collected.
        let action = Action.newReminder(steps: [.dueDate], listTarget: "personal")

        let timed = action.run(arguments: [.text("Call mum"), .date(when, hasTime: true)])
        #expect(timed == .createReminder(ReminderDraft(
            title: "Call mum", dueDate: when, hasTime: true, listID: "personal"
        )))

        let dateOnly = action.run(arguments: [.text("Call mum"), .date(when, hasTime: false)])
        #expect(dateOnly == .createReminder(ReminderDraft(
            title: "Call mum", dueDate: when, hasTime: false, listID: "personal"
        )))
    }

    @Test("List off routes to the target; a nil target is the system default list")
    func listOffRoutesToTarget() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        // A nil target (List off, no fixed list) resolves to the system default (nil id).
        let systemDefault = Action.newReminder(steps: [.dueDate], listTarget: nil)
        #expect(systemDefault.run(arguments: [.text("Walk dog"), .date(when, hasTime: false)])
            == .createReminder(ReminderDraft(
                title: "Walk dog", dueDate: when, hasTime: false, listID: nil
            )))
    }

    @Test("the Priority step is a choice input over None/Low/Medium/High")
    func priorityStepIsChoice() {
        let action = Action.newReminder(steps: [.priority])
        let priority = action.arguments.first { $0.label == "Priority" }
        #expect(priority?.inputMethod == .choice([
            ChoiceOption(id: "0", label: "None"),
            ChoiceOption(id: "9", label: "Low"),
            ChoiceOption(id: "5", label: "Medium"),
            ChoiceOption(id: "1", label: "High"),
        ]))
    }

    @Test("collected notes and priority land on the created reminder")
    func notesAndPriorityCollected() {
        let action = Action.newReminder(steps: [.notes, .priority], listTarget: "personal")
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
        // Only Title + Priority, so the two committed values line up with the two steps.
        let action = Action.newReminder(steps: [.priority], listTarget: nil)
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
        let action = Action.newReminder(steps: [.notes], listTarget: nil)
        let outcome = action.run(arguments: [.text("Water plants"), .text("")])
        #expect(outcome == .createReminder(ReminderDraft(
            title: "Water plants", dueDate: nil, hasTime: false, notes: nil, priority: 0, listID: nil
        )))
        #expect(action.arguments.first { $0.label == "Notes" }?.isOptional == true)
    }

    @Test("draft building stays correct with a second text step and a second choice step")
    func robustToTwoTextAndTwoChoiceSteps() {
        // Title + Notes are both text; Priority + List are both choice. By-label reading
        // keeps each on its own value where by-kind reading would collide.
        let action = Action.newReminder(steps: [.notes, .priority, .list], lists: lists)
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
}

// The reminder step plan (issue #145 follow-up): the pure ordering rules and the
// first-run/migration seed that the App's `CaptureStepsStore` is a thin wrapper over.
struct ReminderStepPlanTests {

    @Test("resolving drops unknown raw ids and de-duplicates, order preserved")
    func resolvedReconciles() {
        let steps: [ReminderStep] = CaptureStepPlan.resolved(["list", "bogus", "dueDate", "list"])
        #expect(steps == [.list, .dueDate])
    }

    @Test("the pool is every step not enabled, in canonical order")
    func poolIsCanonicalComplement() {
        let pool = CaptureStepPlan.pool(enabled: [ReminderStep.list])
        // Canonical order is the declaration order: dueDate, notes, priority, (list).
        #expect(pool == [.dueDate, .notes, .priority])
    }

    @Test("the first-run plan is Due Date then List")
    func firstRun() {
        #expect(ReminderStep.firstRun == [.dueDate, .list])
    }

    @Test("migration seeds from the retired due-date toggle and list ask-each-time")
    func migration() {
        // Old defaults (ask-date on, list asks each time) reproduce the first-run plan.
        #expect(ReminderStep.migrated(askDate: true, listAsksEachTime: true) == [.dueDate, .list])
        // Ask-date off drops Due Date; a fixed list (not ask) drops List.
        #expect(ReminderStep.migrated(askDate: false, listAsksEachTime: true) == [.list])
        #expect(ReminderStep.migrated(askDate: true, listAsksEachTime: false) == [.dueDate])
        #expect(ReminderStep.migrated(askDate: false, listAsksEachTime: false) == [])
    }
}
