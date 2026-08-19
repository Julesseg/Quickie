import SwiftUI
import QuickieCore

/// The one place a fired **key command** lands (CONTEXT.md → Key command; issue
/// #262), whichever of its two declarations delivered it.
///
/// A `Commands` builder lives in the *Scene*, outside any view, so it cannot
/// reach `RootView`'s state directly. It posts here instead, and `RootView`
/// observes `latest` and handles it from a **fresh body pass** — which matters:
/// handing the menu a closure captured at registration time would freeze the
/// `@Query` snapshots (Custom Actions, Snippets, the Pile) the search engine is
/// rebuilt from, so ⌘1 would run the Favorite as it stood when the app launched.
/// An observed value re-reads everything at the moment the key lands.
///
/// The launcher's own in-view shortcuts post here too rather than calling the
/// handler directly, so *both* declarations of a command share one arrival point
/// — and therefore one duplicate guard (see `send`).
///
/// `token` rides alongside the intent so pressing the *same* command twice still
/// registers as a change: `⌘1 ⌘1` is two runs, not one.
@MainActor
@Observable
final class KeyCommandRouter {

    struct Dispatch: Equatable {
        var intent: KeyCommand.Intent
        var token: Int
    }

    private(set) var latest: Dispatch?
    private var counter = 0
    /// The intent already delivered this runloop turn, cleared on the next one.
    private var deliveredThisTurn: KeyCommand.Intent?

    func send(_ intent: KeyCommand.Intent) {
        // Each command is declared twice — in the menu bar (`LauncherCommands`) and
        // on the launcher itself (`LauncherKeyShortcuts`, which binds it where there
        // is no menu bar). UIKit resolves a key press to a single responder, so a
        // double delivery should never happen; if a platform ever does deliver both,
        // ⌘1 must still run the Favorite **once**. Collapsing repeats within one
        // runloop turn is safe — no human presses the same key twice inside one.
        guard intent != deliveredThisTurn else { return }
        deliveredThisTurn = intent
        Task { @MainActor in deliveredThisTurn = nil }
        counter += 1
        latest = Dispatch(intent: intent, token: counter)
    }
}

/// The buttons that carry the declared set's key equivalents. Shared by both
/// declarations below so the menu bar and the launcher can never bind different
/// keys to the same command.
private struct KeyCommandButtons: View {
    let menu: KeyCommand.Menu
    let send: (KeyCommand.Intent) -> Void

    var body: some View {
        ForEach(KeyCommand.commands(in: menu)) { command in
            Button(command.title) { send(command.intent) }
                // Every declared command is ⌘-modified (Core asserts the set never
                // collides with a system shortcut), so the modifier is uniform here.
                .keyboardShortcut(KeyEquivalent(command.key), modifiers: .command)
        }
    }
}

/// Quickie's **menu-bar** commands, declared through the SwiftUI scene `.commands`
/// API so iPadOS 26 lists them in the menu bar and holding ⌘ shows them in the
/// system shortcut HUD — rather than a private `UIKeyCommand` set the system could
/// describe to no one.
///
/// The set itself is Core's (`KeyCommand.declared`): this only renders it, so
/// adding a command is a Core edit with a Core test behind it and the "never
/// repurpose a system shortcut" invariant can't be sidestepped here.
struct LauncherCommands: Commands {
    let router: KeyCommandRouter

    var body: some Commands {
        CommandMenu(KeyCommand.Menu.launcher.title) {
            KeyCommandButtons(menu: .launcher, send: router.send)
        }
        CommandMenu(KeyCommand.Menu.favorites.title) {
            KeyCommandButtons(menu: .favorites, send: router.send)
        }
    }
}

/// The launcher's own copy of the key commands, as **in-view shortcuts**.
///
/// `LauncherCommands` alone is not enough. A scene's `.commands` are realized as a
/// *menu*, and a menu exists only where the system has one — the iPadOS 26 menu
/// bar. On iPhone, and anywhere else with no menu system, the declaration draws
/// nothing and binds nothing, so an attached keyboard would be dead. A
/// `.keyboardShortcut` on a Button *in the view hierarchy* is the other half: it
/// becomes a `UIKeyCommand` on the responder chain, which fires on every idiom and
/// takes precedence over the focused text field's own key handling. Between the
/// two, the commands are both listed (iPad) and live (everywhere).
///
/// `esc` rides here **only** — never in the menu. An unmodified key declared to the
/// menu is claimed app-wide, which would swallow the system's own escape on every
/// pushed Management page and every sheet; carried by a button that exists only
/// while the launcher is frontmost, it reaches nothing else.
///
/// The buttons are invisible, untappable, and hidden from accessibility: they are a
/// key-binding surface, not UI. Rendered in a `.background` so they add no layout.
struct LauncherKeyShortcuts: View {
    let router: KeyCommandRouter
    /// Whether the launcher itself is frontmost — the gate on `esc`'s button, so
    /// the key falls back to the system everywhere else.
    let isLauncherFrontmost: Bool
    let onEscape: () -> Void

    var body: some View {
        ZStack {
            ForEach(KeyCommand.Menu.allCases, id: \.self) { menu in
                KeyCommandButtons(menu: menu, send: router.send)
            }
            if isLauncherFrontmost {
                Button("Dismiss", action: onEscape)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The launcher's half of the keyboard loop, bundled into one modifier: the
/// commands arriving off the router, the in-view shortcuts that bind the same set
/// where no menu bar exists, and `esc`.
///
/// One modifier rather than three because `RootView`'s chain sits near the
/// compiler's type-checking budget.
struct KeyCommandHandling: ViewModifier {
    let router: KeyCommandRouter
    let isLauncherFrontmost: Bool
    let onCommand: (KeyCommand.Intent) -> Void
    let onEscape: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: router.latest) { _, dispatch in
                guard let dispatch else { return }
                onCommand(dispatch.intent)
            }
            .background {
                LauncherKeyShortcuts(
                    router: router,
                    isLauncherFrontmost: isLauncherFrontmost,
                    onEscape: onEscape
                )
            }
    }
}
