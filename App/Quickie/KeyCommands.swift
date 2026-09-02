import SwiftUI
import UIKit
import QuickieCore

/// The one place a fired **key command** lands (CONTEXT.md → Key command; issue
/// #262), whichever of its declarations delivered it.
///
/// Neither declaration can reach `RootView`'s state directly — one lives in the
/// *Scene*, outside any view, the other on the app delegate — so both post here,
/// and `RootView` observes and handles from a **fresh body pass**. That matters:
/// handing either a closure captured at registration time would freeze the
/// `@Query` snapshots (Custom Actions, Snippets, the Pile) the search engine is
/// rebuilt from, so ⌘1 would run the Favorite as it stood when the app launched.
/// An observed value re-reads everything at the moment the key lands.
///
/// A single shared instance, because the app delegate is created by UIKit and has
/// no other way to reach the launcher's bus. `RootView` still takes it as a
/// parameter rather than reaching for the singleton, so the view stays explicit.
@MainActor
@Observable
final class KeyCommandRouter {

    static let shared = KeyCommandRouter()

    struct Dispatch: Equatable {
        var intent: KeyCommand.Intent
        var token: Int
    }

    private(set) var latest: Dispatch?
    /// Bumped by each `esc` press. `esc` is not a `KeyCommand` (it is never
    /// declared to the menu bar — see `QuickieKeyCommandDelegate`), so it rides
    /// its own channel rather than being smuggled into the declared set.
    private(set) var escapes = 0

    /// Whether the launcher itself is frontmost, published by `RootView`. The
    /// delegate reads it to decide whether to offer `esc` at all: unoffered, the
    /// key falls straight through to whatever the system would otherwise do with
    /// it on a pushed page or in a sheet.
    var isLauncherFrontmost = false

    private var counter = 0
    /// The intent already delivered this runloop turn, cleared on the next one.
    private var deliveredThisTurn: KeyCommand.Intent?

    func send(_ intent: KeyCommand.Intent) {
        // Each command is declared twice — to the menu bar (`LauncherCommands`) and
        // to the responder chain (`QuickieKeyCommandDelegate`). UIKit resolves a key
        // press to a single responder, so a double delivery should never happen; if
        // one ever does, ⌘1 must still run the Favorite **once**. Collapsing repeats
        // within one runloop turn is safe — no human presses a key twice inside one.
        guard intent != deliveredThisTurn else { return }
        deliveredThisTurn = intent
        Task { @MainActor in deliveredThisTurn = nil }
        counter += 1
        latest = Dispatch(intent: intent, token: counter)
    }

    func sendEscape() {
        escapes += 1
    }
}

/// The app delegate, which exists **only** to carry the key commands (issue #262).
///
/// This is what actually binds them. SwiftUI's `.commands` and `.keyboardShortcut`
/// are realized through the *menu* system, which exists on iPadOS and not on
/// iPhone, and which CI's synthesized key events did not reach on either. A
/// `UIResponder.keyCommands` array is the older, more direct path: UIKit resolves a
/// hardware key press against the responder chain and invokes the matching command's
/// action. The app delegate is a `UIResponder` sitting at the *end* of that chain,
/// which is exactly right here — it needs no wrapper around the launcher's delicate
/// bottom-bar layout to get into the chain, and anything closer to the first
/// responder (a presented sheet, a navigation controller) still gets first refusal.
///
/// `esc` is offered only while the launcher is frontmost, so everywhere else the key
/// is not claimed at all and the system keeps its own behaviour.
final class QuickieKeyCommandDelegate: UIResponder, UIApplicationDelegate {

    /// Where a fired command's index into `KeyCommand.declared` rides, so the
    /// selector can map the sender back to its intent.
    private static let intentIndexKey = "quickie.keyCommandIndex"

