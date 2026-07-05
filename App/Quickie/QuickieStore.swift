import Foundation
import SwiftData
import QuickieCore

/// The shared App Group that backs Quickie's store. Decided up front (ADR 0006)
/// so the future Share Extension, widgets, and App Intents write to the same
/// source of truth as the app — moving the store into an App Group later is a
/// painful migration.
///
/// NOTE: this identifier must match the `com.apple.security.application-groups`
/// entry in `Quickie.entitlements`, and the App Group must be enabled for the
/// app's bundle ID in your Apple Developer account.
enum AppGroup {
    static let identifier = "group.com.julesseguin.quickie"

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
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: identifier) ?? .standard
}

/// A user-saved Quicklink: a stored *static* URL that opens directly (CONTEXT.md
/// → Quicklink; ADR 0013). It carries no `{placeholder}` and consumes no typed
/// text — the query-consuming, templated behaviour now lives on
/// `StoredCustomAction`. The app persists these in SwiftData and rebuilds the
/// in-memory index from them on launch (ADR 0006: the store is the source of truth,
/// the index a derived cache). Quickie ships no default Quicklinks.
@Model
final class StoredQuicklink {
    /// A stable, collision-free identity assigned at creation and persisted with
    /// the Quicklink. This — not `persistentModelID.hashValue`, which is neither
    /// collision-free nor stable across launches (the same trap the Pile entry avoids) —
    /// is what the index derives this Quicklink's Action id from, so a pinned
    /// Favorite or its Frecency survives relaunches instead of silently orphaning.
    /// Defaulted at the property so existing rows migrate without a value.
    var id: String = UUID().uuidString
    var title: String = ""
    var urlString: String = ""
    /// An optional alternative name also matched against the query.
    var alias: String?
    var createdAt: Date = Date()

