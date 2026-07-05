import Foundation

/// The launch-time reconciliation rule behind the seeded Custom Action's fixed
/// id (ADR 0023). CloudKit-backed SwiftData cannot enforce uniqueness, so a
/// well-known id (e.g. the seeded web search's `seed.web-search`) is convention
/// plus reconciliation: two devices can each seed before their first CloudKit
/// import lands, and once sync merges the stores every device must collapse the
/// same-id rows to the *same* winner. This type owns the pure rule — which rows
/// to delete — leaving fetching and deleting to the store that calls it.
public enum StoreDedup {
    /// Among rows sharing an id, keeps a deterministic winner and returns the
    /// rest — the rows the caller should delete. Rows whose id is unique are
    /// never returned, so the pass is a cheap no-op when there are no
    /// duplicates.
    public static func duplicatesToDelete<Row>(
        among rows: [Row],
        id: (Row) -> String,
        createdAt: (Row) -> Date,
        tieBreak: (Row) -> String
    ) -> [Row] {
        var byID: [String: [Row]] = [:]
        for row in rows {
            byID[id(row), default: []].append(row)
        }
        return byID.values.filter { $0.count > 1 }.flatMap { group in
            // The winner must not depend on fetch order — no order is a fact
            // every device agrees on. Oldest createdAt wins; equal timestamps
            // fall back to the caller's stable tie-break.
            group.sorted {
                let (a, b) = (createdAt($0), createdAt($1))
                return a != b ? a < b : tieBreak($0) < tieBreak($1)
            }.dropFirst()
        }
    }
}
