import Foundation
import Testing
@testable import QuickieCore

// The FilenameIndex is the pure, in-memory snapshot File Search matches against
// (CONTEXT.md → File Search; ADR 0015). The app builds it by walking each granted
// Indexed Folder under a security-scoped bracket; the Core only ever sees a plain
// list of entries — filename, relative path, and the owning folder's bookmark
// identity — and never touches the filesystem. These tests pin that it is
// buildable from a list and prefilters cheaply before the expensive scoring pass.
struct FilenameIndexTests {

    private let index = FilenameIndex(entries: [
        FileEntry(bookmarkID: "folder-1", relativePath: "docs/report.pdf", displayName: "report.pdf"),
        FileEntry(bookmarkID: "folder-1", relativePath: "budget.xlsx", displayName: "budget.xlsx"),
        FileEntry(bookmarkID: "folder-2", relativePath: "photos/vacation.jpg", displayName: "vacation.jpg"),
    ])

    @Test("an index is buildable from a plain list of entries")
    func buildableFromEntries() {
        #expect(index.entries.count == 3)
        #expect(index.entries.contains { $0.displayName == "report.pdf" && $0.bookmarkID == "folder-1" })
    }

    @Test("an entry's display name defaults to the relative path's last component")
    func entryDisplayNameDefaults() {
        let entry = FileEntry(bookmarkID: "f", relativePath: "a/b/notes.txt")
        #expect(entry.displayName == "notes.txt")
    }

    @Test("the prefilter drops hopeless candidates before scoring")
    func prefilterDropsHopeless() {
        // A distinctive query shares no trigrams with the budget/photo entries, so
        // the sound gate drops them before the edit-distance pass — only the report
        // (which shares "rep/epo/por/ort") survives to be scored.
        let survivors = index.prefiltered(for: "reportfinal")
        #expect(survivors.map(\.displayName) == ["report.pdf"])
    }

    @Test("the prefilter is sound — it never drops a real match")
    func prefilterKeepsRealMatches() {
        // A prefix of a filename must always survive to the scoring pass.
        let survivors = index.prefiltered(for: "report")
        #expect(survivors.contains { $0.displayName == "report.pdf" })
    }
}
