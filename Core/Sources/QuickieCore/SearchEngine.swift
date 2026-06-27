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

        // Sort each Provider's candidates into the three regions of the Result
        // list (ADR 0008), preserving the provider order the App wired. A
        // candidate's region is decided by *how* it earns its place: a Fallback
        // is pinned bottom; a Dynamic Provider's result is a type-triggered hit
        // that floats top; everything else is a verb-first name-match.
        var boosted: [Action] = []   // type-triggered, already query-relevant
        var matchable: [Action] = [] // verb-first, scored by the matcher
        var fallbacks: [Action] = [] // pinned to the bottom region
        for provider in providers {
            for action in provider.candidates(for: trimmed) {
                if action.isFallback {
                    fallbacks.append(action)
                } else if provider.kind == .dynamic {
                    boosted.append(action)
                } else {
                    matchable.append(action)
                }
            }
        }

        // Verb-first: name-matchable Actions, scored against the query and
        // dropped when they don't match. Dynamic results skip this — the
        // Provider already decided they apply, so they are not name-matched
        // (Provider.swift: "dynamic candidates arrive already query-relevant").
        let matches = matchable
            .compactMap { action -> (action: Action, score: Double)? in
                guard let score = bestScore(for: action, query: trimmed) else { return nil }
                return (action, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                // Deterministic tie-break so equal scores never reorder
                // unpredictably between runs.
                if lhs.action.title != rhs.action.title { return lhs.action.title < rhs.action.title }
                return lhs.action.id < rhs.action.id
            }
            .map(\.action)

        // Fallbacks are pinned to the bottom region — present for any non-empty
        // query, consuming the raw text — and given a deterministic order.
        let sortedFallbacks = fallbacks
            .sorted { $0.title != $1.title ? $0.title < $1.title : $0.id < $1.id }

        // Boosted (top) → name-matches (middle) → fallbacks (bottom).
        return boosted + matches + sortedFallbacks
    }

    /// The best match score across an Action's title and its aliases — a query
    /// that hits any of an Action's names surfaces it.
    private func bestScore(for action: Action, query: String) -> Double? {
        ([action.title] + action.aliases)
            .compactMap { Matcher.score(query: query, candidate: $0, layout: layout) }
            .max()
    }
}
