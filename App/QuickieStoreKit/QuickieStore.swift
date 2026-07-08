import Foundation
import SwiftData

/// The shared App Group that backs Quickie's store. Decided up front (ADR 0006)
/// so the Share Extension, widgets, and App Intents write to the same source of
/// truth as the app — moving the store into an App Group later is a painful
/// migration. Lives in `QuickieStoreKit` (ADR 0022) so the app and the Share
/// Extension — two processes opening the same store — share one identifier.
///
/// NOTE: this identifier must match the `com.apple.security.application-groups`
/// entry in `Quickie.entitlements` and `QuickieShareExtension.entitlements`, and
/// the App Group must be enabled for the app's bundle ID in your Apple
/// Developer account.
public enum AppGroup {
    public static let identifier = "group.com.julesseguin.quickie"

    /// The shared App Group `UserDefaults`, falling back to `.standard` when the
    /// group isn't provisioned — the same degrade-gracefully posture as the
    /// SwiftData store, so preferences work on an unentitled build too.
    ///
    /// Stored once and shared, not computed per access: `@AppStorage` observes
    /// the exact instance it was handed, so the Settings page's toggle writes
    /// update `RootView`'s reads live only when both hold the *same* object —
    /// with a fresh instance per access the write persists but the launcher
    /// doesn't see it until the next launch. `nonisolated(unsafe)` is what lets
    /// a non-`Sendable` type be stored globally under strict concurrency; it is
    /// safe here because `UserDefaults` is documented thread-safe.
    nonisolated(unsafe) public static let defaults = UserDefaults(suiteName: identifier) ?? .standard
}

/// A user-saved Quicklink: a stored *static* URL that opens directly (CONTEXT.md
/// → Quicklink; ADR 0013). It carries no `{placeholder}` and consumes no typed
/// text — the query-consuming, templated behaviour now lives on
/// `StoredCustomAction`. The app persists these in SwiftData and rebuilds the
/// in-memory index from them on launch (ADR 0006: the store is the source of truth,
/// the index a derived cache). Quickie ships no default Quicklinks; the Share
/// Extension writes one from a shared URL (ADR 0022).
@Model
public final class StoredQuicklink {
    /// A stable, collision-free identity assigned at creation and persisted with
    /// the Quicklink. This — not `persistentModelID.hashValue`, which is neither
    /// collision-free nor stable across launches (the same trap the Pile entry avoids) —
    /// is what the index derives this Quicklink's Action id from, so a pinned
    /// Favorite or its Frecency survives relaunches instead of silently orphaning.
    /// Defaulted at the property so existing rows migrate without a value.
    public var id: String = UUID().uuidString
    public var title: String = ""
    public var urlString: String = ""
    /// An optional alternative name also matched against the query.
    public var alias: String?
    public var createdAt: Date = Date()

    public init(
        title: String,
        urlString: String,
        alias: String? = nil,
        createdAt: Date = Date()
    ) {
        self.title = title
        self.urlString = urlString
        self.alias = alias
        self.createdAt = createdAt
    }
}

/// A user-saved **Custom Action** (CONTEXT.md → Custom Action; ADR 0021): a stored
/// URL template that **requires** at least one `{name}` slot the breadcrumb fills,
/// opening the filled URL on commit. It absorbs the retired Fallback query
/// wholesale — web search is a default-seeded, fully deletable, fallback-flagged
/// instance (`seedDefaultCustomActions` seeds it on first launch).
///
/// `id` is a stable identity assigned at creation — the key the Fallbacks page's
/// persisted order and disabled set reference, and the id of the Action built
/// from this row, so reordering/disabling survives relaunches.
@Model
public final class StoredCustomAction {
    public var id: String = UUID().uuidString
    public var title: String = ""
    /// The URL template; always contains at least one `{name}` slot (the editor
    /// enforces it, mirroring `CustomActionDefinition`).
    public var urlString: String = ""
    public var alias: String?
    /// Whether this is a **Fallback** Custom Action (CONTEXT.md → Fallback Action):
    /// surfaced in the bottom region, its selection seeding the typed query as
    /// Argument 1. Web search seeds with this on. Defaulted so a non-fallback row
    /// migrates without a value.
    public var isFallback: Bool = true
    /// The **fill order** (CONTEXT.md → Custom Action; ADR 0021, issue #94): the
    /// token names in the order the breadcrumb asks them, which the editor's
    /// drag-to-reorder sets. Empty (the default, so existing rows migrate without a
    /// value) means URL-appearance order — `CustomActionDefinition` reconciles it hard
    /// against the live template on read.
    public var fillOrder: [String] = []
    /// The per-slot **type config** (CONTEXT.md → Argument; ADR 0021, issue #96),
    /// keyed by token name — **JSON-encoded**. Stored as `Data` rather than a
    /// composite Codable dictionary attribute because SwiftData did not round-trip
    /// that dictionary (the persisted types were silently lost on reload); a `Data`
    /// blob is a primitive it fully supports. The `[String: ArgumentSpec]` bridge is
    /// an app-side extension (`argumentSpecs`): `ArgumentSpec` is `QuickieCore`
    /// vocabulary, and this framework deliberately holds the schema alone (ADR 0022).
    /// Optional so existing rows migrate without a value (every slot is then free text).
    public var argumentSpecsData: Data?
    public var createdAt: Date = Date()

