import Foundation
import Testing
@testable import QuickieCore

// The Sync Shortcut round-trip (issue #45; ADR 0007): the companion Shortcut
// enumerates the user's shortcuts and hands their names back to Quickie over the
// `quickie://` URL scheme, newline-delimited. The parsing is a pure Core
// function so it can be exercised against sample payloads without a device —
// split on newline, trim, drop empties, dedup case-insensitively, and self-filter
// the Sync Shortcut out by its own name. Newline-delimited is safe because a
// shortcut name cannot contain a newline.
struct ShortcutImportTests {

    @Test("parsing splits newline-delimited names, trimming and dropping empties")
    func splitsTrimsAndDropsEmpties() {
        let payload = "  Timer \n\nScan Document\n  \nStart Workout  "
        #expect(
            ShortcutImport.parse(payload, selfName: "Quickie Sync")
                == ["Timer", "Scan Document", "Start Workout"]
        )
    }

    @Test("parsing dedups case-insensitively, keeping the first spelling")
    func dedupsCaseInsensitively() {
        // Identity is the shortcut name, matched case-insensitively (ADR 0007).
        let payload = "Timer\ntimer\nTIMER\nScan"
        #expect(
            ShortcutImport.parse(payload, selfName: "Quickie Sync")
                == ["Timer", "Scan"]
        )
    }

    @Test("parsing self-filters the Sync Shortcut out by its own name")
    func selfFiltersTheSyncShortcut() {
        // The Sync Shortcut appears in its own `Get My Shortcuts` output; it must
        // never register itself as a runnable Shortcut Action. Matched by name,
        // case-insensitively.
        let payload = "Timer\nquickie sync\nScan"
        #expect(
            ShortcutImport.parse(payload, selfName: "Quickie Sync")
                == ["Timer", "Scan"]
        )
    }

    @Test("the import route extracts the names payload from an inbound quickie://import URL")
    func extractsNamesFromImportURL() {
        // The Sync Shortcut URL-encodes the newline-delimited list into `names`.
        let encoded = "Timer\nScan".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "quickie://import?names=\(encoded)")!
        #expect(ShortcutImport.namesPayload(from: url) == "Timer\nScan")
    }

    @Test("the import route ignores URLs that aren't the import host")
    func ignoresNonImportURLs() {
        // The next slice adds a `shortcut-result` host on the same scheme; the
        // importer must not claim it. A foreign scheme is ignored too.
        #expect(ShortcutImport.namesPayload(from: URL(string: "quickie://shortcut-result?output=hi")!) == nil)
        #expect(ShortcutImport.namesPayload(from: URL(string: "https://import?names=Timer")!) == nil)
    }

    @Test("a first import registers every name with input off, in payload order")
    func firstImportRegistersAllNames() {
        let entries = ShortcutImport.reconcile(existing: [], names: ["Timer", "Scan"])
        #expect(entries == [
            ShortcutEntry(name: "Timer", acceptsInput: false),
            ShortcutEntry(name: "Scan", acceptsInput: false),
        ])
    }

    @Test("re-sync auto-prunes to the payload, preserving acceptsInput on survivors")
    func reSyncAutoPrunesPreservingToggle() {
        // Universal auto-prune keyed by name (ADR 0007): mirror the payload — keep
        // existing names (preserving their toggle), add new ones (input off), drop
        // names absent from the payload. Matched case-insensitively.
        let existing = [
            ShortcutEntry(name: "Timer", acceptsInput: true),
            ShortcutEntry(name: "Scan", acceptsInput: false),
            ShortcutEntry(name: "Gone", acceptsInput: true),
        ]
        let entries = ShortcutImport.reconcile(existing: existing, names: ["timer", "Workout"])
        #expect(entries == [
            // "timer" survives and keeps its ON toggle (case-insensitive match).
            ShortcutEntry(name: "timer", acceptsInput: true),
            // "Workout" is new — input off.
            ShortcutEntry(name: "Workout", acceptsInput: false),
            // "Scan" and "Gone" are absent from the payload — pruned.
        ])
    }

    @Test("renaming a shortcut reads as delete + re-add, dropping the old toggle")
    func renameIsDeletePlusReAdd() {
        // Identity is the name, so a renamed shortcut is a new name (input off)
        // and the old name — with its toggle — is pruned (ADR 0007 corollary).
        let existing = [ShortcutEntry(name: "Old Name", acceptsInput: true)]
        let entries = ShortcutImport.reconcile(existing: existing, names: ["New Name"])
        #expect(entries == [ShortcutEntry(name: "New Name", acceptsInput: false)])
    }
}
