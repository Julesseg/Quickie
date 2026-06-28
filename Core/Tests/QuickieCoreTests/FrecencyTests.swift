import Foundation
import Testing
@testable import QuickieCore

// Frecency is the frequency × recency signal (CONTEXT.md → Frecency): it records
// the user's past Action selections and ranks ids by how often and how recently
// they were chosen. These tests read as the spec for that signal — they fix the
// *ordering* behavior the Home list and the ranking boost depend on, never the
// arithmetic of the decay curve.
struct FrecencyTests {

    @Test("a recorded selection surfaces in the ranking")
    func recordsASelection() {
        var frecency = Frecency()
        frecency.record("github", at: Date())
        #expect(frecency.ranked(now: Date()).contains("github"))
    }

    @Test("a never-selected Action is absent and scores zero")
    func unseenIsAbsent() {
        let frecency = Frecency()
        #expect(frecency.score(for: "unseen", now: Date()) == 0)
        #expect(frecency.ranked(now: Date()).isEmpty)
    }

    @Test("more selections rank an Action higher (frequency)")
    func frequencyRanksHigher() {
        let now = Date()
        var frecency = Frecency()
        frecency.record("often", at: now)
        frecency.record("often", at: now)
        frecency.record("once", at: now)
        #expect(frecency.ranked(now: now) == ["often", "once"])
    }

    @Test("a more recent selection ranks higher than an older one (recency)")
    func recencyRanksHigher() {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        var frecency = Frecency()
        frecency.record("stale", at: weekAgo)
        frecency.record("fresh", at: now)
        #expect(frecency.ranked(now: now) == ["fresh", "stale"])
    }

    @Test("sustained use outranks a single brand-new selection (frequency × recency)")
    func recencyBlendsWithFrequency() {
        let now = Date()
        let oneHalfLifeAgo = now.addingTimeInterval(-3 * 24 * 60 * 60)
        var frecency = Frecency()
        // "loyal" was picked four times a half-life ago: 4 × 0.5 = 2.0, which
        // still beats a single brand-new pick (1.0). Frecency is not pure
        // recency — a habitually-used Action doesn't vanish behind a one-off.
        for _ in 0..<4 { frecency.record("loyal", at: oneHalfLifeAgo) }
        frecency.record("newcomer", at: now)
        #expect(frecency.ranked(now: now) == ["loyal", "newcomer"])
    }

    @Test("a selection's weight halves over the half-life")
    func decaysByHalfLife() {
        let now = Date()
        let halfLifeAgo = now.addingTimeInterval(-3 * 24 * 60 * 60)
        var fresh = Frecency()
        fresh.record("x", at: now)
        var aged = Frecency()
        aged.record("x", at: halfLifeAgo)
        // One half-life of age halves the contribution.
        #expect(abs(aged.score(for: "x", now: now) - 0.5 * fresh.score(for: "x", now: now)) < 0.0001)
    }

    @Test("the event log is bounded so storage and scoring can't grow without limit")
    func boundsStoredEvents() {
        let now = Date()
        var frecency = Frecency()
        // Record well past the cap, all at the same instant: uncapped the score
        // would be the full count, but the most-recent-N cap holds it at the
        // ceiling — bounding both the persisted blob and the O(events) scoring.
        for _ in 0..<(Frecency.maxEvents * 2 + 17) { frecency.record("x", at: now) }
        #expect(frecency.score(for: "x", now: now) == Double(Frecency.maxEvents))
    }

    @Test("dropping the oldest events past the cap preserves the ranking")
    func cappingKeepsTheMostRecent() {
        let now = Date()
        let old = now.addingTimeInterval(-30 * 24 * 60 * 60) // long since negligible
        var frecency = Frecency()
        // A flood of ancient picks for "stale" (each already ~nil weight), then a
        // single fresh pick for "fresh". Even before the cap "fresh" wins; the cap
        // only sheds events whose contribution was already negligible.
        for _ in 0..<(Frecency.maxEvents * 2) { frecency.record("stale", at: old) }
        frecency.record("fresh", at: now)
        #expect(frecency.ranked(now: now).first == "fresh")
    }

    @Test("frecency survives a Codable round-trip with its ranking intact")
    func codableRoundTrips() throws {
        let now = Date()
        var frecency = Frecency()
        frecency.record("a", at: now)
        frecency.record("a", at: now)
        frecency.record("b", at: now)

        let data = try JSONEncoder().encode(frecency)
        let restored = try JSONDecoder().decode(Frecency.self, from: data)

        #expect(restored == frecency)
        #expect(restored.ranked(now: now) == ["a", "b"])
    }
}