    init(
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
/// instance (`seedDefaultCustomActions` seeds it on first launch). Managed this
/// slice on the interim Fallbacks page (the real editor + Custom Actions Management
/// page are the next slice); its fallback-flagged rows are ordered/disabled there
/// alongside Save for later / New Snippet.
///
/// `id` is a stable identity assigned at creation — the key the Fallbacks page's
/// persisted order and disabled set reference, and the id of the Action built
/// from this row, so reordering/disabling survives relaunches.
@Model
final class StoredCustomAction {
    var id: String = UUID().uuidString
    var title: String = ""
    /// The URL template; always contains at least one `{name}` slot (the editor
    /// enforces it, mirroring `CustomActionDefinition`).
    var urlString: String = ""
    var alias: String?
    /// Whether this is a **Fallback** Custom Action (CONTEXT.md → Fallback Action):
    /// surfaced in the bottom region, its selection seeding the typed query as
    /// Argument 1. Web search seeds with this on; the interim Fallbacks sheet
    /// authors fallback-flagged rows. Defaulted so a future non-fallback row (the
    /// next slice's Custom Actions page) migrates without a value.
    var isFallback: Bool = true
    /// The **fill order** (CONTEXT.md → Custom Action; ADR 0021, issue #94): the
    /// token names in the order the breadcrumb asks them, which the editor's
    /// drag-to-reorder sets. Empty (the default, so existing rows migrate without a
    /// value) means URL-appearance order — `CustomActionDefinition` reconciles it hard
    /// against the live template on read.
    var fillOrder: [String] = []
    /// The per-slot **type config** (CONTEXT.md → Argument; ADR 0021, issue #96),
    /// keyed by token name: each slot's type (text/number/date/choice), a choice's
    /// inline options, and a date's optional output-format overrides — **JSON-encoded**.
    /// Stored as `Data` rather than a `[String: ArgumentSpec]` dictionary attribute
    /// because SwiftData did not round-trip that composite Codable dictionary
    /// (the persisted types were silently lost on reload); a `Data` blob is a
    /// primitive it fully supports. Bridged by the `argumentSpecs` computed property.
    /// Optional so existing rows migrate without a value (every slot is then free text).
    var argumentSpecsData: Data?
    var createdAt: Date = Date()

    init(
        id: String = UUID().uuidString,
        title: String,
        urlString: String,
        alias: String? = nil,
        isFallback: Bool = true,
        fillOrder: [String] = [],
        argumentSpecs: [String: ArgumentSpec] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.alias = alias
        self.isFallback = isFallback
        self.fillOrder = fillOrder
        self.argumentSpecsData = Self.encodeSpecs(argumentSpecs)
        self.createdAt = createdAt
    }

    /// The per-slot type config, decoded from its stored JSON (issue #96). A missing
    /// or unreadable blob reads as no config — every slot is then plain free text.
    /// SwiftData ignores this computed property; only `argumentSpecsData` persists.
    var argumentSpecs: [String: ArgumentSpec] {
        get {
            guard let data = argumentSpecsData,
                  let decoded = try? JSONDecoder().decode([String: ArgumentSpec].self, from: data)
            else { return [:] }
            return decoded
        }
        set { argumentSpecsData = Self.encodeSpecs(newValue) }
    }

    /// Encodes the spec map to its stored JSON, collapsing an empty map to `nil` so a
    /// spec-less action stores no blob (and migrates cleanly).
    private static func encodeSpecs(_ specs: [String: ArgumentSpec]) -> Data? {
        specs.isEmpty ? nil : try? JSONEncoder().encode(specs)
    }
}

/// A user-saved Snippet: reusable text whose main action is **Copy**
/// (CONTEXT.md → Snippet) — canned replies, an address, a template pasted
/// repeatedly. Persisted in SwiftData alongside Quicklinks; the in-memory index
/// is rebuilt from these on launch (ADR 0006). A Snippet is distinct from a Pile
/// entry in intent: titled, reusable copy-out text, not a deferred query.
@Model
final class StoredSnippet {
    /// A stable, collision-free identity assigned at creation and persisted with
    /// the Snippet. This — not `persistentModelID.hashValue`, which is neither
    /// collision-free nor stable across launches (the same trap the Pile entry avoids) —
    /// is what the index derives this Snippet's Action id from, so a pinned
    /// Favorite or its Frecency survives relaunches instead of silently orphaning.
    /// Defaulted at the property so existing rows migrate without a value.
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date()

    init(title: String, body: String, createdAt: Date = Date()) {
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
final class StoredPileEntry {
    /// A stable, collision-free identity assigned at creation and persisted with
    /// the entry. This — not `persistentModelID.hashValue`, which is neither
    /// collision-free nor stable across launches — is what the index uses to
    /// derive the entry's Action id and what `stagePileEntry(id:)` resolves back
    /// to.
    var id: String = UUID().uuidString
    var text: String = ""
    var createdAt: Date = Date()

    init(id: String = UUID().uuidString, text: String, createdAt: Date = Date()) {
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
    var actionID: String { id }
}

extension StoredSnippet {
    var actionID: String { "snippet.\(id)" }
}

extension StoredPileEntry {
    var actionID: String { "pile.\(id)" }
}

/// The legacy Note entity (pre-ADR 0018), kept in the schema **only** so
/// `migrateNotesToPile` can read the rows a previous build stored and collapse
/// each to a titleless Pile entry. Nothing else creates or reads these; once
/// migrated, the table stays empty.
@Model
final class StoredNote {
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: String = UUID().uuidString, title: String, body: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Owns the single `ModelContainer`, configured for the shared App Group with
/// CloudKit private-database sync — on by default, offline-first, covering
/// exactly this content store and nothing else (ADR 0023). Every stored
/// attribute above carries a property-level default (or is optional) because
/// CloudKit requires it. Absence of iCloud or the entitlement degrades
/// silently to the fully-functional local store.
enum QuickieStore {
    static let container: ModelContainer = {
        let schema = Schema([StoredQuicklink.self, StoredCustomAction.self, StoredSnippet.self, StoredPileEntry.self, StoredNote.self])

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

    /// An ephemeral, in-memory container used under UI testing (the `--uitesting`
    /// launch argument). Each launch starts with an empty store, so Pile entries
    /// and snippets never persist or accumulate across runs — the tests stay
    /// idempotent and a capture assertion can't pass on a stale row from a
    /// previous run.
    static func inMemoryContainer() -> ModelContainer {
        let schema = Schema([StoredQuicklink.self, StoredCustomAction.self, StoredSnippet.self, StoredPileEntry.self, StoredNote.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory Quickie ModelContainer: \(error)")
        }
    }

    private static let defaultWebSearchTemplate = "https://duckduckgo.com/?q={query}"
    /// The seeded web search's fixed, well-known id (ADR 0023). The seed is
    /// guarded by a *per-device* flag, so a second device can seed before its
    /// first CloudKit import lands — a fixed id is what lets the launch-time
    /// dedup pass recognize the two rows as the same seed and collapse them.
    private static let seedWebSearchID = "seed.web-search"
    /// Bumped to `.v2` for the Custom Action unification (ADR 0021): the retired
    /// `StoredFallbackQuery` table is gone, so a fresh seed of the web-search
    /// **Custom Action** must run once against the new storage even on a build that
    /// recorded the old split migration as done.
    private static let seedFlagKey = "store.didSeedCustomActions.v2"

    /// Exposed so the UI-testing launch path can clear the one-time seed flag and
    /// let each fresh in-memory store re-seed the default web-search Custom Action.
    static var migrationFlagKeyForTesting: String { seedFlagKey }

    /// Seeds the default, fully deletable web-search **Custom Action** on first
    /// launch (CONTEXT.md → Custom Action; ADR 0021), run at launch and guarded by a
    /// flag so it happens exactly once. Web search is an ordinary, deletable,
    /// fallback-flagged one-slot Custom Action — no longer a privileged built-in —
    /// so the user can search out of the box while remaining free to delete or edit
    /// it. No data migration: the retired Fallback query storage is pre-release, so
    /// there is nothing to convert (ADR 0021).
    ///
    /// Idempotent and defensive: the seed is gated on "no Custom Actions *and* never
    /// seeded", so a user who later deletes web search doesn't get it re-seeded.
    @MainActor
    static func seedDefaultCustomActions(
        in context: ModelContext,
        defaults: UserDefaults = SignalsStore.sharedDefaults
    ) {
        guard !defaults.bool(forKey: seedFlagKey) else { return }

        let existing = (try? context.fetchCount(FetchDescriptor<StoredCustomAction>())) ?? 0
        if existing == 0 {
            context.insert(StoredCustomAction(
                id: seedWebSearchID,
                title: "Search the web",
                urlString: defaultWebSearchTemplate,
                alias: "search",
                isFallback: true
            ))
        }

        // Only record the seed as done once the save actually persists. If it
        // throws, leave the flag unset so the seed retries next launch — otherwise
        // the inserted Custom Action would be lost with no way to recover (the guard
        // would skip the retry forever).
        do {
            try context.save()
            defaults.set(true, forKey: seedFlagKey)
        } catch {
            // Save failed; the seed will retry on the next launch.
        }
    }

    /// The launch-time dedup pass behind the fixed seed id (ADR 0023): CloudKit
    /// cannot enforce uniqueness, so two devices that each seeded before their
    /// first import both end up with two "Search the web" rows once sync
    /// merges the stores. Among rows sharing an id, `StoreDedup` keeps a
    /// deterministic winner — oldest `createdAt`, synced attributes as the
    /// stable tie-break, so every device deletes the same rows — and this pass
    /// deletes the rest. Cheap when there are no duplicates (the common case):
    /// one fetch, no writes.
    @MainActor
    static func dedupeCustomActions(in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<StoredCustomAction>())) ?? []
        let duplicates = StoreDedup.duplicatesToDelete(
            among: rows,
            id: \.id,
            createdAt: \.createdAt,
            tieBreak: { "\($0.urlString)|\($0.title)|\($0.alias ?? "")" }
        )
        guard !duplicates.isEmpty else { return }

        for row in duplicates {
            context.delete(row)
        }
        try? context.save()
    }

    /// The launch argument that seeds legacy pre-Pile `StoredNote` rows into the
    /// fresh in-memory UI-testing store (alongside `--uitesting`), so a UI test
    /// can drive the real `migrateNotesToPile` collapse at launch instead of the
    /// migration going unexercised (issue #62; ADR 0018).
    static let uitestSeedNotesArgument = "-uitest-seed-notes"

    /// Plants the legacy rows `uitestSeedNotesArgument` asks for: a note whose
    /// title differs from its body, so the test can assert the collapse keeps
    /// the body as the entry's text and drops the title (it stops matching).
    @MainActor
    static func seedLegacyNotesForUITesting(in context: ModelContext) {
        context.insert(StoredNote(
            title: "Groceries list",
            body: "buy oat milk and eggs for the week"
        ))
    }

    /// One-time data migration for the Note → Pile replacement (ADR 0018), run
    /// at launch: every stored note collapses to a titleless Pile entry — the
    /// body *is* the entry's text; the title is dropped (it was derived from the
    /// body's first line at capture, and ADR 0018 accepts losing it). No flag is
    /// needed: migrated rows are deleted, so the source empties and re-running
    /// is a no-op — self-healing if a save ever fails mid-way.
    @MainActor
    static func migrateNotesToPile(in context: ModelContext) {
        let notes = (try? context.fetch(FetchDescriptor<StoredNote>())) ?? []
        guard !notes.isEmpty else { return }

        for note in notes {
            let text = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                context.insert(StoredPileEntry(id: note.id, text: text, createdAt: note.createdAt))
            }
            context.delete(note)
        }
        try? context.save()
    }
}
