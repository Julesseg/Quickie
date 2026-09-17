import Testing
@testable import QuickieCore

// The Custom Action URL field's single-line rule: the field wraps (vertical axis)
// but a template never holds a line break, so Return and multi-line pastes are
// stripped, with the caret kept where the user was typing.
struct SingleLineTextTests {

    @Test("text without a line break needs no adjustment")
    func noBreakPassesThrough() {
        #expect(SingleLineText.adjusted(replacing: "app://x", with: "app://x?") == nil)
    }

    @Test("Return at the end is dropped, caret stays at the end")
    func trailingReturnDropped() {
        #expect(
            SingleLineText.adjusted(replacing: "app://x", with: "app://x\n")
                == BraceAutoClose.Adjustment(text: "app://x", caretOffset: 7)
        )
        #expect(SingleLineText.isReturnKeypress(replacing: "app://x", with: "app://x\n"))
    }

    @Test("Return mid-text is dropped, caret stays where it was typed")
    func midTextReturnDropped() {
        #expect(
            SingleLineText.adjusted(replacing: "app://xy", with: "app://x\ny")
                == BraceAutoClose.Adjustment(text: "app://xy", caretOffset: 7)
        )
        #expect(SingleLineText.isReturnKeypress(replacing: "app://xy", with: "app://x\ny"))
    }

    @Test("a multi-line paste is joined, caret past the pasted text")
    func multiLinePasteJoined() {
        let adjustment = SingleLineText.adjusted(replacing: "a?q=", with: "a?q=one\ntwo\r\nthree")
        #expect(adjustment == BraceAutoClose.Adjustment(text: "a?q=onetwothree", caretOffset: 15))
        #expect(!SingleLineText.isReturnKeypress(replacing: "a?q=", with: "a?q=one\ntwo\r\nthree"))
    }

    @Test("a replacement that isn't an insertion is stripped with the caret at the end")
    func replacementStripped() {
        #expect(
            SingleLineText.adjusted(replacing: "old", with: "new\nvalue")
                == BraceAutoClose.Adjustment(text: "newvalue", caretOffset: 8)
        )
        #expect(!SingleLineText.isReturnKeypress(replacing: "old", with: "new\nvalue"))
    }
}
