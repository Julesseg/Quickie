import Foundation
import Testing
@testable import QuickieCore

// A Snippet is saved, reusable text whose *main action* is Copy (CONTEXT.md →
// Snippet): canned replies, an address, a template pasted repeatedly. In the
// core it is just an Action — the one kind of thing in the index — so it
// matches, ranks, and runs through the same loop as every other capability.
// These tests pin the copy-out contract without reaching into how snippets are
// stored.
struct SnippetTests {

    @Test("a snippet's main action copies its body to the clipboard")
    func snippetCopiesBody() {
        let snippet = Action.snippet(
            id: "snip.address",
            title: "Home address",
            body: "221B Baker Street, London"
        )
        #expect(snippet.run() == .copyText("221B Baker Street, London"))
    }

    @Test("a snippet declares text output and consumes no input")
    func snippetTypedContent() {
        let snippet = Action.snippet(
            id: "snip.reply",
            title: "Canned reply",
            body: "Thanks for reaching out — I'll get back to you shortly."
        )
        // Self-contained copy-out: it produces text and ignores the typed
        // query, unlike a placeholder-Quicklink which consumes it.
        #expect(snippet.outputType == .text)
        #expect(snippet.inputTypes.isEmpty)
        #expect(snippet.run(input: "anything the user typed") == .copyText("Thanks for reaching out — I'll get back to you shortly."))
    }

    @Test("a snippet is fuzzy-searchable and surfaces as a ranked result row")
    func snippetIsSearchable() {
        let snippets = IndexedProvider(catalog: [
            .snippet(id: "snip.address", title: "Home address", body: "221B Baker Street"),
            .snippet(id: "snip.iban", title: "Bank IBAN", body: "GB29 NWBK ..."),
        ])
        let engine = SearchEngine(providers: [snippets])

        // A forgiving subsequence query finds the snippet by title and ranks it
        // into the Result list, exactly like any other Action.
        let results = engine.results(for: "addr")
        #expect(results.map(\.id) == ["snip.address"])
    }

    @Test("running a matched snippet copies its body, not its title")
    func matchedSnippetCopiesBody() {
        // The copy-out distinction: a snippet's row is labelled by its title but
        // its main action copies the *body* — label and payload differ.
        let snippets = IndexedProvider(catalog: [
            .snippet(id: "snip.reply", title: "Canned reply", body: "Thanks for reaching out!"),
        ])
        let engine = SearchEngine(providers: [snippets])

        let top = engine.results(for: "reply").first
        #expect(top?.run() == .copyText("Thanks for reaching out!"))
    }
}
