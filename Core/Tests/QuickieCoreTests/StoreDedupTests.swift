import Foundation
import Testing
@testable import QuickieCore

// CloudKit-backed SwiftData cannot enforce uniqueness, so the seeded web-search
// Custom Action's fixed id is convention plus reconciliation (ADR 0023): two
// devices can each seed before their first CloudKit import lands, and the
// launch-time dedup pass collapses the same-id rows to one deterministic
// winner. These tests pin that reconciliation rule — which rows a store should
// delete — without reaching into how rows are persisted.
struct StoreDedupTests {

    /// A stand-in for a stored row: just the three facts the rule reads.
    private struct Row: Equatable {
        var id: String
        var createdAt: Date
        var tieBreak: String = ""
    }

    private func losers(among rows: [Row]) -> [Row] {
        StoreDedup.duplicatesToDelete(
            among: rows,
            id: \.id,
            createdAt: \.createdAt,
            tieBreak: \.tieBreak
        )
    }

    @Test("distinct ids are left alone — the pass deletes nothing when there are no duplicates")
    func noDuplicatesDeletesNothing() {
        let rows = [
            Row(id: "seed.web-search", createdAt: Date(timeIntervalSinceReferenceDate: 100)),
            Row(id: "custom.things", createdAt: Date(timeIntervalSinceReferenceDate: 200)),
        ]
        #expect(losers(among: rows).isEmpty)
    }

    @Test("rows sharing an id collapse to the oldest — the later seed is the one deleted, whichever order sync delivered them in")
    func oldestCreatedAtWins() {
        let first = Row(id: "seed.web-search", createdAt: Date(timeIntervalSinceReferenceDate: 100))
        let second = Row(id: "seed.web-search", createdAt: Date(timeIntervalSinceReferenceDate: 200))
        // Fetch order isn't a fact either device agrees on, so the rule must
        // pick the same winner regardless of it.
        #expect(losers(among: [first, second]) == [second])
        #expect(losers(among: [second, first]) == [second])
    }

    @Test("equal createdAt falls back to the stable tie-break, so every device still picks the same winner")
    func equalCreatedAtBreaksTieDeterministically() {
        let seededTogether = Date(timeIntervalSinceReferenceDate: 100)
        let kept = Row(id: "seed.web-search", createdAt: seededTogether, tieBreak: "a")
        let dropped = Row(id: "seed.web-search", createdAt: seededTogether, tieBreak: "b")
        #expect(losers(among: [kept, dropped]) == [dropped])
        #expect(losers(among: [dropped, kept]) == [dropped])
    }

    @Test("each id collapses to one survivor independently; rows with unique ids are untouched")
    func groupsCollapseIndependently() {
        let rows = [
            Row(id: "seed.web-search", createdAt: Date(timeIntervalSinceReferenceDate: 300)),
            Row(id: "custom.things", createdAt: Date(timeIntervalSinceReferenceDate: 100)),
            Row(id: "seed.web-search", createdAt: Date(timeIntervalSinceReferenceDate: 100)),
            Row(id: "custom.things", createdAt: Date(timeIntervalSinceReferenceDate: 200)),
            Row(id: "custom.unrelated", createdAt: Date(timeIntervalSinceReferenceDate: 50)),
        ]
        let deleted = losers(among: rows)
        // One loser per duplicated id: the newer web-search seed and the newer
        // things row; the unique row survives untouched.
        #expect(deleted.count == 2)
        #expect(deleted.contains(rows[0]))
        #expect(deleted.contains(rows[3]))
    }
}