    public init(
        id: String = UUID().uuidString,
        title: String,
        urlString: String,
        alias: String? = nil,
        isFallback: Bool = true,
        fillOrder: [String] = [],
        argumentSpecsData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.alias = alias
        self.isFallback = isFallback
        self.fillOrder = fillOrder
        self.argumentSpecsData = argumentSpecsData
        self.createdAt = createdAt
    }
}

/// A user-saved Snippet: reusable text whose main action is **Copy**
/// (CONTEXT.md → Snippet) — canned replies, an address, a template pasted
/// repeatedly. Persisted in SwiftData alongside Quicklinks; the in-memory index
/// is rebuilt from these on launch (ADR 0006). A Snippet is distinct from a Pile
/// entry in intent: titled, reusable copy-out text, not a deferred query.
@Model
public final class StoredSnippet {
    /// A stable, collision-free identity assigned at creation and persisted with
    /// the Snippet. This — not `persistentModelID.hashValue`, which is neither
    /// collision-free nor stable across launches (the same trap the Pile entry avoids) —
    /// is what the index derives this Snippet's Action id from, so a pinned
    /// Favorite or its Frecency survives relaunches instead of silently orphaning.
    /// Defaulted at the property so existing rows migrate without a value.
    public var id: String = UUID().uuidString
    public var title: String = ""
    public var body: String = ""
    public var createdAt: Date = Date()

