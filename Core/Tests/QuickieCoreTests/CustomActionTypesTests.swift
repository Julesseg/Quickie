import Foundation
import Testing
@testable import QuickieCore

// Typed Custom Action arguments (CONTEXT.md → Custom Action; ADR 0021, issue #96):
// per-argument types beyond free text — number, date, choice — carried in the
// sidecar `argumentSpecs` config, never in the plain `{name}` token. These pin the
// type-driven Argument derivation, the serialization each type fills its slot with
// (exercised at the `Action` → `MultiStepAction.commit(...)` → `ActionOutcome`
// seam), the added Save gating, and the flagship Things example running end to end.
struct CustomActionTypesTests {

    /// A wall-clock date built in the current calendar/zone — the same zone the ISO
    /// serializer formats in, so the round-trip is deterministic on any CI machine.
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: - Typed Argument derivation

    @Test("a number-typed slot derives the numeric keyboard variant")
    func numberSlotDerivesNumericKeyboard() {
        let def = CustomActionDefinition(
            name: "Tip", template: "app://tip?amount={amount}",
            argumentSpecs: ["amount": ArgumentSpec(type: .number)]
        )
        #expect(def.arguments.map(\.contentType) == [.number])
        #expect(def.arguments.first?.inputMethod == .keyboard(.number))
    }

    @Test("a date-typed slot derives the in-place date picker")
    func dateSlotDerivesDatePicker() {
        let def = CustomActionDefinition(
            name: "When", template: "app://x?when={when}",
            argumentSpecs: ["when": ArgumentSpec(type: .date)]
        )
        #expect(def.arguments.first?.inputMethod == .datePicker)
    }

    @Test("a choice-typed slot derives the fuzzy option list from its inline options")
    func choiceSlotDerivesChoice() {
        // Options are user-entered strings; id = label (the chosen label fills the slot).
        let def = CustomActionDefinition(
            name: "List", template: "app://x?list={list}",
            argumentSpecs: ["list": ArgumentSpec(type: .choice, options: ["Today", "Inbox"])]
        )
        let expected = [ChoiceOption(id: "Today", label: "Today"), ChoiceOption(id: "Inbox", label: "Inbox")]
        #expect(def.arguments.first?.inputMethod == .choice(expected))
    }

    @Test("blank choice options are ignored in the derived option set")
    func blankChoiceOptionsIgnored() {
        let def = CustomActionDefinition(
            name: "List", template: "app://x?list={list}",
            argumentSpecs: ["list": ArgumentSpec(type: .choice, options: ["Today", "   ", ""])]
        )
        #expect(def.arguments.first?.inputMethod == .choice([ChoiceOption(id: "Today", label: "Today")]))
    }

    // MARK: - Serialization through the fill seam

