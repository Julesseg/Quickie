import Foundation

/// The launcher's **key command** set (CONTEXT.md → Key command; issue #262): the
/// hardware-keyboard commands Quickie declares to the system so an iPad with a
/// keyboard attached drives the whole loop without a touch, and so the iPadOS 26
/// menu bar and the hold-⌘ HUD list them the system way.
///
/// The declaration lives here — not inside the App's SwiftUI command builders —
/// for the same reason every other policy does: which keys Quickie claims is a
/// decision with an invariant behind it (never repurpose a standard system
/// shortcut, one key per command), and an invariant asserted by `swift test` on
/// any platform beats a convention buried in a view builder. It matters twice
/// over here, because the App renders this one set in *two* places — the scene's
/// menu-bar commands and the launcher's own in-view shortcuts — and a set split
/// across two builders would drift. The App renders exactly what `declared` says
/// and applies exactly the outcome `EscapeKey` returns.
///
/// Every declared command is **⌘-modified**. `esc` is deliberately *not* one of
/// them — its meaning is contextual and an unmodified key claimed app-wide would
/// swallow the system's own escape handling on pushed pages and sheets — so it
/// lives beside this type as `EscapeKey` and the App binds it to the launcher alone.
public struct KeyCommand: Equatable, Hashable, Sendable, Identifiable {

    /// What a command does when it fires. The App switches on this exhaustively,
    /// so adding a case is a compile error at the one place it must be handled.
    public enum Intent: Equatable, Hashable, Sendable {
        /// Put the caret back in the search input from anywhere at the root.
        case focusSearch
        /// Run the Favorite occupying `slot` of the 2×2 [[Favorites grid]],
        /// one-based, tap-equivalently to that card.
        case runFavorite(slot: Int)
        /// Open the Settings hub (its top-level page, no provider panel).
        case openSettings
    }

    public var intent: Intent
    /// The menu-bar / HUD label. Written as the verb the user is invoking, since
    /// the hold-⌘ HUD shows the item alone with no menu title around it.
    public var title: String
    /// The key equivalent, always taken with ⌘.
    public var key: Character
    /// The top-level menu-bar menu the command is listed under.
    public var menu: Menu

    public var id: Intent { intent }

    /// The menu-bar menus the set is split across — one `CommandMenu` each, in
    /// this order. A closed set rather than free titles, so a command can only be
    /// filed under a menu that exists and the App can build the bar by walking it.
    public enum Menu: String, CaseIterable, Equatable, Hashable, Sendable {
        case launcher = "Launcher"
        case favorites = "Favorites"

        /// The menu's title in the bar.
        public var title: String { rawValue }
    }

    /// The 2×2 [[Favorites grid]]'s slots (CONTEXT.md → Favorites grid): four,
    /// one-based, matching ⌘1–⌘4.
    public static let favoriteSlots = 1...4

    /// The ⌘-keys the system (or a focused text field) already owns — Copy, Paste,
    /// Cut, Select All, Undo/Redo, and the standard document/window verbs. A
    /// launcher that repurposed one of these would break the very field it is
    /// built around, so `declared` is asserted disjoint from this set.
    public static let systemReservedKeys: Set<Character> = [
        "a", // Select All
        "c", // Copy
        "f", // Find
        "h", // Hide
        "m", // Minimize
        "n", // New
        "o", // Open
        "p", // Print
        "q", // Quit
        "s", // Save
        "t", // New Tab
        "v", // Paste
        "w", // Close
        "x", // Cut
        "z", // Undo / Redo
    ]

    /// The full set, in menu-declaration order.
    public static let declared: [KeyCommand] = [
        KeyCommand(
            intent: .focusSearch,
            title: "Focus Search",
            key: "k",
            menu: .launcher
        ),
        KeyCommand(
            intent: .openSettings,
            title: "Settings",
            key: ",",
            menu: .launcher
        ),
    ] + favoriteSlots.map { slot in
        KeyCommand(
            intent: .runFavorite(slot: slot),
            title: "Run Favorite \(slot)",
            key: Character("\(slot)"),
            menu: .favorites
        )
    }

    /// The commands filed under `menu`, in declaration order — what the App loops
    /// over to build one `CommandMenu`.
    public static func commands(in menu: Menu) -> [KeyCommand] {
        declared.filter { $0.menu == menu }
    }

    /// The Favorite a ⌘-digit addresses: the [[Action]] on the card in that
    /// one-based slot of the 2×2 grid. Nothing outside the grid's four slots is
    /// addressable, and a slot past what the user has pinned resolves to nothing
    /// rather than wrapping.
    public static func favorite(at slot: Int, in favorites: [Action]) -> Action? {
        guard favoriteSlots.contains(slot) else { return nil }
        let index = slot - 1
        guard favorites.indices.contains(index) else { return nil }
        return favorites[index]
    }
}

/// The `esc` key — the launcher's one **contextual** key, and deliberately not a
/// `KeyCommand`: it is never declared to the menu bar (an unmodified key claimed
/// app-wide would swallow the system's own escape everywhere else), so it is its
/// own small policy rather than a member of the declared set.
public enum EscapeKey {

    /// What pressing `esc` unwinds.
    public enum Outcome: Equatable, Sendable {
        /// Empty the input that owns the bottom bar — the query, or the capture
        /// step's text — leaving every context intact.
        case clearInput
        /// Abandon the in-flight capture, exactly as its × affordance does.
        case exitCapture
        /// Leave the [[Search Files context]], exactly as its × affordance does.
        case exitFileSearch
        /// Nothing to unwind: esc is a no-op.
        case ignored
    }

    /// What `esc` means right now. It **unwinds one layer at a time**, innermost
    /// first, so the key always reads as "back one step" rather than "throw
    /// everything away":
    ///
    /// 1. Text in the input that owns the bottom bar — the query, or a capture
    ///    step's text — clears first.
    /// 2. With that text empty, an active capture is abandoned, exactly as its ×
    ///    affordance does (CONTEXT.md → Quick capture).
    /// 3. Otherwise the [[Search Files context]] is left, exactly as its × does.
    /// 4. On a clean Home there is nothing to unwind, so esc does nothing — it is
    ///    never a destructive key with no visible effect to undo.
    ///
    /// A capture entered from the Search Files context leaves both flags set; the
    /// capture is the innermost layer, so it unwinds first and a further esc then
    /// leaves the context.
    public static func outcome(
        hasInputText: Bool,
        isCapturing: Bool,
        inFileSearch: Bool
    ) -> Outcome {
        if hasInputText { return .clearInput }
        if isCapturing { return .exitCapture }
        if inFileSearch { return .exitFileSearch }
        return .ignored
    }
}
