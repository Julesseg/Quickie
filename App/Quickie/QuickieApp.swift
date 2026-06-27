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
            return QuickieStore.inMemoryContainer()
        }
        return QuickieStore.container
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
