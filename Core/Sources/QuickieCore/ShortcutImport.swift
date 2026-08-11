import Foundation

/// One imported Shortcut Action's persisted state (issue #45; ADR 0007): the
/// shortcut's **name** (its identity — `Get My Shortcuts` returns no stable IDs),
/// the per-row **`acceptsInput`** toggle (the only way Quickie learns a shortcut
/// takes input since import is names-only), and an optional user-defined **alias**
/// (issue #198) — the single extra name the matcher scores alongside the title, the
/// same single-alias convention the Custom Action editor uses. `Codable` so the app
/// can persist the set as JSON in the shared App Group `UserDefaults`, mirroring the
/// `FallbacksStore` pattern — no CloudKit.
public struct ShortcutEntry: Codable, Equatable, Sendable {
    public let name: String
    public var acceptsInput: Bool
    /// The one optional user-defined alias, edited inline on the Shortcuts page
    /// (issue #198). `nil` (the default) means no alias — no pill, nothing extra to
    /// match. Optional so decoding a pre-#198 payload (which lacks the key) reads as
    /// no alias rather than failing, the same forward-compat the `acceptsInput`
    /// default gives.
    public var alias: String?
    /// The user-chosen **leading glyph**, mirroring `CustomActionDefinition.glyph`
    /// (issue #163): an SF Symbol name picked from the same curated glyph catalog on
    /// the shortcut's own appearance page, which `Action.shortcut` stamps onto the
    /// produced `Action.glyph`. `nil` (the default) leaves the kind-derived glyph
    /// unchanged — a pure opt-in, so an untouched import looks exactly as before.
    /// Optional so a pre-appearance payload decodes as no glyph.
    public var glyph: String?
    /// The **raw persisted** Action color token, mirroring `StoredCustomAction
    /// .colorToken` (issue #243) — a plain string rather than the typed `ActionColor`
    /// so an unknown or blank token (a build with an older/newer palette) decodes
    /// cleanly instead of failing; `color` is the tolerant typed read of it. `nil`
    /// is **Default** — the kind-derived tint, unchanged.
    public var colorToken: String?

    public init(
        name: String,
        acceptsInput: Bool = false,
        alias: String? = nil,
        glyph: String? = nil,
        colorToken: String? = nil
    ) {
        self.name = name
        self.acceptsInput = acceptsInput
        self.alias = alias
        self.glyph = glyph
        self.colorToken = colorToken
    }

    /// Normalizes a raw alias string to *set* vs *unset* (issue #198): trim
    /// whitespace, and a blank result collapses to `nil` (no alias). The one place
    /// the rule lives, so the Shortcuts page's field writer (`ShortcutsStore.setAlias`)
    /// and the `Action.shortcut` factory agree — an all-whitespace field never becomes
    /// a matchable empty alias or an empty pill. Mirrors `normalizedGlyph` below for
    /// the glyph (issue #163).
    public static func normalizedAlias(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// The chosen glyph normalized to *set* vs *unset*, mirroring
    /// `CustomActionDefinition.normalizedGlyph` (issue #163): a blank or
    /// whitespace-only name collapses to `nil` so an "empty" glyph reads as unset
    /// (the derived glyph applies) rather than an unrenderable blank symbol.
    public var normalizedGlyph: String? {
        Self.normalizedGlyph(glyph)
    }

    /// The shared *set vs unset* rule for a raw stored glyph string — same
    /// normalization the Custom Action editor's badge and this type's own
    /// `normalizedGlyph` apply, so a whitespace-only value reads as "no symbol"
    /// everywhere identically.
    public static func normalizedGlyph(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return raw
    }

    /// The chosen **Action color** (issue #243), resolved from `colorToken` through
    /// the same tolerant `ActionColor(token:)` read every persisted surface uses —
    /// an absent, blank, or unknown token reads as Default rather than failing.
    public var color: ActionColor? {
        ActionColor(token: colorToken)
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
    /// toggle, its alias, and its chosen glyph/color**, issues #198, #163, #243),
    /// adds names not seen before with input off and no alias/appearance, and drops
    /// names absent from the payload. Matching is by name, case-insensitively. Order
    /// follows the payload. A first import is just this against an empty `existing`,
    /// and — since identity is the name — a rename reads as delete + re-add, so the
    /// renamed shortcut loses its toggle, alias, and appearance alike.
    public static func reconcile(existing: [ShortcutEntry], names: [String]) -> [ShortcutEntry] {
        // Key the whole survivor by name so `acceptsInput`, `alias`, and the
        // appearance all carry forward together — each survives a re-sync exactly
        // like the toggle does.
        let existingByName = Dictionary(
            existing.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return names.map { name in
            let survivor = existingByName[name.lowercased()]
            return ShortcutEntry(
                name: name,
                acceptsInput: survivor?.acceptsInput ?? false,
                alias: survivor?.alias,
                glyph: survivor?.glyph,
                colorToken: survivor?.colorToken
            )
        }
    }

    /// The names in `names` that are **new** to `existing` — matched by name,
    /// case-insensitively, exactly like `reconcile` — in payload order. These are
    /// the fresh imports a sync adds; the app layer starts each one **disabled**
    /// (CONTEXT.md → Disabled) so an import never floods results — the user
    /// enables the shortcuts they actually want from the Shortcuts page, while a
    /// re-sync's survivors keep whatever enablement they already have.
    public static func addedNames(existing: [ShortcutEntry], names: [String]) -> [String] {
        let known = Set(existing.map { $0.name.lowercased() })
        return names.filter { !known.contains($0.lowercased()) }
    }
}
