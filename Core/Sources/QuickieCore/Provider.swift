/// How a Provider's Actions reach the Result list (ADR 0004, ADR 0015). The
/// SearchEngine treats each kind differently:
/// - **indexed** — a pre-indexed, enumerable catalog the engine matches and ranks
///   centrally; also the only kind eligible for Home (Favorites + Frecency).
/// - **dynamic** (*boosted*-dynamic) — computed live and already query-relevant,
///   so it floats to the top region unscored (the Calculator: a math answer is
///   unambiguously the top hit).
/// - **rankedDynamic** — computed live from the Provider's *own* prefiltered index
///   (so a large set never floods the central catalog, Home, or Frecency), but its
///   survivors are name-scored by the `Matcher` and placed in the **ranked** region
///   by match quality (File Search): an exact command name still outranks a strong
///   filename hit.
public enum ProviderKind: Sendable {
    case indexed
    case dynamic
    case rankedDynamic
}

/// A source that contributes Actions to the Result list. Every Action
/// originates from exactly one Provider. Providers are the core extensibility
/// seam — new capabilities are new Providers — so the protocol is intentionally
/// tiny: declare your kind, hand back candidate Actions for a query.
public protocol Provider: Sendable {
    var kind: ProviderKind { get }

    /// Which configurable kind this Provider is (ADR 0019; issue #67) — the
    /// identity its Enabled toggle persists against. `nil` for a catalog that
    /// belongs to no disableable kind (the hub's built-in command rows), which
    /// is what keeps every Settings command row typeable while its provider is
    /// disabled: the recovery path can't be switched off.
    var id: ProviderID? { get }

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

    /// No kind by default: a Provider is only disableable once it declares
    /// which `ProviderID` it is.
    var id: ProviderID? { nil }
}
