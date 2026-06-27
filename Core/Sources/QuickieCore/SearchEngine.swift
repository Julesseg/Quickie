import Foundation

/// Turns a typed query into the ranked Result list — the loop minus the pixels.
/// It gathers candidate Actions from every Provider, scores each against the
/// query via the `Matcher` (best of title or aliases), drops non-matches, and
/// sorts best-first so the top row sits nearest the input.
///
/// This is the skeleton's ranking policy: matcher score only. The richer M1
/// signals (frecency, favorites, provider weight, exact-match float, fallbacks
/// pinned bottom) layer in here in later slices without changing the
/// `results(for:)` shape the UI depends on.
public struct SearchEngine {
    private let providers: [Provider]
    /// The active keyboard layout, used by the Matcher to weight adjacent-key
    /// typos. The App keeps this in step with `UITextInputMode`; the Core
    /// defaults to QWERTY so it stays platform-agnostic and testable.
    private let layout: KeyboardLayout

    public init(providers: [Provider], layout: KeyboardLayout = .qwerty) {
        self.providers = providers
        self.layout = layout
    }

    /// The ranked Result list for `query`, best match first. An empty or
    /// whitespace-only query returns `[]` — the signal for the app to show the
    /// Home placeholder rather than a Result list.
    public func results(for query: String) -> [Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let scored = providers
            .flatMap { $0.candidates(for: trimmed) }
            .compactMap { action -> (action: Action, score: Double)? in
                guard let score = bestScore(for: action, query: trimmed) else { return nil }
                return (action, score)
            }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                // Deterministic tie-break so equal scores never reorder
                // unpredictably between runs.
                if lhs.action.title != rhs.action.title { return lhs.action.title < rhs.action.title }
                return lhs.action.id < rhs.action.id
            }
            .map(\.action)
    }

    /// The best match score across an Action's title and its aliases — a query
    /// that hits any of an Action's names surfaces it.
    private func bestScore(for action: Action, query: String) -> Double? {
        ([action.title] + action.aliases)
            .compactMap { Matcher.score(query: query, candidate: $0, layout: layout) }
            .max()
    }
}
