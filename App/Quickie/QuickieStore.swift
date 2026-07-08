import Foundation
import SwiftData
import QuickieCore
import QuickieStoreKit

/// The app-side half of the store (ADR 0022): the `@Model` schema, `AppGroup`,
/// and container configurations moved into `QuickieStoreKit` so the Share
/// Extension opens the same store against the same schema. What stays here is
/// everything only the app runs — first-launch seeding, data migrations, the
/// CloudKit seed dedup (ADR 0023), the UI-testing hooks — plus the
/// `ArgumentSpec` bridge, which needs `QuickieCore` vocabulary the framework
/// deliberately doesn't link.
extension StoredCustomAction {
    /// Creates a row from decoded per-slot type config. The framework's
    /// designated init takes the stored JSON blob; this is the app-facing
    /// spelling every call site keeps using.
    convenience init(
        id: String = UUID().uuidString,
        title: String,
        urlString: String,
        alias: String? = nil,
        fillOrder: [String] = [],
        argumentSpecs: [String: ArgumentSpec],
        createdAt: Date = Date()
    ) {
        self.init(
            id: id,
            title: title,
            urlString: urlString,
            alias: alias,
            fillOrder: fillOrder,
            argumentSpecsData: Self.encodeSpecs(argumentSpecs),
            createdAt: createdAt
        )
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

extension QuickieStore {
    private static let defaultWebSearchTemplate = "https://duckduckgo.com/?q={query}"
    /// The seeded web search's fixed, well-known id (ADR 0023). The seed is
    /// guarded by a *per-device* flag, so a second device can seed before its
    /// first CloudKit import lands — a fixed id is what lets the launch-time
    /// dedup pass recognize the two rows as the same seed and collapse them.
    /// Exposed so `FallbacksStore` can pre-enable it as a first-run fallback
    /// (issue #114) against the exact id the seed writes.
    static let seedWebSearchID = "seed.web-search"
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
    /// flag so it happens exactly once. Web search is an ordinary, deletable one-slot
    /// Custom Action — no longer a privileged built-in — so the user can search out
    /// of the box while remaining free to delete or edit it. Its free-text `{query}`
    /// slot makes it fallback-*eligible* by shape (issue #114); `FallbacksStore`
    /// pre-enables it in the first-run enabled list. No data migration: the retired
    /// Fallback query storage is pre-release, so there is nothing to convert (ADR 0021).
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
                alias: "search"
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

    /// The dedup pass behind the fixed seed id (ADR 0023): CloudKit cannot
    /// enforce uniqueness, so two devices that each seeded before their first
    /// import both end up with two "Search the web" rows once sync merges the
    /// stores. Among rows sharing an id, `StoreDedup` keeps a deterministic
    /// winner — oldest `createdAt`, synced attributes as the stable tie-break,
    /// so every device deletes the same rows — and this pass deletes the rest.
    /// Runs at launch *and* whenever the Custom Action catalog changes (a
    /// mid-session CloudKit import can land a duplicate long after launch —
    /// a launcher stays resident between cold starts). Idempotent and cheap
    /// when there are no duplicates (the common case): one fetch, no writes.
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
