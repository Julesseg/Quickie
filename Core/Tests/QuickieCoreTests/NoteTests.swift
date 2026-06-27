import Foundation
import Testing
@testable import QuickieCore

// A Note is a captured free-text thought whose *main action* is Open/read
// (CONTEXT.md → Note): the brain-dump target. Like every capability it is just
// an Action in the index, so it matches, ranks, and runs through the same loop.
// What sets it apart from a Snippet is the outcome of running it: a Note opens
// for reading, a Snippet copies out. These tests pin the read contract — and
// the instant, silent "New Note" capture — without reaching into how notes are
// stored.
struct NoteTests {

    @Test("a note's main action opens it for reading")
    func noteOpensForReading() {
        let note = Action.note(id: "note.groceries", title: "Groceries")
        #expect(note.run() == .openNote(id: "note.groceries"))
    }

    @Test("a note declares text output and consumes no input")
    func noteTypedContent() {
        let note = Action.note(id: "note.ideas", title: "App ideas")
        // Self-contained read: it produces text and ignores the typed query,
        // unlike the "New Note" capture which consumes it.
        #expect(note.outputType == .text)
        #expect(note.inputTypes.isEmpty)
        #expect(note.run(input: "anything the user typed") == .openNote(id: "note.ideas"))
    }

    @Test("a note is fuzzy-searchable and surfaces as a ranked result row")
    func noteIsSearchable() {
        let notes = IndexedProvider(catalog: [
            .note(id: "note.groceries", title: "Groceries"),
            .note(id: "note.standup", title: "Standup talking points"),
        ])
        let engine = SearchEngine(providers: [notes])

        // A forgiving subsequence query finds the note by title and ranks it
        // into the Result list, exactly like any other Action.
        let results = engine.results(for: "groc")
        #expect(results.map(\.id) == ["note.groceries"])
        // Its main action is the read, surfaced through the same loop.
        #expect(results.first?.run() == .openNote(id: "note.groceries"))
    }

    @Test("a note reads while a snippet copies — same storage, opposite main action")
    func noteIsDistinctFromSnippet() {
        // The defining contrast (CONTEXT.md → Note vs Snippet): give both the
        // same human-facing title and the difference is entirely in the outcome.
        let note = Action.note(id: "shared.title", title: "Meeting")
        let snippet = Action.snippet(id: "shared.title", title: "Meeting", body: "Room 4, 3pm")

        #expect(note.run() == .openNote(id: "shared.title"))
        #expect(snippet.run() == .copyText("Room 4, 3pm"))
        #expect(note.run() != snippet.run())
    }

    @Test("the New Note Fallback captures the raw typed text as a new note")
    func newNoteCapturesTypedText() {
        let capture = Action.newNote()
        // A Fallback-style capture (CONTEXT.md → Fallback Action): it is flagged
        // a Fallback, consumes text, and produces text. Running it emits the
        // instant, silent capture the app turns into a stored Note — no app
        // switch, the typed text becomes the note's body.
        #expect(capture.isFallback)
        #expect(capture.inputTypes == [.text])
        #expect(capture.outputType == .text)
        #expect(capture.run(input: "remember to call the dentist")
                == .createNote("remember to call the dentist"))
    }

    // An engine wired like the app: stored notes feeding the index plus the
    // always-present "New Note" capture and the web-search Fallback.
    private func engine() -> SearchEngine {
        SearchEngine(providers: [
            IndexedProvider(catalog: [
                .note(id: "note.groceries", title: "Groceries"),
                .note(id: "note.standup", title: "Standup talking points"),
            ]),
            IndexedProvider(catalog: [.newNote(), .webSearch()]),
        ])
    }

    @Test("the New Note capture rides the bottom region below name-matched notes")
    func newNotePinnedBelowMatches() {
        // "groc" name-matches the Groceries note; the New Note capture still
        // rides along, pinned in the bottom fallback region with web-search.
        let ids = engine().results(for: "groc").map(\.id)
        #expect(ids.first == "note.groceries")
        #expect(ids.contains("builtin.new-note"))
        // Fallbacks sit below every name-match — never above the matched note.
        #expect(ids.firstIndex(of: "builtin.new-note")! > ids.firstIndex(of: "note.groceries")!)
    }

    @Test("the New Note capture is present even when nothing matches by name")
    func newNoteAppearsForNonMatchingQuery() {
        // Pure brain-dump text matches no note title; only the Fallbacks serve
        // it, so a brand-new thought can always be captured.
        let ids = engine().results(for: "buy a birthday gift for mum").map(\.id)
        #expect(ids.contains("builtin.new-note"))
    }

    @Test("an empty query surfaces no New Note capture (Home state)")
    func emptyQueryHasNoCapture() {
        #expect(engine().results(for: "").isEmpty)
        #expect(engine().results(for: "   ").isEmpty)
    }
}
