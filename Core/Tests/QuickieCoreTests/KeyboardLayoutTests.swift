import Testing
@testable import QuickieCore

// A KeyboardLayout answers one physical question: are these two keys close
// enough that a thumb could hit one meaning the other? The forgiving matcher
// leans on this to make adjacent-key typos cheap. These tests pin the
// observable adjacency relation, not the table's internal storage, so the
// geometry can be retuned (staggered offsets, extra keys) without rewriting
// the suite.
struct KeyboardLayoutTests {

    @Test("on QWERTY, physically neighboring keys are adjacent")
    func qwertyNeighbors() {
        // Same row and diagonal neighbors of 'g'.
        #expect(KeyboardLayout.qwerty.areAdjacent("g", "h"))
        #expect(KeyboardLayout.qwerty.areAdjacent("g", "f"))
        #expect(KeyboardLayout.qwerty.areAdjacent("g", "t"))
    }

    @Test("on QWERTY, keys on opposite sides of the board are not adjacent")
    func qwertyDistant() {
        #expect(!KeyboardLayout.qwerty.areAdjacent("g", "p"))
        #expect(!KeyboardLayout.qwerty.areAdjacent("q", "m"))
    }

    @Test("a key is not adjacent to itself")
    func notSelfAdjacent() {
        #expect(!KeyboardLayout.qwerty.areAdjacent("g", "g"))
    }

    // The App reads the active keyboard's primary language (a BCP-47 tag like
    // "fr-FR") off UITextInputMode and resolves it to a layout here. The
    // resolution is pure, so it is tested without any UIKit.
    @Test("French resolves to AZERTY")
    func frenchIsAzerty() {
        #expect(KeyboardLayout.forLanguage("fr-FR") == .azerty)
        #expect(KeyboardLayout.forLanguage("fr") == .azerty)
    }

    @Test("German resolves to QWERTZ")
    func germanIsQwertz() {
        #expect(KeyboardLayout.forLanguage("de-DE") == .qwertz)
    }

    @Test("English resolves to QWERTY")
    func englishIsQwerty() {
        #expect(KeyboardLayout.forLanguage("en-US") == .qwerty)
    }

    @Test("an unknown or opaque language falls back to QWERTY")
    func unknownFallsBackToQwerty() {
        // Third-party/opaque keyboards (and languages we don't ship a table
        // for) fall back to QWERTY; the non-adjacency layers still cover them.
        #expect(KeyboardLayout.forLanguage("ja-JP") == .qwerty)
        #expect(KeyboardLayout.forLanguage(nil) == .qwerty)
        #expect(KeyboardLayout.forLanguage("") == .qwerty)
    }
}
