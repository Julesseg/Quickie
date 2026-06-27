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

    /// The Actions this Provider offers for the given query. An **Indexed**
    /// Provider returns its full catalog regardless of the query and lets the
    /// SearchEngine match/rank it. A **Dynamic** Provider computes results from
    /// the query and decides for itself whether it applies.
    func candidates(for query: String) -> [Action]
}
