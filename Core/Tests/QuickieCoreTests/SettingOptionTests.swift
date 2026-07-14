import Foundation
import Testing
@testable import QuickieCore

// The declared settings schema (ADR 0020; issue #69): each Provider declares its
// Options as typed `SettingOption`s in Core, and the app renders any schema
// generically. These tests pin the schema — the shapes the renderer relies on and
// the per-provider declarations — through the public `SettingOption` surface, never
// the SwiftUI page that draws it. The point of ADR 0020 is that panel structure,
// defaults, and enablement live here and are covered by `swift test`.
struct SettingOptionTests {

    @Test("every provider's schema leads with its Enabled toggle")
    func schemaLeadsWithEnabled() {
        // The provider-level Enabled switch (issue #67) becomes the schema's first
        // entry (ADR 0020), so the generic renderer never special-cases where it
        // goes: it is always row one, for every provider.
        for provider in ProviderID.allCases {
            let first = provider.settingsSchema.first
            #expect(first?.key == SettingOption.enabledKey)
            #expect(first?.kind == .enabled)
            #expect(first?.title == "Enabled")
        }
    }

    @Test("the Events schema declares its default-calendar choice and editor toggle")
    func eventsSchemaDeclaresOptions() {
        // The capture *steps* now live in the reorderable double-list on the page (issue
        // #145 follow-up), not the schema. The schema keeps the default-calendar choice
        // (where an event lands when the Calendar step is off) and the editor toggle.
        let schema = ProviderID.events.settingsSchema
        let keys = schema.map(\.key)
        #expect(keys.contains(SettingsKey.eventCalendar))
        #expect(keys.contains(SettingsKey.eventEditor))

        guard case .choice(let calendar)? = schema.first(where: { $0.key == SettingsKey.eventCalendar })?.kind else {
            Issue.record("the calendar option should be a choice"); return
        }
        #expect(calendar.source == .dynamic(.eventCalendars))
        // No "Ask each time" row: asking is expressed by enabling the Calendar step in
        // the double-list. The choice is only the default target, leading with it.
        #expect(calendar.leadingOptions.map(\.id) == [""])
        #expect(calendar.leadingOptions.map(\.label) == ["Default calendar"])

        let editor = schema.first { $0.key == SettingsKey.eventEditor }
        #expect(editor?.kind == .toggle(default: false))
    }

    @Test("the Reminders schema declares only its default-list choice")
    func remindersSchemaDeclaresOptions() {
        // Like Events, the steps moved to the double-list; the schema keeps just the
        // default-list choice (the target when the List step is off).
        let schema = ProviderID.reminders.settingsSchema
        let keys = schema.map(\.key)
        #expect(keys.contains(SettingsKey.reminderList))

        guard case .choice(let list)? = schema.first(where: { $0.key == SettingsKey.reminderList })?.kind else {
            Issue.record("the list option should be a choice"); return
        }
        #expect(list.source == .dynamic(.reminderLists))
        #expect(list.leadingOptions.map(\.id) == [""])
        #expect(list.leadingOptions.map(\.label) == ["Default list"])
    }

    @Test("the reorderable step plan drives the breadcrumb, not schema toggles")
    func stepPlanResolvesAndPools() {
        // The step universe is a fixed enum; the plan is the enabled, ordered subset,
        // and the pool its canonical-order complement (issue #145 follow-up).
        let reminder: [ReminderStep] = CaptureStepPlan.resolved(["priority", "dueDate"])
        #expect(reminder == [.priority, .dueDate])
        #expect(CaptureStepPlan.pool(enabled: reminder) == [.notes, .list])

        let event: [EventStep] = CaptureStepPlan.resolved(["calendar"])
        #expect(event == [.calendar])
        #expect(CaptureStepPlan.pool(enabled: event) == [.start, .location, .notes])
    }

    @Test("the Computed schema ships the Enabled toggle plus five per-type toggles, all default-on")
    func computedSchemaShipsFivePerTypeToggles() {
        // The Computed provider's options section (ADR 0032): the provider-level
        // Enabled toggle first, then Math, Unit conversion, URLs, Phone numbers, and
        // Email addresses — every one a schema-declared toggle defaulting on, so all
        // detection off restores the pre-detection Calculator exactly.
        let schema = ProviderID.calculator.settingsSchema
        #expect(schema.first?.kind == .enabled)

        let perType = [
            SettingsKey.calculatorMath,
            SettingsKey.calculatorUnitConversion,
            SettingsKey.calculatorURL,
            SettingsKey.calculatorPhone,
            SettingsKey.calculatorEmail,
        ]
        // Present, in order, right after Enabled.
        #expect(schema.dropFirst().map(\.key) == perType)
        for key in perType {
            #expect(schema.first { $0.key == key }?.kind == .toggle(default: true))
        }
    }

