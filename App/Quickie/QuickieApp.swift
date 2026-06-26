import SwiftUI

/// The app shell. Per ADR 0012 (zero-wall launch) there is no onboarding and
/// no scene chrome between launch and the input field — the WindowGroup hosts
/// `RootView` directly, and the SwiftData store (shared App Group container,
/// CloudKit off) is attached so the Result list can read user content.
@main
struct QuickieApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(QuickieStore.container)
    }
}
