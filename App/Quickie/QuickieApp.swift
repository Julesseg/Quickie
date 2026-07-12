import SwiftUI
import SwiftData
import QuickieStoreKit

/// The app shell. Per ADR 0012 (zero-wall launch) there is no onboarding and
/// no scene chrome between launch and the input field — the WindowGroup hosts
/// `RootView` directly, and the SwiftData store (shared App Group container,
/// CloudKit-synced with silent local fallback — ADR 0023) is attached so the
/// Result list can read user content.
@main
struct QuickieApp: App {
    /// The shared App Group store in normal use; an ephemeral in-memory store
    /// under UI testing so each run starts clean and tests stay idempotent.
    private let container: ModelContainer = {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            // The in-memory store starts empty every launch, but UserDefaults
            // (where the one-time migration flag lives) persists across runs — so
            // clear the flag here, letting the launch migration re-seed the
            // default web-search Fallback query into each fresh test store.
            SignalsStore.sharedDefaults.removeObject(forKey: QuickieStore.migrationFlagKeyForTesting)
            SignalsStore.sharedDefaults.removeObject(forKey: QuickieStore.quicklinkSeedFlagKeyForTesting)
            return QuickieStore.inMemoryContainer()
        }
        return QuickieStore.container
    }()

    init() {
        // Honor the same UI-test reset flag as SignalsStore/FallbacksStore for the
        // app-level toggles (issue #65): they persist in the App Group defaults,
        // so without this a test that flipped Clipboard prefill or Show Recents
        // off would leak that state into every later run. Done here, before
        // `RootView`'s `@AppStorage` properties take their first read.
        if ProcessInfo.processInfo.arguments.contains(SignalsStore.uitestResetArgument) {
            AppSettings.reset(in: AppGroup.defaults)
            // The Favorites-widget projection keys (snapshot + frecency outbox —
            // ADR 0025) live in the same persistent App Group defaults: without
            // this, a leftover outbox event from a prior run would drain into
            // frecency and trip a later test's "empty Home" assertion.
            FavoritesWidgetStore.launchReset()
            // The eligible-action catalog (ADR 0027) shares those persistent
            // defaults too — clear it on the same reset so a prior run's catalog
            // can't leak into a later test.
            EligibleActionCatalogStore.launchReset()
        }
        // Seed pending widget-run outbox events under UI testing (issue #126):
        // XCUITest can't tap a Home-Screen widget, so this plants real outbox
        // events — through `FavoritesWidgetStore.recordRun` — before `RootView`
        // drains them, letting a test prove a widget run surfaces in Frecency.
        // After the reset above, so the seed lands on the clean slate.
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            FavoritesWidgetStore.seedRunsFromLaunchArguments()
        }
        // Forward-migrate the retired Event/Reminder capture settings onto the
        // schema's single dynamic-choice keys (ADR 0020; issue #69), before
        // RootView's `@AppStorage` first read — so a "save silently" preference set
        // on an older build survives the upgrade instead of reverting to "ask".
        SettingsMigration.migrateDynamicChoices()
        // Seed the default web-search Custom Action here — *before* `RootView`'s
        // `@Query` first reads (ADR 0021) — rather than in RootView's launch task.
        // SwiftData delivers a mid-`.task` insert to a `@Query` only on the next
        // update cycle, so seeding there left the catalog empty for the first
        // render: a pinned Favorite pointing at the seed (`seed.web-search`) then
        // failed to draw its Home card until the query caught up, a race that lost
        // deterministically on the slow CI iPhone SE runner. Seeding at init makes
        // the catalog populated from the very first render on any toolchain. The
        // seed flag keeps it a one-shot in normal use (and, with the flag cleared
        // above under UI testing, a per-run reseed for the fresh in-memory store);
        // RootView's launch task still runs the CloudKit dedupe and favorites
        // reconcile over the now already-seeded catalog.
        QuickieStore.seedDefaultCustomActions(in: container.mainContext)
        // Seed the default static Quicklinks (YouTube, Gmail, GitHub) here too, for
        // the same reason: populated from the first render so a pinned Favorite
        // pointing at a `seed.link.*` id draws its Home card without a @Query race.
        QuickieStore.seedDefaultQuicklinks(in: container.mainContext)
        // Seed legacy pre-Pile Note rows under UI testing (issue #62; ADR 0018):
        // the flag plants `StoredNote` rows in the fresh in-memory store *before*
        // RootView's launch task runs `migrateNotesToPile`, so the test drives
        // the real collapse. Gated on `--uitesting` too so a stray flag can never
        // write into the real store.
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),
           ProcessInfo.processInfo.arguments.contains(QuickieStore.uitestSeedNotesArgument) {
            QuickieStore.seedLegacyNotesForUITesting(in: container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