    override var keyCommands: [UIKeyCommand]? {
        var commands = KeyCommand.declared.enumerated().map { index, command in
            let key = UIKeyCommand(
                title: command.title,
                action: #selector(runKeyCommand(_:)),
                input: String(command.key),
                modifierFlags: .command,
                propertyList: [Self.intentIndexKey: index]
            )
            // Surface it in the hold-⌘ HUD beside the menu bar's own listing.
            key.discoverabilityTitle = command.title
            return key
        }
        if KeyCommandRouter.shared.isLauncherFrontmost {
            commands.append(
                UIKeyCommand(
                    title: "Dismiss",
                    action: #selector(runEscape(_:)),
                    input: UIKeyCommand.inputEscape,
                    modifierFlags: []
                )
            )
        }
        return commands
    }

    @objc private func runKeyCommand(_ sender: UIKeyCommand) {
        guard let plist = sender.propertyList as? [String: Any],
              let index = plist[Self.intentIndexKey] as? Int,
              KeyCommand.declared.indices.contains(index)
        else { return }
        let intent = KeyCommand.declared[index].intent
        MainActor.assumeIsolated { KeyCommandRouter.shared.send(intent) }
    }

    @objc private func runEscape(_ sender: UIKeyCommand) {
        MainActor.assumeIsolated { KeyCommandRouter.shared.sendEscape() }
    }
}

/// Quickie's **menu-bar** commands, declared through the SwiftUI scene `.commands`
/// API so iPadOS 26 lists them in the menu bar — the discoverability half. The
/// binding half is `QuickieKeyCommandDelegate`; a command reaching us by either
/// route runs exactly once (see `KeyCommandRouter.send`).
///
/// The set itself is Core's (`KeyCommand.declared`): this only renders it, so
/// adding a command is a Core edit with a Core test behind it and the "never
/// repurpose a system shortcut" invariant can't be sidestepped here.
struct LauncherCommands: Commands {
    let router: KeyCommandRouter

    var body: some Commands {
        CommandMenu(KeyCommand.Menu.launcher.title) {
            menuItems(in: .launcher)
        }
        CommandMenu(KeyCommand.Menu.favorites.title) {
            menuItems(in: .favorites)
        }
    }

    @ViewBuilder
    private func menuItems(in menu: KeyCommand.Menu) -> some View {
        ForEach(KeyCommand.commands(in: menu)) { command in
            Button(command.title) { router.send(command.intent) }
                // Every declared command is ⌘-modified (Core asserts the set never
                // collides with a system shortcut), so the modifier is uniform here.
                .keyboardShortcut(KeyEquivalent(command.key), modifiers: .command)
        }
    }
}

/// The launcher's half of the keyboard loop: the commands and `esc` arriving off
/// the router, the frontmost flag the delegate reads back to decide whether to
/// claim `esc` at all, and the keystroke that re-primes the [[Highlighted result]].
///
/// One modifier rather than four because `RootView`'s chain sits near the
/// compiler's type-checking budget. ↑/↓ are the one part of the loop that is *not*
/// here: they are bound on the input field itself (`InputBar`), where they arrive
/// ahead of the text system rather than having to be taken back from it.
struct KeyCommandHandling: ViewModifier {
    let router: KeyCommandRouter
    let isLauncherFrontmost: Bool
    /// The live query. A keystroke re-ranks the results, so it re-arms the
    /// [[Highlighted result]] on the best match (CONTEXT.md → Highlighted result):
    /// the modifier watches the text and calls `onPrimeHighlight` when it moves.
    /// It rides here, with the rest of the keyboard loop, rather than as one more
    /// `onChange` on `RootView`'s chain — which sits *at* the compiler's
    /// type-checking budget, close enough that adding one tips it over.
    let primeHighlightOn: String
    let onCommand: (KeyCommand.Intent) -> Void
    let onEscape: () -> Void
    let onPrimeHighlight: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: router.latest) { _, dispatch in
                guard let dispatch else { return }
                onCommand(dispatch.intent)
            }
            .onChange(of: router.escapes) { _, _ in onEscape() }
            .onChange(of: isLauncherFrontmost, initial: true) { _, frontmost in
                router.isLauncherFrontmost = frontmost
            }
            .onChange(of: primeHighlightOn) { _, _ in onPrimeHighlight() }
    }
}
