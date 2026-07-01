import SwiftUI
import SwiftData

/// The app shell. Per ADR 0012 (zero-wall launch) there is no onboarding and
/// no scene chrome between launch and the input field — the WindowGroup hosts
/// `RootView` directly, and the SwiftData store (shared App Group container,
/// CloudKit off) is attached so the Result list can read user content.
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
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
