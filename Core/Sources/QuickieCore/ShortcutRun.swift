import Foundation

/// The **run** side of a Shortcut Action (CONTEXT.md → Shortcut Action; issue
/// #46) — the counterpart to `ShortcutImport`'s ingest side. Two pure halves:
///
/// - **Outbound**: `runURL(name:input:)` builds the `shortcuts://x-callback-url/
///   run-shortcut` open that fires a shortcut by name, wiring the `x-success` /
///   `x-error` / `x-cancel` callbacks back to the app's own `quickie://` routes.
///   The `ActionOutcome.runShortcut` carries only name + input; the app builds this
///   URL and opens it at the platform edge (the defer-to-the-edge pattern).
/// - **Inbound**: `result(from:)` classifies the `quickie://` callback the app is
///   reopened on — success reinjects the returned output as the new query, error
///   flashes a toast, cancel is silent. The output lives here in URL handling, not
///   in an `ActionOutcome` (CONTEXT.md → Shortcut Action), because it is the
///   deliberate poor-man's precursor to Workflow: text straight back into the input.
///
/// A third, simpler outbound verb rides alongside these: `editURL(name:)` builds
/// the `shortcuts://open-shortcut` deeplink that opens a shortcut in its editor by
/// name — the target of a Shortcut row's **Edit** secondary action. It needs no
/// callback (opening the editor is fire-and-forget), so it is not part of the
/// run round-trip.
///
/// All halves are pure and `swift test`-covered so the whole round-trip is
/// exercised without a device; the app only opens the URL and reinjects/toasts.
public enum ShortcutRun {

    // MARK: Outbound

    /// The Shortcuts x-callback-url endpoint that runs a shortcut by name.
    public static let runEndpoint = "shortcuts://x-callback-url/run-shortcut"

    /// Builds the `shortcuts://x-callback-url/run-shortcut` open for `name`, wiring
    /// the `x-success` / `x-error` / `x-cancel` callbacks back to the `quickie://`
    /// routes `result(from:)` classifies. A non-nil `input` is passed as the
    /// shortcut's **text** input via Shortcuts' contract (`input=text` selects the
    /// source, `text` carries the value); `nil` fires the shortcut with no input.
    /// `URLComponents` percent-encodes every value, so a name or input with spaces
    /// or reserved characters is carried safely.
    public static func runURL(name: String, input: String?) -> URL {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"

        var items = [URLQueryItem(name: "name", value: name)]
        if let input {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        items.append(URLQueryItem(name: "x-success", value: callback(resultHost)))
        items.append(URLQueryItem(name: "x-error", value: callback(errorHost)))
        items.append(URLQueryItem(name: "x-cancel", value: callback(cancelHost)))
        components.queryItems = items

        // The components are always valid for this fixed structure; fall back to the
        // bare endpoint only to keep the signature non-optional.
        return components.url ?? URL(string: runEndpoint)!
    }

    // MARK: Edit

    /// The Shortcuts endpoint that opens a shortcut **for editing** by name — the
    /// edit counterpart to `runEndpoint`. Unlike the run path this takes no
    /// x-callback-url wrapper: opening a shortcut in its editor is fire-and-forget,
    /// so there is nothing to route back over `quickie://`.
    public static let editEndpoint = "shortcuts://open-shortcut"

    /// Builds the `shortcuts://open-shortcut?name=<name>` open that deeplinks
    /// straight into the named shortcut's editor in the Shortcuts app (CONTEXT.md →
    /// Shortcut Action). Only the name is needed — the same name-keyed identity the
    /// run path uses (ADR 0007) — so a Shortcut row's **Edit** secondary action
    /// reuses the handle it already carries, with no Apple UUID to resolve.
    /// `URLComponents` percent-encodes the name, so spaces or reserved characters
    /// are carried safely.
    public static func editURL(name: String) -> URL {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "open-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]

        // The components are always valid for this fixed structure; fall back to the
        // bare endpoint only to keep the signature non-optional.
        return components.url ?? URL(string: editEndpoint)!
    }

    // MARK: Inbound

    /// The `quickie://` scheme the run callbacks ride — the same scheme the Sync
    /// Shortcut import returns names on (`ShortcutImport.scheme`).
    public static let scheme = ShortcutImport.scheme

    /// The `x-success` host — `quickie://shortcut-result?…` — carrying the run's
    /// returned output to reinject as the new query.
    public static let resultHost = "shortcut-result"

    /// The `x-error` host — `quickie://shortcut-error` — a failed run.
    public static let errorHost = "shortcut-error"

    /// The `x-cancel` host — `quickie://shortcut-cancel` — a user-cancelled run.
    public static let cancelHost = "shortcut-cancel"

    /// Classifies the inbound `quickie://` callback a run is reopened on, or `nil`
    /// when the URL is not a run callback (a foreign scheme, or a sibling host like
    /// the import route). Keeps the routing decision pure and testable; the app
    /// dispatches inbound URLs by host at the root and performs the classified result.
    public static func result(from url: URL) -> ShortcutResult? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case resultHost:
            // Reinjection is unconditional on success: non-empty output gives the
            // user something to act on, empty output clears the field to a fresh Home.
            return .reinject(output(from: url))
        case errorHost:
            return .failed
        case cancelHost:
            return .cancelled
        default:
            return nil
        }
    }

    /// The returned output on a success callback — read from `result` (the parameter
    /// Shortcuts appends to `x-success`) or `output` as a fallback — defaulting to
    /// empty when the run produced nothing, so an empty success clears to Home.
    private static func output(from url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        return items?.first { $0.name == "result" || $0.name == "output" }?.value ?? ""
    }

    private static func callback(_ host: String) -> String {
        "\(scheme)://\(host)"
    }
}

/// What an inbound Shortcut run callback means (CONTEXT.md → Shortcut Action;
/// issue #46), classified from the `quickie://` URL by `ShortcutRun.result(from:)`:
///
/// - `reinject` (x-success): reinject the returned output as the new query text —
///   the matcher re-runs and the Result list rebuilds. Empty output clears to Home.
/// - `failed` (x-error): flash a failure toast and leave the query untouched.
/// - `cancelled` (x-cancel): a silent no-op.
public enum ShortcutResult: Equatable, Sendable {
    case reinject(String)
    case failed
    case cancelled
}
