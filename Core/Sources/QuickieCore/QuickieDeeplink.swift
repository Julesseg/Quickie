import Foundation

/// The inbound `quickie://` **deeplink door** (issue #120; ADR 0024) — the pure
/// parse/build half of the entry family the App Intents bridge and epic #16's
/// entry surfaces ride, a sibling to `ShortcutImport` (the Sync-Shortcut ingest)
/// and `ShortcutRun` (the run round-trip) on the same `quickie` scheme. It exists
/// before any App Intent does: the Quick Capture App Shortcut (#121), the
/// deep-link widget (#124), and the Control Center control (#125) all construct
/// these URLs and hand them to the single root `onOpenURL`.
///
/// Four routes, each a **distinct host** so it never collides with the sibling
/// `import` / `shortcut-result` / `shortcut-error` / `shortcut-cancel` families:
///
/// - `quickie://capture/reminder` — open with the Reminder quick capture selected,
///   breadcrumb at Argument 1 (CONTEXT.md → Reminder)
/// - `quickie://capture/event` — the same for the Event quick capture
/// - `quickie://run/<id>` — **tap-equivalent** run of the Action with `id`: the app
///   behaves exactly as if the user tapped that Action's result row (a Favorite
///   runs its main action, a Custom Action starts its breadcrumb). An id that no
///   longer resolves degrades to plain Home — the app resolves it, this only carries
///   it (CONTEXT.md → Bridged Action)
/// - `quickie://entry` — **fresh entry**: reset to a clean, focused Home, the route
///   every open-focused entry surface rides (CONTEXT.md → Entry surface)
///
/// Parsing is pure and `swift test`-covered so the whole grammar is exercised
/// without a device; the app only dispatches the classified value at its root.
/// An unrecognized URL — a foreign scheme, a sibling host, an unknown capture
/// leaf, an empty run id, an `entry` with trailing junk — classifies as `nil`
/// and is ignored, so the existing `quickie://` families pass straight through.
public enum QuickieDeeplink: Equatable, Sendable {
    case captureReminder
    case captureEvent
    case run(id: String)
    case entry

    /// The `quickie://` scheme, shared with the sibling import/run families
    /// (`ShortcutImport.scheme`) — one scheme, dispatched by host at the root.
    public static let scheme = ShortcutImport.scheme

    /// The `quickie://capture/…` host and its two leaves.
    public static let captureHost = "capture"
    public static let reminderLeaf = "reminder"
    public static let eventLeaf = "event"

    /// The `quickie://run/<id>` host.
    public static let runHost = "run"

    /// The `quickie://entry` host.
    public static let entryHost = "entry"

    // MARK: Parse

    /// Classifies an inbound `quickie://` URL into a deeplink route, or `nil` when
    /// it is not one of the four (a foreign scheme, a sibling host, an unknown
    /// capture leaf, an empty run id, or `entry` with trailing path). Pure and
    /// total so the app's root dispatch stays a single `switch`.
    public static func parse(_ url: URL) -> QuickieDeeplink? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case captureHost:
            switch leaf(of: url) {
            case reminderLeaf: return .captureReminder
            case eventLeaf: return .captureEvent
            default: return nil
            }
        case runHost:
            guard let id = idPath(of: url), !id.isEmpty else { return nil }
            return .run(id: id)
        case entryHost:
            // A fresh-entry reset must be unambiguous: `entry` alone (a bare host or
            // a lone trailing slash), never `entry/<junk>` — trailing path classifies
            // as unknown, not a silent reset.
            return leaf(of: url) == nil ? .entry : nil
        default:
            return nil
        }
    }

    /// The single path component after the host — `reminder` in `capture/reminder`
    /// — or `nil` when the host stands alone or carries more than one component.
    /// A capture leaf is exactly one segment; anything else is not a capture route.
    private static func leaf(of url: URL) -> String? {
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count == 1 else { return nil }
        return String(segments[0])
    }

    /// The full path after the `run` host, leading slash dropped — the Action id,
    /// already percent-decoded by `URL.path`. Read whole (not split) so an id that
    /// happens to contain a `/` survives; `nil` when there is no path at all.
    private static func idPath(of url: URL) -> String? {
        guard url.path.hasPrefix("/") else { return nil }
        return String(url.path.dropFirst())
    }

    // MARK: Build

    /// Builds `quickie://entry` — the fresh-entry reset every open-focused entry
    /// surface opens the app on (#121, #124, #125).
    public static func entryURL() -> URL {
        build(host: entryHost, path: nil)
    }

    /// Builds `quickie://capture/reminder`.
    public static func captureReminderURL() -> URL {
        build(host: captureHost, path: reminderLeaf)
    }

    /// Builds `quickie://capture/event`.
    public static func captureEventURL() -> URL {
        build(host: captureHost, path: eventLeaf)
    }

    /// Builds `quickie://run/<id>`, percent-encoding the id so a title-derived id
    /// with spaces or reserved characters round-trips through `parse` intact.
    public static func runURL(id: String) -> URL {
        build(host: runHost, path: id)
    }

    /// Assembles a `quickie://<host>[/<path>]` URL, percent-encoding `path` for the
    /// URL's path component (`percentEncodedPath`, so the encoding is explicit and
    /// portable rather than leaning on the `path` setter's platform behavior).
    /// Falls back to the bare host URL only to keep the signature non-optional; the
    /// fixed structure is always valid.
    private static func build(host: String, path: String?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let path {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            components.percentEncodedPath = "/" + encoded
        }
        return components.url ?? URL(string: "\(scheme)://\(host)")!
    }
}
