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
}

/// A user-saved Quicklink: a stored *static* URL that opens directly (CONTEXT.md
/// → Quicklink; ADR 0013). It carries no `{placeholder}` and consumes no typed
/// text — the query-consuming behaviour now lives on `StoredFallbackQuery`. The
/// app persists these in SwiftData and rebuilds the in-memory index from them on
/// launch (ADR 0006: the store is the source of truth, the index a derived
/// cache). Quickie ships no default Quicklinks.
///
/// The former `isFallback` flag is gone (its rows migrate to Fallback queries —
/// see `migrateToFallbackQueries`); SwiftData drops the column automatically.
@Model
final class StoredQuicklink {
    /// A stable, collision-free identity assigned at creation and persisted with
    /// the Quicklink. This — not `persistentModelID.hashValue`, which is neither
    /// collision-free nor stable across launches (the same trap the Pile entry avoids) —
    /// is what the index derives this Quicklink's Action id from, so a pinned
    /// Favorite or its Frecency survives relaunches instead of silently orphaning.
    /// Defaulted at the property so existing rows migrate without a value.
    var id: String = UUID().uuidString
    var title: String
    var urlString: String
    /// An optional alternative name also matched against the query.
    var alias: String?
    var createdAt: Date

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

/// A user-saved Fallback query: a stored URL template that **requires** a
/// `{placeholder}` and consumes the typed text as its query (CONTEXT.md →
/// Fallback query; ADR 0013). One kind of Fallback Action, managed on the
/// unified Fallbacks page alongside Save for later / New Snippet. Web search is just a
/// default-seeded, fully deletable instance of this (`migrateToFallbackQueries`
/// seeds it on first launch).
///
/// `id` is a stable identity assigned at creation — the key the Fallbacks page's
/// persisted order and disabled set reference, and the id of the Action built
/// from this row, so reordering/disabling survives relaunches.
@Model
final class StoredFallbackQuery {
    var id: String
    var title: String
    /// The URL template; always contains at least one `{placeholder}` (the
    /// editor enforces it, mirroring `Action.fallbackQuery`).
    var urlString: String
    var alias: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        urlString: String,
        alias: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.alias = alias
        self.createdAt = createdAt
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
    var title: String
    var body: String
    var createdAt: Date

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
    var id: String
    var text: String
    var createdAt: Date

    init(id: String = UUID().uuidString, text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// The legacy Note entity (pre-ADR 0018), kept in the schema **only** so
/// `migrateNotesToPile` can read the rows a previous build stored and collapse
/// each to a titleless Pile entry. Nothing else creates or reads these; once
/// migrated, the table stays empty.
@Model
final class StoredNote {
    var id: String
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, title: String, body: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Owns the single `ModelContainer`, configured for the shared App Group with
/// CloudKit off for now (M1 is fully local — ADR 0006 / ROADMAP).
enum QuickieStore {
    static let container: ModelContainer = {
        let schema = Schema([StoredQuicklink.self, StoredFallbackQuery.self, StoredSnippet.self, StoredPileEntry.self, StoredNote.self])

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

        let configuration = appGroupAvailable
            ? ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier), cloudKitDatabase: .none)
            : ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
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
        let schema = Schema([StoredQuicklink.self, StoredFallbackQuery.self, StoredSnippet.self, StoredPileEntry.self, StoredNote.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory Quickie ModelContainer: \(error)")
        }
    }

    private static let defaultWebSearchTemplate = "https://duckduckgo.com/?q={query}"
    private static let migrationFlagKey = "store.didMigrateToFallbackQueries.v1"

    /// Exposed so the UI-testing launch path can clear the one-time migration flag
    /// and let each fresh in-memory store re-seed the default web-search Fallback.
    static var migrationFlagKeyForTesting: String { migrationFlagKey }

    /// One-time data migration for the Quicklink / Fallback query split (ADR
    /// 0013), run at launch and guarded by a flag so it happens exactly once.
    /// Former placeholder-Quicklinks (the only ones that could be Fallbacks)
    /// become `StoredFallbackQuery` rows; static ones stay Quicklinks. On a store
    /// with no Fallback queries it also seeds the default, fully deletable
    /// web-search query — so first launch and a clean migration both leave the
    /// user able to search, without privileging web search as a built-in.
    ///
    /// Idempotent and defensive: it never deletes a static link, and the seed is
    /// gated on "no Fallback queries *and* never migrated", so a user who later
    /// deletes web search doesn't get it re-seeded.
    @MainActor
    static func migrateToFallbackQueries(
        in context: ModelContext,
        defaults: UserDefaults = SignalsStore.sharedDefaults
    ) {
        guard !defaults.bool(forKey: migrationFlagKey) else { return }

        let placeholderLinks = (try? context.fetch(FetchDescriptor<StoredQuicklink>())) ?? []
        for link in placeholderLinks where Action.templateContainsPlaceholder(link.urlString) {
            context.insert(StoredFallbackQuery(
                title: link.title,
                urlString: link.urlString,
                alias: link.alias,
                createdAt: link.createdAt
            ))
            context.delete(link)
        }

        let existingQueries = (try? context.fetchCount(FetchDescriptor<StoredFallbackQuery>())) ?? 0
        if existingQueries == 0 {
            context.insert(StoredFallbackQuery(
                title: "Search the web",
                urlString: defaultWebSearchTemplate,
                alias: "search"
            ))
        }

        // Only record the migration as done once the save actually persists. If
        // it throws, leave the flag unset so the migration retries next launch —
        // otherwise the inserted Fallback queries and deleted placeholder
        // Quicklinks would be lost with no way to recover (the guard would skip
        // the retry forever).
        do {
            try context.save()
            defaults.set(true, forKey: migrationFlagKey)
        } catch {
            // Save failed; migration will retry on the next launch.
        }
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