    @Test("the File Search schema ships an inline-cap stepper with sane bounds")
    func fileSearchSchemaShipsInlineCapStepper() {
        // The second extensibility proof (issue #69 AC #4): a stepper, the third
        // option type, driving File Search's inline row cap (default ~3, ADR 0015).
        let stepper = ProviderID.fileSearch.settingsSchema
            .first { $0.key == SettingsKey.fileSearchInlineCap }
        guard case .stepper(let setting) = stepper?.kind else {
            Issue.record("File Search should declare an inline-cap stepper")
            return
        }
        #expect(setting.defaultValue == 3)
        #expect(setting.range.lowerBound >= 1)
        #expect(setting.range.contains(setting.defaultValue))
    }

    @Test("migrating the retired ask/default settings preserves the old routing")
    func migrationPreservesOldRouting() {
        // The upgrade path (issue #69 review): the old `askCalendar`/`askList` +
        // `defaultID` pair seeds the new single dynamic-choice value so a "save
        // silently" capture survives — the reviewer's formula, corrected for the
        // ask-off + empty-default state (the only one the old UI could reach), which
        // must land on the system-default sentinel, not "" (which would revert to ask).
        #expect(SettingsChoice.migratedSelection(ask: true, defaultID: "") == "")
        #expect(SettingsChoice.migratedSelection(ask: true, defaultID: "cal-x") == "")
        #expect(SettingsChoice.migratedSelection(ask: false, defaultID: "") == SettingsChoice.systemDefault)
        #expect(SettingsChoice.migratedSelection(ask: false, defaultID: "cal-x") == "cal-x")

        // …and the migrated value round-trips back through the routing mapping to the
        // exact `EventCalendarSelection` the old settings produced.
        #expect(EventCalendarSelection(stored: SettingsChoice.migratedSelection(ask: true, defaultID: "")) == .ask)
        #expect(EventCalendarSelection(stored: SettingsChoice.migratedSelection(ask: false, defaultID: "")) == .fixed(id: nil))
        #expect(EventCalendarSelection(stored: SettingsChoice.migratedSelection(ask: false, defaultID: "cal-x")) == .fixed(id: "cal-x"))
    }

    @Test("the bespoke escape hatch ships but no schema uses it")
    func escapeHatchExistsButIsUnused() {
        // ADR 0020's rule — "schema unless no case fits": the bespoke sub-view hatch
        // is the deliberate pressure valve, present in the type but unused today so
        // it never becomes a bespoke-view dumping ground. The live EventKit pickers
        // are a `dynamic choice`, not the hatch, so nothing ships needing it.
        for provider in ProviderID.allCases {
            for option in provider.settingsSchema {
                if case .bespoke = option.kind {
                    Issue.record("\(provider) uses the bespoke hatch; the rule is schema-first")
                }
            }
        }
        // It nonetheless exists for the exotic panel a future provider might need.
        let hatch = SettingOption(key: "x", title: "X", kind: .bespoke(identifier: "custom"))
        #expect(hatch.kind == .bespoke(identifier: "custom"))
    }

    @Test("the calendar dynamic choice's stored value maps to the capture's routing")
    func calendarStoredValueMapsToSelection() {
        // The migration's connective tissue (issue #69): the dynamic choice persists
        // one string, and the capture reads it back as its routing. Empty is the
        // "Ask each time" sentinel (`.ask`); any other value is a fixed calendar.
        #expect(EventCalendarSelection(stored: "") == .ask)
        #expect(EventCalendarSelection(stored: "cal-work") == .fixed(id: "cal-work"))
        // The system-default sentinel routes silently to the system default calendar
        // (`.fixed(id: nil)`) — the state the old "ask off" setting expressed, which
        // the migration seeds so an upgrade never silently flips it back to ask.
        #expect(EventCalendarSelection(stored: SettingsChoice.systemDefault) == .fixed(id: nil))
        // Reminders route the same way over their list picker.
        #expect(ReminderListSelection(stored: "") == .ask)
        #expect(ReminderListSelection(stored: "list-errands") == .fixed(id: "list-errands"))
        #expect(ReminderListSelection(stored: SettingsChoice.systemDefault) == .fixed(id: nil))
    }

    @Test("a stepper clamps a stored value into its range")
    func stepperClampsIntoRange() {
        // The renderer and the provider both read a persisted cap through `clamped`,
        // so a stale or out-of-bounds store can never drive File Search past bounds.
        let setting = StepperSetting(range: 1...5, defaultValue: 3)
        #expect(setting.clamped(0) == 1)
        #expect(setting.clamped(9) == 5)
        #expect(setting.clamped(4) == 4)
    }
}