    public init(title: String, body: String, createdAt: Date = Date()) {
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

/// A saved Pile entry: a raw query text the user saved to deal with later
/// (CONTEXT.md → Pile; ADR 0018) — a titleless block of text, nothing more.
/// Captured silently by the "Save for later" Fallback, staged (and consumed) by
/// its main action, discarded on the Pile page. Persisted in SwiftData alongside
/// Quicklinks and Snippets; the in-memory index is rebuilt from these on launch
/// (ADR 0006).
@Model
public final class StoredPileEntry {
    /// A stable, collision-free identity assigned at creation and persisted with
    /// the entry. This — not `persistentModelID.hashValue`, which is neither
    /// collision-free nor stable across launches — is what the index uses to
    /// derive the entry's Action id and what `stagePileEntry(id:)` resolves back
    /// to.
    public var id: String = UUID().uuidString
    public var text: String = ""
    public var createdAt: Date = Date()

    public init(id: String = UUID().uuidString, text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// The stable Action id each stored row's Action is indexed under — one
/// derivation shared by the engine wiring (`RootView`) and the Management
/// pages' per-row enablement toggles (issue #68), so a toggle always keys the
/// exact id the engine filters by. Quicklinks use the stored id as-is; the
/// prefixed spaces keep the id families collision-free. Shortcuts derive
/// theirs in Core (`Action.shortcutID(for:)`), since the factory owns it.
extension StoredQuicklink {
    public var actionID: String { id }
}

extension StoredSnippet {
    public var actionID: String { "snippet.\(id)" }
}

extension StoredPileEntry {
    public var actionID: String { "pile.\(id)" }
}

/// The legacy Note entity (pre-ADR 0018), kept in the schema **only** so
/// `migrateNotesToPile` can read the rows a previous build stored and collapse
/// each to a titleless Pile entry. Nothing else creates or reads these; once
/// migrated, the table stays empty.
@Model
public final class StoredNote {
    public var id: String = UUID().uuidString
    public var title: String = ""
    public var body: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: String = UUID().uuidString, title: String, body: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Owns the store's single schema and its container configurations, shared by
/// the app and the Share Extension (ADR 0022): two processes open the same App
/// Group store, so the schema definition must have exactly one home — this
/// framework. The app-launch seeding/migration helpers stay app-side, as
/// `QuickieStore` extensions.
public enum QuickieStore {
    /// The one schema both processes open the shared store against (ADR 0022:
    /// byte-identical or the store is ambiguous).
    private static var schema: Schema {
        Schema([StoredQuicklink.self, StoredCustomAction.self, StoredSnippet.self, StoredPileEntry.self, StoredNote.self])
    }

    /// The **app's** container, configured for the shared App Group with
    /// CloudKit private-database sync — on by default, offline-first, covering
    /// exactly this content store and nothing else (ADR 0023). Every stored
    /// attribute above carries a property-level default (or is optional)
    /// because CloudKit requires it. Absence of iCloud or the entitlement
    /// degrades silently to the fully-functional local store.
    public static let container: ModelContainer = {
        // Only ask SwiftData for the shared App Group container when this build
        // is actually entitled for it — `containerURL(forSecurityApplication…)`
        // returns nil otherwise. Probing first avoids constructing a grouped
        // ModelConfiguration that would stall or error on a device/CI simulator
        // where the App Group capability isn't provisioned (ADR 0012: never
        // block the input). When the group is unavailable we degrade to a plain
        // local store; data simply isn't shared with extensions until the group
        // is configured (ADR 0006).
        let appGroupAvailable = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) != nil

        // CloudKit sync first (ADR 0023): the same store, mirrored to the
        // user's private database. Container creation throws when the build
        // isn't entitled for iCloud (CI simulator, signed-out personal-team
        // builds), so a failure here is the expected "no iCloud" signal — fall
        // through to the local configuration rather than surfacing anything.
        let cloudKitConfiguration = appGroupAvailable
            ? ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier), cloudKitDatabase: .automatic)
            : ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        if let synced = try? ModelContainer(for: schema, configurations: [cloudKitConfiguration]) {
            return synced
        }

        let localConfiguration = appGroupAvailable
            ? ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier), cloudKitDatabase: .none)
            : ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        } catch {
            fatalError("Failed to create Quickie ModelContainer: \(error)")
        }
    }()

    /// Why the **extension's** container couldn't open (ADR 0022): unlike the
    /// app, the Share Extension never degrades to a private local store — a
    /// silent write to a container the app can never read is a fake "saved",
    /// worse than an honest failure.
    public enum AppGroupStoreError: Error {
        /// The App Group isn't provisioned for this build, so there is no
        /// shared container to write into.
        case appGroupUnavailable
        /// The shared container exists but the store failed to open in it.
        case storeFailed(any Error)
    }

    /// The **Share Extension's** container: the shared App Group store or an
    /// error — never a silent private fallback (ADR 0022). The app keeps its
    /// own degrade-to-local posture in `container` above (ADR 0006).
    ///
    /// Deliberately opened with CloudKit **off** even though the app's side
    /// syncs (ADR 0023): the extension isn't iCloud-entitled, and only one
    /// process should run the mirroring — the extension's writes land in the
    /// shared store's history and the app exports them to CloudKit on its next
    /// run, the standard extension/app split for a synced store.
    public static func appGroupContainer() throws(AppGroupStoreError) -> ModelContainer {
        guard FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) != nil
        else { throw .appGroupUnavailable }

        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            throw .storeFailed(error)
        }
    }

    /// An ephemeral, in-memory container used under UI testing (the `--uitesting`
    /// launch argument). Each launch starts with an empty store, so Pile entries
    /// and snippets never persist or accumulate across runs — the tests stay
    /// idempotent and a capture assertion can't pass on a stale row from a
    /// previous run.
    public static func inMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory Quickie ModelContainer: \(error)")
        }
    }
}