    @Test("a number value fills its slot as the typed digits")
    func numberSerializes() {
        let action = CustomActionDefinition(
            name: "Tip", template: "app://tip?amount={amount}",
            argumentSpecs: ["amount": ArgumentSpec(type: .number)]
        ).makeAction(id: "tip")!
        var session = MultiStepAction(action: action)
        // The numeric keyboard still commits text; the digits fill the slot verbatim.
        #expect(session.commit(.text("42"))
                == .completed(.openURL(URL(string: "app://tip?amount=42")!)))
    }

    @Test("a choice value fills its slot with the chosen label")
    func choiceSerializes() {
        let action = CustomActionDefinition(
            name: "List", template: "things:///add?list={list}",
            argumentSpecs: ["list": ArgumentSpec(type: .choice, options: ["Today", "Inbox"])]
        ).makeAction(id: "list")!
        var session = MultiStepAction(action: action)
        #expect(session.commit(.choice(ChoiceOption(id: "Today", label: "Today")))
                == .completed(.openURL(URL(string: "things:///add?list=Today")!)))
    }

    @Test("a date value serializes to the ISO default, branched on whether it has a time")
    func dateSerializesISODefaults() {
        // Date-only → yyyy-MM-dd; timed → yyyy-MM-dd'T'HH:mm.
        let dateOnly = CustomActionDefinition(
            name: "Due", template: "app://x?d={d}",
            argumentSpecs: ["d": ArgumentSpec(type: .date)]
        ).makeAction(id: "d")!
        var s1 = MultiStepAction(action: dateOnly)
        #expect(s1.commit(.date(date(2026, 7, 4), hasTime: false))
                == .completed(.openURL(URL(string: "app://x?d=2026-07-04")!)))

        let timed = CustomActionDefinition(
            name: "Due", template: "app://x?d={d}",
            argumentSpecs: ["d": ArgumentSpec(type: .date)]
        ).makeAction(id: "d")!
        var s2 = MultiStepAction(action: timed)
        // The `T` and `:` are query-legal, so they stay literal (not over-encoded).
        #expect(s2.commit(.date(date(2026, 7, 4, 9, 5), hasTime: true))
                == .completed(.openURL(URL(string: "app://x?d=2026-07-04T09:05")!)))
    }

    @Test("a single custom date format replaces the ISO default")
    func dateSerializesCustomFormat() {
        // A timed format (Things' yyyy-MM-dd@HH:mm) serializes a timed value; the `@`
        // and `:` are query-legal, so they stay literal.
        let timedAction = CustomActionDefinition(
            name: "When", template: "things:///add?when={when}",
            argumentSpecs: ["when": ArgumentSpec(type: .date, dateFormat: "yyyy-MM-dd@HH:mm")]
        ).makeAction(id: "when")!
        var timed = MultiStepAction(action: timedAction)
        #expect(timed.commit(.date(date(2026, 7, 4, 14, 30), hasTime: true))
                == .completed(.openURL(URL(string: "things:///add?when=2026-07-04@14:30")!)))

        // A date-only format (a slash is query-legal, so it stays literal).
        let dateOnlyAction = CustomActionDefinition(
            name: "When", template: "things:///add?when={when}",
            argumentSpecs: ["when": ArgumentSpec(type: .date, dateFormat: "dd/MM/yyyy")]
        ).makeAction(id: "when")!
        var dateOnly = MultiStepAction(action: dateOnlyAction)
        #expect(dateOnly.commit(.date(date(2026, 7, 4), hasTime: false))
                == .completed(.openURL(URL(string: "things:///add?when=04/07/2026")!)))
    }

    @Test("a date format's meaning decides whether the slot collects a time")
    func dateFormatMeaningDecidesTimeCollection() {
        // The format is the single source: a time-bearing format makes the slot a
        // datetime (the picker offers a time), a date-only one keeps it date-only, and
        // a blank format defaults to date-only — no separate toggle.
        func timeFlag(_ format: String?) -> Bool? {
            let def = CustomActionDefinition(
                name: "x", template: "app://x?d={d}",
                argumentSpecs: ["d": ArgumentSpec(type: .date, dateFormat: format)]
            )
            return def.arguments.first?.dateIncludesTime
        }
        #expect(timeFlag(nil) == false)                    // blank → date-only
        #expect(timeFlag("yyyy-MM-dd") == false)           // date tokens only
        #expect(timeFlag("dd/MM/yyyy") == false)           // uppercase M is month, not minute
        #expect(timeFlag("yyyy-MM-dd@HH:mm") == true)      // HH:mm → timed
        #expect(timeFlag("yyyy-MM-dd'T'HH:mm") == true)    // quoted T is a literal; HH:mm still counts
        #expect(timeFlag("MMM d, yyyy") == false)          // internal spaces, no time tokens
        // A non-date type never carries the flag.
        let text = CustomActionDefinition(name: "x", template: "app://x?d={d}")
        #expect(text.arguments.first?.dateIncludesTime == nil)
    }

    @Test("a date format is trimmed of edge whitespace before formatting")
    func dateFormatTrimsEdgeWhitespace() {
        // The editor keeps the raw text for typing fidelity, but stray leading/trailing
        // whitespace must never reach DateFormatter and leak a literal space into the
        // filled URL. Internal spaces (a legitimate part of a format) are preserved.
        let action = CustomActionDefinition(
            name: "When", template: "app://x?d={d}",
            argumentSpecs: ["d": ArgumentSpec(type: .date, dateFormat: "  yyyy-MM-dd  ")]
        ).makeAction(id: "d")!
        var s = MultiStepAction(action: action)
        #expect(s.commit(.date(date(2026, 7, 4), hasTime: false))
                == .completed(.openURL(URL(string: "app://x?d=2026-07-04")!)))

        // An all-whitespace format formats to nothing, so it falls back to the ISO
        // default rather than producing a blank date value.
        #expect(ArgumentSpec(type: .date, dateFormat: "   ").outputFormat(hasTime: true)
                == ArgumentSpec.defaultTimedFormat)

        // An internal space is kept — the trim is edge-only.
        #expect(ArgumentSpec(type: .date, dateFormat: " MMM d yyyy ").outputFormat(hasTime: false)
                == "MMM d yyyy")
    }

    // MARK: - Validation additions

    @Test("Save is gated on non-empty options for every choice argument")
    func saveGatedOnChoiceOptions() {
        var def = CustomActionDefinition(
            name: "List", template: "things:///add?list={list}",
            argumentSpecs: ["list": ArgumentSpec(type: .choice, options: [])]
        )
        #expect(!def.choiceOptionsAreValid)
        #expect(!def.isValidForSave)

        def.argumentSpecs["list"] = ArgumentSpec(type: .choice, options: ["Today"])
        #expect(def.choiceOptionsAreValid)
        #expect(def.isValidForSave)
    }

    @Test("a whitespace-only choice option does not satisfy the gate")
    func whitespaceChoiceOptionFailsGate() {
        let def = CustomActionDefinition(
            name: "List", template: "things:///add?list={list}",
            argumentSpecs: ["list": ArgumentSpec(type: .choice, options: ["  ", ""])]
        )
        #expect(!def.choiceOptionsAreValid)
    }

    @Test("a number/date/choice first argument makes it fallback-ineligible")
    func eligibilityGateBitesForTypedFirstArgument() {
        // Eligibility is derived from the first fill-order token's *type* (a choice
        // slot's content type is also .text, so a naive content-type check would miss
        // it). A typed-first Custom Action still *saves* — Save is no longer gated on
        // eligibility (issue #114) — it just doesn't enter the Fallback list's pool.
        for type in [ArgumentType.number, .date, .choice] {
            let def = CustomActionDefinition(
                name: "X", template: "app://x?first={first}",
                argumentSpecs: ["first": ArgumentSpec(type: type, options: ["A"])]
            )
            #expect(!def.isFallbackEligible, "a \(type.rawValue) first argument isn't eligible")
            #expect(def.isValidForSave, "a \(type.rawValue)-first Custom Action still saves")
            #expect(def.makeAction(id: "x")?.isFallbackEligible == false,
                    "the produced Action agrees it isn't eligible")
        }

        // A free-text first argument makes it eligible.
        let text = CustomActionDefinition(name: "X", template: "app://x?first={first}")
        #expect(text.isFallbackEligible)
        #expect(text.makeAction(id: "x")?.isFallbackEligible == true)
    }

    @Test("eligibility reads the fill-order first argument, not the URL's first")
    func eligibilityReadsFillOrder() {
        // URL order is title then when, but the user dragged the date `when` to ask
        // first — so it's ineligible even though the URL's first slot is text.
        var def = CustomActionDefinition(
            name: "X", template: "things:///add?title={title}&when={when}",
            argumentSpecs: ["when": ArgumentSpec(type: .date)]
        )
        #expect(def.isFallbackEligible) // title (text) is first by default
        def.moveArguments(fromOffsets: IndexSet(integer: 1), toOffset: 0) // when leads
        #expect(def.orderedTokenNames == ["when", "title"])
        #expect(!def.isFallbackEligible)
    }

    // MARK: - Spec follows rename and reconciles hard against the template

    @Test("renaming an argument carries its type config to the new token")
    func renameCarriesSpec() {
        var def = CustomActionDefinition(
            name: "X", template: "app://x?d={1}",
            argumentSpecs: ["1": ArgumentSpec(type: .date, dateFormat: "yyyy-MM-dd@HH:mm")]
        )
        def.renameArgument("1", to: "when")
        #expect(def.spec(for: "when") == ArgumentSpec(type: .date, dateFormat: "yyyy-MM-dd@HH:mm"))
        #expect(def.arguments.first?.inputMethod == .datePicker)
    }

    @Test("a spec for a token the template lost is pruned by reconciledSpecs")
    func reconciledSpecsPrunesDeadTokens() {
        var def = CustomActionDefinition(
            name: "X", template: "app://x?a={a}&b={b}",
            argumentSpecs: [
                "a": ArgumentSpec(type: .number),
                "b": ArgumentSpec(type: .choice, options: ["X"]),
            ]
        )
        def.template = "app://x?a={a}" // {b} deleted
        #expect(def.reconciledSpecs.keys.sorted() == ["a"])
    }

    @Test("setArgumentType sets the type by fill-order position, leaving other config intact")
    func setArgumentTypeByPosition() {
        var def = CustomActionDefinition(
            name: "X", template: "app://x?when={when}",
            argumentSpecs: ["when": ArgumentSpec(dateFormat: "yyyy-MM-dd@HH:mm")]
        )
        def.setArgumentType(at: 0, to: .date)
        #expect(def.spec(at: 0) == ArgumentSpec(type: .date, dateFormat: "yyyy-MM-dd@HH:mm"))
    }

    // MARK: - The flagship acceptance example (ADR 0021 / issue #96)

    @Test("the flagship Things example is authorable and runs end to end")
    func flagshipThingsExampleRunsEndToEnd() {
        // things:///add?title={title}&notes={notes}&when={when}&deadline={deadline}&list={list}
        // fill order title → when → deadline → list → notes; `when` a timed date with
        // Things' format, `deadline` a default date, `list` a choice. Its text-first
        // `title` makes it fallback-eligible by shape.
        let def = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}&when={when}&deadline={deadline}&list={list}",
            fillOrder: ["title", "when", "deadline", "list", "notes"],
            argumentSpecs: [
                "when": ArgumentSpec(type: .date, dateFormat: "yyyy-MM-dd@HH:mm"),
                "deadline": ArgumentSpec(type: .date),
                "list": ArgumentSpec(type: .choice, options: ["Today", "Inbox"]),
            ]
        )
        #expect(def.isValidForSave)

        let action = def.makeAction(id: "things")!
        // The breadcrumb asks in fill order, morphing the control per type.
        #expect(action.arguments.map(\.label) == ["title", "when", "deadline", "list", "notes"])
        #expect(action.arguments.map(\.inputMethod) == [
            .keyboard(.text),
            .datePicker,
            .datePicker,
            .choice([ChoiceOption(id: "Today", label: "Today"), ChoiceOption(id: "Inbox", label: "Inbox")]),
            .keyboard(.text),
        ])

        var session = MultiStepAction(action: action)
        #expect(session.commit(.text("Ship v2")) == .collecting)                        // title
        #expect(session.commit(.date(date(2026, 7, 4, 14, 30), hasTime: true)) == .collecting) // when
        #expect(session.commit(.date(date(2026, 7, 10), hasTime: false)) == .collecting)       // deadline
        #expect(session.commit(.choice(ChoiceOption(id: "Today", label: "Today"))) == .collecting) // list
        // notes is the final step — the commit completes with the fully-formed link.
        #expect(session.commit(.text("prep release")) == .completed(.openURL(URL(
            string: "things:///add?title=Ship%20v2&notes=prep%20release&when=2026-07-04@14:30&deadline=2026-07-10&list=Today"
        )!)))
    }
}
