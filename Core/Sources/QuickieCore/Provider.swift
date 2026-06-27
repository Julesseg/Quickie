/// Whether a Provider's Actions are a pre-indexed, enumerable set or computed
/// live per keystroke (ADR 0004). The SearchEngine treats the two differently:
/// indexed candidates are matched and ranked centrally; dynamic candidates
/// arrive already query-relevant.
public enum ProviderKind: Sendable {
    case indexed
    case dynamic
}

/// A source that contributes Actions to the Result list. Every Action
/// originates from exactly one Provider. Providers are the core extensibility
/// seam — new capabilities are new Providers — so the protocol is intentionally
/// tiny: declare your kind, hand back candidate Actions for a query.
public protocol Provider: Sendable {
    var kind: ProviderKind { get }

    /// A multiplier on the match score of every Action this Provider
    /// contributes (issue #9 AC #3) — the lever that lets one source outrank
    /// another at equal match quality (e.g. a user's own Quicklinks over the
    /// built-ins). Defaults to `1.0` (neutral) so most Providers ignore it.
    var weight: Double { get }

    /// The Actions this Provider offers for the given query. An **Indexed**
    /// Provider returns its full catalog regardless of the query and lets the
    /// SearchEngine match/rank it. A **Dynamic** Provider computes results from
    /// the query and decides for itself whether it applies.
    func candidates(for query: String) -> [Action]
}

public extension Provider {
    /// Neutral weight: most Providers neither boost nor suppress their Actions
    /// relative to others, so they need not declare one.
    var weight: Double { 1.0 }
}
