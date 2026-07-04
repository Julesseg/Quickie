import Foundation
import Testing
@testable import QuickieCore

// The input method an Argument presents is *derived*, never stored (CONTEXT.md →
// Input method; ADR 0013), so the control can never drift from the declaration.
// These pin the derivation directly on `Argument`, type by type — including the
// numeric keyboard variant a `number` Argument raises (issue #96) — alongside the
// datePicker/choice cases the capture Actions already assert.
struct ArgumentInputMethodTests {

    @Test("free text derives the text keyboard variant")
    func textDerivesTextKeyboard() {
        #expect(Argument(label: "Title", contentType: .text).inputMethod == .keyboard(.text))
    }

    @Test("a number Argument raises the numeric keyboard variant")
    func numberDerivesNumericKeyboard() {
        // The keyboard input method gains a numeric-layout variant (issue #96): a
        // number slot comes up on the system number pad, declaration-driven from the
        // content type like every other input method.
        #expect(Argument(label: "Amount", contentType: .number).inputMethod == .keyboard(.number))
    }

    @Test("a date Argument uses the in-place date picker")
    func dateDerivesDatePicker() {
        #expect(Argument(label: "Due", contentType: .date).inputMethod == .datePicker)
    }

    @Test("a fixed option set is a fuzzy choice regardless of content type")
    func optionsDeriveChoice() {
        let options = [ChoiceOption(id: "a", label: "A"), ChoiceOption(id: "b", label: "B")]
        // Options win over the content type — a choice slot carries `.text` content
        // yet presents the fuzzy list, so a numeric-looking choice never raises a pad.
        #expect(Argument(label: "List", contentType: .text, options: options).inputMethod == .choice(options))
        #expect(Argument(label: "List", contentType: .number, options: options).inputMethod == .choice(options))
    }
}
