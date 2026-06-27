import Foundation

/// The frequency × recency ranking signal (CONTEXT.md → Frecency): a record of
/// the user's past Action selections that scores each Action by how *often* and
/// how *recently* it was chosen. It feeds two surfaces — the auto-suggested
/// Frecency list on Home, and a ranking boost in Results — both of which only
/// depend on the *ordering* it produces, never on the shape of the decay curve.
///
/// A pure value type: the App records a selection on tap and persists the whole
/// thing (it is `Codable`), so the Core needs no clock or storage of its own —
/// callers pass `now` in, which also keeps scoring deterministic under test.
public struct Frecency: Codable, Sendable, Equatable {

    /// One past selection: which Action, and when. The raw events are kept (not
    /// a running tally) so the decay is recomputed against the *current* `now`
    /// on every query rather than baked in at record time.
    private struct Event: Codable, Sendable, Equatable {
        let id: String
        let at: Date
    }

    private var events: [Event] = []

    /// How long until a single selection's contribution decays to half. Recent
    /// picks dominate, but a long-favored Action still outranks a one-off from
    /// weeks ago — the "× recency" half of frecency. A few days matches a
    /// launcher's rhythm: yesterday's pick still counts, last month's barely.
    private static let halfLife: TimeInterval = 3 * 24 * 60 * 60

    public init() {}

    /// Records that the user selected `id` at time `at` — the App calls this on
    /// every main-action tap (issue #9 AC #2).
    public mutating func record(_ id: String, at: Date) {
        events.append(Event(id: id, at: at))
    }

    /// The frecency score of `id` at time `now` — higher means chosen more often
    /// and/or more recently. `0` when never selected.
    ///
    /// Each selection contributes a weight that halves every `halfLife`, and the
    /// weights sum: this is what blends *frequency* (more selections → more
    /// terms) with *recency* (older selections → smaller terms) into one number.
    /// A selection in the future (clock skew) is clamped to weight 1 rather than
    /// amplified.
    public func score(for id: String, now: Date) -> Double {
        var total: Double = 0
        for event in events where event.id == id {
            let age: TimeInterval = max(0, now.timeIntervalSince(event.at))
            let exponent: Double = -age / Self.halfLife
            total += pow(2.0, exponent)
        }
        return total
    }

    /// The Action ids ordered best-first by frecency at time `now`. Ids never
    /// selected (score 0) are omitted, so the Home Frecency list shows only
    /// genuinely-used Actions.
    public func ranked(now: Date) -> [String] {
        let ids: Set<String> = Set(events.map(\.id))

        var scored: [(id: String, score: Double)] = []
        for id in ids {
            let s: Double = score(for: id, now: now)
            if s > 0 { scored.append((id: id, score: s)) }
        }

        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.id < rhs.id
        }
        return scored.map(\.id)
    }
}
