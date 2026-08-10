import Foundation

/// Which rung of the Fallback list's promotion ladder an Action sits on
/// (CONTEXT.md → Fallback list, Shelf; issue #241).
public enum FallbackTier: String, Sendable, CaseIterable {
    /// Eligible but not activated — the derived waiting room, never stored.
    case pool
    /// The user-ordered Active section: rides the Result list's bottom fallback region.
    case enabled
    /// The user-ordered Shelf: the glass button row above the input. A shelved action
    /// **vacates** the bottom region (its ranked name-match duplicate is unaffected).
    case shelf
}

/// The user's two stored fallback lists — the **Shelf** and the **enabled** (Active)
/// list — held together so the ladder's one hard invariant, *an id sits on at most one
/// rung*, cannot be broken by a caller (CONTEXT.md → Fallback list, Shelf; ADR 0037;
/// issue #241). The third rung, the pool, stays derived (everything eligible that
/// neither list claims), so it is still never stored.
///
/// Membership is the only fact: there is deliberately no capture-vs-search category
/// anywhere in the model (ADR 0037), so the Shelf is reconciled, pruned, and reordered
/// by exactly the same rules as the enabled list — `FallbackActivation`'s per-list
/// primitives, applied to both. Everything here is pure and edge-free (no UserDefaults,
/// no EventKit), so the App's `FallbacksStore` is a thin persistence wrapper and every
/// placement rule is exercised by `swift test`.
public struct FallbackTiers: Equatable, Sendable {
    /// The Shelf, most-important-first — leading edge of the button row.
    public private(set) var shelf: [String]
    /// The Active list, most-important-first (the top of the page is nearest the input).
    public private(set) var enabled: [String]

    /// Builds the ladder from two persisted lists, restoring the invariant rather than
    /// trusting it: each list is de-duplicated (first position wins) and **the Shelf
    /// wins** any id both claim. That is what makes the Shelf seed a one-liner — the
    /// migration hands over the user's untouched enabled list alongside the seeded
    /// Shelf, and the ids the Shelf claims (Save for later, New Snippet) simply leave
    /// Active.
    public init(shelf: [String] = [], enabled: [String] = []) {
        var seen = Set<String>()
        self.shelf = shelf.filter { seen.insert($0).inserted }
        self.enabled = enabled.filter { seen.insert($0).inserted }
    }

    /// The rung `id` currently sits on. Anything neither list claims is in the pool —
    /// including an id that isn't fallback-eligible at all, which the caller has
    /// already filtered by shape (`Action.isFallbackEligible`).
    public func tier(of id: String) -> FallbackTier {
        if shelf.contains(id) { return .shelf }
        if enabled.contains(id) { return .enabled }
        return .pool
    }

    /// Moves `id` to `tier`, applying the ladder's placement rules (CONTEXT.md →
    /// Fallback list). A move off a rung always removes it from the other list first,
    /// so the tiers stay disjoint:
    ///
    /// - **to the Shelf** — appended at the trailing end, from Active *or* straight
    ///   from the pool (no forced two-step climb).
    /// - **to Active** — inserted at the **top** when it comes down from the Shelf (it
    ///   was important enough to shelve, so it does not fall to the bottom), appended
    ///   at the bottom when it comes up from the pool ("available", not "most
    ///   important").
    /// - **to the pool** — dropped from whichever list held it; the pool is derived,
    ///   so there is nothing to insert into.
    ///
    /// Moving an id to the rung it already occupies is a no-op that keeps its rank, so
    /// a repeated tap can never quietly re-sort the list.
    public mutating func move(_ id: String, to tier: FallbackTier) {
        let from = self.tier(of: id)
        guard from != tier else { return }
        shelf.removeAll { $0 == id }
        enabled.removeAll { $0 == id }
        switch tier {
        case .shelf: shelf.append(id)
        case .enabled: enabled.insert(id, at: from == .shelf ? 0 : enabled.endIndex)
        case .pool: break
        }
    }

    /// The derived **pool**: the eligible ids neither list claims. The page sorts these
    /// alphabetically by title (titles live App-side); this only knows ids, so it
    /// returns membership in the caller's order.
    public func pool(from liveEligibleIDs: [String]) -> [String] {
        liveEligibleIDs.filter { tier(of: $0) == .pool }
    }

    /// The Shelf resolved through the live fallback-eligible catalog — ids that don't
    /// currently resolve are hidden without being forgotten, exactly as for Active.
    public func resolvedShelf(for liveEligibleIDs: [String]) -> [String] {
        FallbackActivation.reconciledEnabledIDs(enabled: shelf, liveEligibleIDs: Set(liveEligibleIDs))
    }

    /// The Active list resolved through the live fallback-eligible catalog — the
    /// engine's `enabledFallbacks` and the page's Active section.
    public func resolvedEnabled(for liveEligibleIDs: [String]) -> [String] {
        FallbackActivation.reconciledEnabledIDs(enabled: enabled, liveEligibleIDs: Set(liveEligibleIDs))
    }

    /// Applies a drag-reorder of the **visible** Shelf rows, keeping any member that
    /// hasn't resolved yet in its slot (the launch race; issue #114).
    public mutating func reorderShelf(visibleOrder: [String]) {
        shelf = FallbackActivation.reorderedEnabled(enabled: shelf, visibleOrder: visibleOrder)
    }

    /// Applies a drag-reorder of the **visible** Active rows, with the same
    /// not-yet-loaded care as `reorderShelf`.
    public mutating func reorderEnabled(visibleOrder: [String]) {
        enabled = FallbackActivation.reorderedEnabled(enabled: enabled, visibleOrder: visibleOrder)
    }

    /// Demotes every id in `ids` to the pool — the coupling behind the per-action
    /// **Disabled** switch (CONTEXT.md → Disabled; issue #68): a disabled action leaves
    /// *both* the Shelf and Active, so re-enabling it lands it in the pool rather than
    /// restoring its old rank on either rung.
    public mutating func demoteToPool(_ ids: Set<String>) {
        shelf.removeAll(where: ids.contains)
        enabled.removeAll(where: ids.contains)
    }

    /// Forgets the rank of any member of **either** tier whose eligibility is genuinely
    /// lost — seen eligible earlier this session (`everEligible`) but no longer live.
    /// Regaining eligibility re-enters the action as a pool newcomer. An id never yet
    /// seen eligible (the seeded default before `@Query` surfaces it) is kept, so the
    /// launch race is never mistaken for a loss. See `FallbackActivation
    /// .prunedForgettingLost` for the rule and its one accepted limit.
    public mutating func pruneForgettingLost(liveEligible: Set<String>, everEligible: Set<String>) {
        shelf = FallbackActivation.prunedForgettingLost(
            enabled: shelf, liveEligible: liveEligible, everEligible: everEligible
        )
        enabled = FallbackActivation.prunedForgettingLost(
            enabled: enabled, liveEligible: liveEligible, everEligible: everEligible
        )
    }

    /// The first-run (and migration) Shelf, most-important-first: New Reminder, New
    /// Event, Save for later, New Snippet (CONTEXT.md → Shelf). A default, fully
    /// user-editable — the capture-vs-search intuition survives *only* here, as the
    /// reason these four were picked, never as model state (ADR 0037). The two captures
    /// also appear in `FallbackActivation.firstRunEnabledIDs()`; the initializer's
    /// shelf-wins rule is what settles that overlap, for a fresh install and an
    /// existing user's carried-over list alike.
    public static let firstRunShelfIDs = [
        Action.newReminderID, Action.newEventID, Action.saveForLaterID, Action.newSnippetID,
    ]
}
