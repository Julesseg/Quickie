import Foundation
import Testing
@testable import QuickieCore

// The Search Files context (CONTEXT.md → Search Files context; ADR 0014): a
// scoped, uncapped file-browsing surface entered by *selecting* a "Search Files"
// command row — never a mode toggle. These tests pin the Core seam: the command
// Action that enters the context, and the provider's uncapped context filter
// (distinct from the substring-gated, inline-capped `candidates(for:)`).
struct SearchFilesContextTests {

    @Test("the Search Files command carries the enter-file-search outcome")
    func searchFilesCommandEntersContext() {
        let action = Action.searchFiles()
        #expect(action.kind == .searchFiles)
        #expect(action.run() == .enterFileSearch)
        #expect(action.mainAction == .searchFiles)
        // A command row enters a context rather than producing content, so it wears
        // the neutral `.text` output like every other command — never `.file`, which
        // would read as a source of file-typed output for a future Argument chain.
        #expect(action.outputType == .text)
        #expect(action.inputTypes.isEmpty)
    }

    @Test("the Search Files command matches by name and alias")
    func searchFilesCommandMatchesByName() {
        let action = Action.searchFiles()
        // Typing its name (or the "files" alias) surfaces it like any command row.
        #expect(Matcher.score(query: "search files", candidate: action.title) != nil)
        #expect(action.aliases.contains { Matcher.score(query: "files", candidate: $0) != nil })
    }

    private func provider(_ entries: [FileEntry], inlineCap: Int = 3) -> FileSearchProvider {
        FileSearchProvider(index: FilenameIndex(entries: entries), inlineCap: inlineCap)
    }

    @Test("the context surfaces weak matches the inline path holds back")
    func contextSurfacesWeakMatches() {
        // A scattered subsequence ("rport" through "report.pdf") is below the
        // substring threshold (ADR 0035), so it never surfaces inline — but the
        // uncapped context shows it.
        let p = provider([FileEntry(bookmarkID: "f", relativePath: "report.pdf")])
        #expect(p.candidates(for: "rport").isEmpty)           // inline: held back
        #expect(p.contextMatches(for: "rport").count == 1)    // context: shown
    }

    @Test("the context is uncapped — more than the inline cap can surface")
    func contextIsUncapped() {
        let entries = (1...10).map { FileEntry(bookmarkID: "f", relativePath: "report-\($0).pdf") }
        let p = provider(entries, inlineCap: 3)
        #expect(p.candidates(for: "report").count == 3)       // inline: capped
        #expect(p.contextMatches(for: "report").count == 10)  // context: all of them
    }

    @Test("an empty context query browses every file")
    func emptyContextQueryBrowsesAll() {
        let entries = [
            FileEntry(bookmarkID: "f", relativePath: "b/budget.xlsx"),
            FileEntry(bookmarkID: "f", relativePath: "a/report.pdf"),
        ]
        let names = provider(entries).contextMatches(for: "").map(\.title)
        // Browse-all, ordered by display name so the list reads stably.
        #expect(names == ["budget.xlsx", "report.pdf"])
    }

    @Test("context survivors are ordered best match first and carry openFile")
    func contextOrdersBestFirst() {
        let p = provider([
            FileEntry(bookmarkID: "f", relativePath: "reporting-tool.md"),
            FileEntry(bookmarkID: "f", relativePath: "report.md"),
        ])
        let hits = p.contextMatches(for: "report.md")
        #expect(hits.first?.title == "report.md")             // exact beats prefix
        #expect(hits.first?.run() == .openFile(bookmarkID: "f", relativePath: "report.md"))
    }
}
