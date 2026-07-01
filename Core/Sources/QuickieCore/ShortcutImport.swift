import Foundation

/// One imported Shortcut Action's persisted state (issue #45; ADR 0007): the
/// shortcut's **name** (its identity — `Get My Shortcuts` returns no stable IDs)
/// and the per-row **`acceptsInput`** toggle, the only way Quickie learns a
/// shortcut takes input since import is names-only. `Codable` so the app can
/// persist the set as JSON in the shared App Group `UserDefaults`, mirroring the
/// `FallbacksStore` pattern — no CloudKit.
public struct ShortcutEntry: Codable, Equatable, Sendable {
    public let name: String
    public var acceptsInput: Bool

    public init(name: String, acceptsInput: Bool = false) {
        self.name = name
        self.acceptsInput = acceptsInput
    }
}

/// The pure ingestion side of the Sync Shortcut round-trip (issue #45; ADR 0007).
/// iOS forbids enumerating a user's Shortcuts through any API, so the companion
/// **Sync Shortcut** does it from inside the Shortcuts app and hands the names
/// back over the `quickie://` URL scheme, newline-delimited. Everything here is
/// pure and unit-tested against sample payloads — the app layer owns the URL
/// scheme registration and the persistence, this owns the parsing and the
/// name-keyed reconciliation.
public enum ShortcutImport {

    /// The custom URL scheme the Sync Shortcut returns names on (Info.plist
    /// `CFBundleURLTypes`). Both this slice's `import` route and the next slice's
    /// `shortcut-result` route ride it.
    public static let scheme = "quickie"

    /// The inbound `import` route's host — `quickie://import?names=…`.
    public static let importHost = "import"

    /// The query item carrying the newline-delimited, URL-encoded name list.
    public static let namesQueryItem = "names"

    /// Extracts the raw newline-delimited names payload from an inbound
    /// `quickie://import?names=…` URL, or `nil` when the URL isn't the import
    /// route (a foreign scheme, or a sibling host like the next slice's
    /// `shortcut-result`). The app dispatches inbound URLs by host at the root;
    /// this keeps the routing decision pure and testable.
    public static func namesPayload(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == importHost else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == namesQueryItem })?.value
    }

    /// Parses a raw Sync-Shortcut payload into clean shortcut names: split on
    /// newline, trim each, drop empties, dedup **case-insensitively** (keeping the
    /// first spelling seen), and **self-filter** the Sync Shortcut out by its own
    /// name so the importer never registers itself as a runnable Shortcut Action.
    /// Newline-delimited is safe because a shortcut name cannot contain a newline.
    public static func parse(_ payload: String, selfName: String) -> [String] {
        let selfKey = selfName.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        var names: [String] = []
        for line in payload.split(separator: "\n", omittingEmptySubsequences: false) {
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard key != selfKey else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            names.append(name)
        }
        return names
    }

    /// Reconciles a parsed name list into the persisted entry set — the **universal
    /// auto-prune** a re-sync performs (ADR 0007). Rebuilds the set to mirror the
    /// payload: it keeps existing names (**preserving each survivor's `acceptsInput`
    /// toggle**), adds names not seen before with input off, and drops names absent
    /// from the payload. Matching is by name, case-insensitively. Order follows the
    /// payload. A first import is just this against an empty `existing`, and — since
    /// identity is the name — a rename reads as delete + re-add (old toggle lost).
    public static func reconcile(existing: [ShortcutEntry], names: [String]) -> [ShortcutEntry] {
        let toggleByName = Dictionary(
            existing.map { ($0.name.lowercased(), $0.acceptsInput) },
            uniquingKeysWith: { first, _ in first }
        )
        return names.map { name in
            ShortcutEntry(name: name, acceptsInput: toggleByName[name.lowercased()] ?? false)
        }
    }
}
