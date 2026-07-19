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

    @Test("a first import reports every name as added — all start disabled")
    func firstImportReportsAllNamesAsAdded() {
        // The app layer disables each added name's action id, so a first import
        // arrives fully disabled and the user opts shortcuts in one by one.
        #expect(ShortcutImport.addedNames(existing: [], names: ["Timer", "Scan"]) == ["Timer", "Scan"])
    }

    @Test("a re-sync reports only the genuinely new names, matched case-insensitively")
    func reSyncReportsOnlyNewNamesAsAdded() {
        // Survivors — even respelled — are not "added": they keep whatever
        // enablement the user already chose; only "Workout" starts disabled.
        let existing = [
            ShortcutEntry(name: "Timer", acceptsInput: true),
            ShortcutEntry(name: "Scan", acceptsInput: false),
        ]
        #expect(
            ShortcutImport.addedNames(existing: existing, names: ["timer", "Workout"])
                == ["Workout"]
        )
    }

    @Test("renaming a shortcut reads as delete + re-add, dropping the old toggle")
    func renameIsDeletePlusReAdd() {
        // Identity is the name, so a renamed shortcut is a new name (input off)
        // and the old name — with its toggle — is pruned (ADR 0007 corollary).
        let existing = [ShortcutEntry(name: "Old Name", acceptsInput: true)]
        let entries = ShortcutImport.reconcile(existing: existing, names: ["New Name"])
        #expect(entries == [ShortcutEntry(name: "New Name", acceptsInput: false)])
    }

    // MARK: - Alias survival (issue #198)

    @Test("a re-sync preserves a survivor's alias alongside its toggle")
    func reSyncPreservesAlias() {
        // The alias rides the name-keyed store exactly as `acceptsInput` does
        // (issue #198): a survivor keeps its alias across a re-sync, matched
        // case-insensitively by name.
        let existing = [
            ShortcutEntry(name: "Translate", acceptsInput: true, alias: "tr"),
            ShortcutEntry(name: "Scan", acceptsInput: false, alias: nil),
        ]
        let entries = ShortcutImport.reconcile(existing: existing, names: ["translate", "Scan"])
        #expect(entries == [
            // "translate" survives and keeps *both* its toggle and its alias.
            ShortcutEntry(name: "translate", acceptsInput: true, alias: "tr"),
            // "Scan" survives with no alias, unchanged.
            ShortcutEntry(name: "Scan", acceptsInput: false, alias: nil),
        ])
    }

    @Test("a removed shortcut drops with its alias; a fresh import arrives alias-less")
    func removalAndFreshImportDropAlias() {
        // A name absent from the payload is pruned, taking its alias with it; a
        // renamed shortcut (a new name, since identity is the name) arrives fresh —
        // input off and no alias, the same documented trade-off as the toggle.
        let existing = [
            ShortcutEntry(name: "Old Name", acceptsInput: true, alias: "old"),
            ShortcutEntry(name: "Gone", acceptsInput: false, alias: "g"),
        ]
        let entries = ShortcutImport.reconcile(existing: existing, names: ["New Name"])
        #expect(entries == [ShortcutEntry(name: "New Name", acceptsInput: false, alias: nil)])
    }

    @Test("normalizedAlias trims and collapses a blank to nil — the shared set/unset rule")
    func normalizedAliasSetVsUnset() {
        // The one place the *set vs unset* rule lives, shared by the Shortcuts page's
        // field writer and the `Action.shortcut` factory (issue #198).
        #expect(ShortcutEntry.normalizedAlias("  tr  ") == "tr")
        #expect(ShortcutEntry.normalizedAlias("tr") == "tr")
        #expect(ShortcutEntry.normalizedAlias("   ") == nil)
        #expect(ShortcutEntry.normalizedAlias("") == nil)
        #expect(ShortcutEntry.normalizedAlias(nil) == nil)
    }

    @Test("a pre-#198 payload without the alias key decodes as no alias")
    func decodesLegacyPayloadWithoutAlias() throws {
        // The `alias` field is optional so a stored set written before #198 (only
        // `name`/`acceptsInput`) still decodes — the missing key reads as no alias
        // rather than failing, the forward-compat the `acceptsInput` default gives.
        let legacy = #"[{"name":"Timer","acceptsInput":true}]"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([ShortcutEntry].self, from: legacy)
        #expect(decoded == [ShortcutEntry(name: "Timer", acceptsInput: true, alias: nil)])
    }
}
