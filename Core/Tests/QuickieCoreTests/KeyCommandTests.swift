import Foundation
import Testing
@testable import QuickieCore

// The hardware-keyboard command set (CONTEXT.md → Key command; issue #262).
// The declaration and the esc resolution live in Core so "which keys we claim"
// and "what esc means right now" are asserted invariants rather than conventions
// buried in a SwiftUI `.commands` builder; the App only renders what `declared`
// says and applies the outcome `escape` returns.
struct KeyCommandTests {

    // MARK: - The declared set

    @Test("the declared set is exactly the launcher's six ⌘ commands")
    func declaredSetIsTheSixCommands() {
        let intents = KeyCommand.declared.map(\.intent)
        #expect(intents == [
            .focusSearch,
            .openSettings,
            .runFavorite(slot: 1),
            .runFavorite(slot: 2),
            .runFavorite(slot: 3),
            .runFavorite(slot: 4),
        ])
    }

    @Test("each command carries the key the issue specifies")
    func commandsCarryTheirKeys() {
        let keys = Dictionary(
            uniqueKeysWithValues: KeyCommand.declared.map { ($0.intent, $0.key) }
        )
        #expect(keys[.focusSearch] == "k")
        #expect(keys[.openSettings] == ",")
        #expect(keys[.runFavorite(slot: 1)] == "1")
        #expect(keys[.runFavorite(slot: 2)] == "2")
        #expect(keys[.runFavorite(slot: 3)] == "3")
        #expect(keys[.runFavorite(slot: 4)] == "4")
    }

    @Test("no two commands claim the same key")
    func keysAreUnique() {
        let keys = KeyCommand.declared.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("every command is titled, so the menu bar and the hold-⌘ HUD can list it")
    func everyCommandIsTitled() {
        for command in KeyCommand.declared {
            #expect(!command.title.isEmpty)
        }
    }

    /// Standard system shortcuts (⌘C, ⌘V, ⌘A…) must not be repurposed — a
    /// launcher that steals Copy from its own text field is broken, and the
    /// reserved set is the guard that keeps a future command from taking one.
    @Test("no command repurposes a standard system shortcut")
    func noCommandRepurposesASystemShortcut() {
        for command in KeyCommand.declared {
            #expect(
                !KeyCommand.systemReservedKeys.contains(command.key),
                "⌘\(command.key) is a system shortcut and must not be repurposed"
            )
        }
    }

    @Test("the reserved set names the editing and window shortcuts a text field owns")
    func reservedSetNamesTheEditingShortcuts() {
        for key: Character in ["c", "v", "x", "a", "z"] {
            #expect(KeyCommand.systemReservedKeys.contains(key))
        }
    }

    @Test("the Favorites commands land in the Favorites menu, the rest in the launcher menu")
    func commandsDeclareTheirMenu() {
        #expect(
            KeyCommand.commands(in: .launcher).map(\.intent) == [.focusSearch, .openSettings]
        )
        #expect(
            KeyCommand.commands(in: .favorites).map(\.intent)
                == KeyCommand.favoriteSlots.map { KeyCommand.Intent.runFavorite(slot: $0) }
        )
    }

    /// Walking the menus is how the App builds the bar, so a command filed under
    /// no menu would silently never be listed.
    @Test("walking the menus reaches every declared command")
    func walkingTheMenusReachesEveryCommand() {
        #expect(KeyCommand.Menu.allCases.flatMap(KeyCommand.commands(in:)) == KeyCommand.declared)
    }

    // MARK: - Favorite slots

    /// Stand-in pins: the built-in command rows, which every install has.
    private let grid: [Action] = [
        .openSettings(), .openCustomActionsPage(), .openFallbacksPage(), .searchFiles(),
    ]

    @Test("a slot addresses the matching Favorites-grid card, one-based")
    func slotAddressesTheMatchingCard() {
        #expect(KeyCommand.favorite(at: 1, in: grid)?.id == grid[0].id)
        #expect(KeyCommand.favorite(at: 4, in: grid)?.id == grid[3].id)
    }

    @Test("a slot past the pinned count resolves to nothing")
    func slotPastThePinnedCountResolvesToNothing() {
        #expect(KeyCommand.favorite(at: 3, in: Array(grid.prefix(2))) == nil)
        #expect(KeyCommand.favorite(at: 1, in: []) == nil)
    }

    /// The grid is 2×2 (CONTEXT.md → Favorites grid), so slot 5 is not addressable
    /// even if an older build's store somehow holds a fifth pin.
    @Test("no slot addresses past the 2×2 grid")
    func noSlotAddressesPastTheGrid() {
        let five = grid + [.openSystemPage()]
        #expect(KeyCommand.favorite(at: 5, in: five) == nil)
        #expect(KeyCommand.favorite(at: 0, in: five) == nil)
        #expect(KeyCommand.favorite(at: -1, in: five) == nil)
    }

    // MARK: - esc

    @Test("esc over a typed query clears it and stays put")
    func escOverATypedQueryClearsIt() {
        #expect(
            EscapeKey.outcome(hasInputText: true, isCapturing: false, inFileSearch: false)
                == .clearInput
        )
    }

    @Test("a second esc — the query now empty — exits an active capture")
    func secondEscExitsAnActiveCapture() {
        #expect(
            EscapeKey.outcome(hasInputText: true, isCapturing: true, inFileSearch: false)
                == .clearInput
        )
        #expect(
            EscapeKey.outcome(hasInputText: false, isCapturing: true, inFileSearch: false)
                == .exitCapture
        )
    }

    @Test("a second esc exits the Search Files context")
    func secondEscExitsTheSearchFilesContext() {
        #expect(
            EscapeKey.outcome(hasInputText: true, isCapturing: false, inFileSearch: true)
                == .clearInput
        )
        #expect(
            EscapeKey.outcome(hasInputText: false, isCapturing: false, inFileSearch: true)
                == .exitFileSearch
        )
    }

    /// A capture entered *from* the Search Files context would leave both flags
    /// set; the capture is the innermost context, so it unwinds first.
    @Test("a capture unwinds before the Search Files context")
    func captureUnwindsBeforeTheFileSearchContext() {
        #expect(
            EscapeKey.outcome(hasInputText: false, isCapturing: true, inFileSearch: true)
                == .exitCapture
        )
    }

    @Test("esc on a clean Home does nothing")
    func escOnACleanHomeDoesNothing() {
        #expect(
            EscapeKey.outcome(hasInputText: false, isCapturing: false, inFileSearch: false)
                == .ignored
        )
    }
}
