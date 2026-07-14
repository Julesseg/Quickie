import Foundation

/// The muted relative-age label every [[Pile]] entry wears (CONTEXT.md → Pile,
/// aging paragraph; issue #164): **always shown, as the single coarsest unit** —
/// "2h ago", "4d ago", "3w ago", never a compound "3w 2d". Aging is information,
/// not enforcement (no auto-expiry), so this is purely how an entry's persisted
/// creation date reads in a row's subtitle channel and the page header.
///
/// Pure and clock-free — the app passes `now` (its `Date()`) so the ladder stays
/// deterministic and testable, the same defer-to-the-edge shape the outcomes use.
public enum RelativeAge {
    // The ladder's rungs, coarsest-fitting wins. `m` is minutes, so months read
    // "mo" to stay unambiguous. Weeks run up to the 30-day mark ("4w ago" at 29
    // days), then months (30-day), then years (365-day) — enough to label an
    // entry that, since nothing auto-deletes, may wait indefinitely.
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * minute
    private static let day: TimeInterval = 24 * hour
    private static let week: TimeInterval = 7 * day
    private static let month: TimeInterval = 30 * day
    private static let year: TimeInterval = 365 * day

    /// The coarsest single-unit "…ago" label for an entry created at `created`,
    /// read as of `now`. A non-positive interval — a just-saved entry or a
    /// future `createdAt` from CloudKit clock skew — clamps to "just now" so a
    /// row never shows a negative age.
    public static func label(from created: Date, asOf now: Date) -> String {
        let seconds = now.timeIntervalSince(created)
        guard seconds >= minute else { return "just now" }
        switch seconds {
        case ..<hour:  return "\(Int(seconds / minute))m ago"
        case ..<day:   return "\(Int(seconds / hour))h ago"
        case ..<week:  return "\(Int(seconds / day))d ago"
        case ..<month: return "\(Int(seconds / week))w ago"
        case ..<year:  return "\(Int(seconds / month))mo ago"
        default:       return "\(Int(seconds / year))y ago"
        }
    }
}

/// The Pile **page** header line (CONTEXT.md → Pile; issue #164): the entry count
/// plus the oldest entry's age — and **nothing** for an empty Pile (never
/// "0 saved"). The one place the Pile's size is stated: nothing outside the page
/// advertises it (the Pile command row stays bare, no badge anywhere), so this
/// lives beside the entries it summarizes, not on any chrome.
public enum PileHeader {
    /// The header text, or `nil` when there is nothing to summarize — an empty
    /// Pile (no header, no "0 saved") or, defensively, a positive count with no
    /// oldest date. `oldest` is the creation date of the oldest live entry.
    public static func text(entryCount: Int, oldest: Date?, asOf now: Date) -> String? {
        guard entryCount > 0, let oldest else { return nil }
        return "\(entryCount) saved · oldest \(RelativeAge.label(from: oldest, asOf: now))"
    }
}
