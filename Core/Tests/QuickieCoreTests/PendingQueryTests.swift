import Foundation
import Testing
@testable import QuickieCore

// A **Pending query** (CONTEXT.md → Pending query; issue #152) is unresolved
// input the user left in the root launcher when the app backgrounded: the app
// snapshots `(text?, timestamp)` to the App Group defaults at background time
// and decides at the next activation — warm or cold — by comparing timestamps
// (ADR 0031). No background timers; termination loses nothing. These tests pin
// what qualifies for the snapshot, how each return path resolves it, and the
// confirmation copy the auto-save flashes.
struct PendingQueryTests {

    // MARK: What qualifies at background time

    @Test("a plain non-empty root query snapshots with its text — the Pending query")
    func plainQuerySnapshotsWithText() {
        let at = Date(timeIntervalSince1970: 1_000)
        let pending = PendingQuery.snapshot(
            query: "do chores tonight", isCapturing: false, inFileSearch: false,
            autoSaveEnabled: true, at: at
        )
        #expect(pending == PendingQuery(text: "do chores tonight", backgroundedAt: at))
    }

    @Test("an empty or whitespace query snapshots without text — the window still resets state, but there is nothing to save")
    func emptyQuerySnapshotsWithoutText() {
        for query in ["", "   ", "\n"] {
            let pending = PendingQuery.snapshot(
                query: query, isCapturing: false, inFileSearch: false,
                autoSaveEnabled: true, at: .now
            )
            #expect(pending?.text == nil)
        }
    }

    @Test("a half-filled breadcrumb and the Search Files context snapshot without text — they reset after the window but save nothing (the Pile holds raw query texts only)")
    func scopedContextsSnapshotWithoutText() {
        let capturing = PendingQuery.snapshot(
            query: "buy milk", isCapturing: true, inFileSearch: false,
            autoSaveEnabled: true, at: .now
        )
        #expect(capturing?.text == nil)

        let filtering = PendingQuery.snapshot(
            query: "report.pdf", isCapturing: false, inFileSearch: true,
            autoSaveEnabled: true, at: .now
        )
        #expect(filtering?.text == nil)
    }

    @Test("toggle off snapshots nothing at all — today's behavior exactly: state preserved indefinitely")
    func disabledSnapshotsNothing() {
        let pending = PendingQuery.snapshot(
            query: "do chores tonight", isCapturing: false, inFileSearch: false,
            autoSaveEnabled: false, at: .now
        )
        #expect(pending == nil)
    }

    // MARK: How the next activation resolves it

    @Test("a plain open within the window restores — still mid-thought")
    func plainOpenWithinWindowRestores() {
        let at = Date(timeIntervalSince1970: 1_000)
        let pending = PendingQuery(text: "do chores tonight", backgroundedAt: at)
        let resolution = pending.resolution(at: at.addingTimeInterval(29), via: .plainOpen)
        #expect(resolution == .keep)
    }

    @Test("a plain open at or past the window commits the text to the Pile — moved on")
    func plainOpenPastWindowCommits() {
        let at = Date(timeIntervalSince1970: 1_000)
        let pending = PendingQuery(text: "do chores tonight", backgroundedAt: at)
        let resolution = pending.resolution(at: at.addingTimeInterval(PendingQuery.lifetime), via: .plainOpen)
        #expect(resolution == .reset(commit: "do chores tonight"))
    }

    @Test("an entry surface commits at any age — 'something new now' replaces today's silent discard")
    func entrySurfaceCommitsRegardlessOfAge() {
        let at = Date(timeIntervalSince1970: 1_000)
        let pending = PendingQuery(text: "do chores tonight", backgroundedAt: at)
        #expect(pending.resolution(at: at.addingTimeInterval(1), via: .entrySurface)
            == .reset(commit: "do chores tonight"))
    }

    @Test("a textless snapshot past the window resets without committing — clean Home, nothing written")
    func textlessSnapshotResetsWithoutCommit() {
        let at = Date(timeIntervalSince1970: 1_000)
        let pending = PendingQuery(text: nil, backgroundedAt: at)
        #expect(pending.resolution(at: at.addingTimeInterval(60), via: .plainOpen)
            == .reset(commit: nil))
        #expect(pending.resolution(at: at.addingTimeInterval(5), via: .plainOpen) == .keep)
        #expect(pending.resolution(at: at.addingTimeInterval(5), via: .entrySurface)
            == .reset(commit: nil))
    }

    @Test("a clock that moved backwards reads as within the window — never destroy typed text on a skewed clock")
    func backwardsClockKeeps() {
        let at = Date(timeIntervalSince1970: 1_000)
        let pending = PendingQuery(text: "do chores tonight", backgroundedAt: at)
        #expect(pending.resolution(at: at.addingTimeInterval(-3_600), via: .plainOpen) == .keep)
    }

    // MARK: The confirmation flash

    @Test("the auto-save confirmation quotes a short text whole")
    func confirmationQuotesShortTextWhole() {
        #expect(PendingQuery.savedConfirmation(for: "do chores") == "Saved “do chores” for later")
    }

    @Test("the confirmation truncates a long text with an ellipsis and quotes only its first line")
    func confirmationTruncatesLongText() {
        let long = String(repeating: "a", count: 100)
        #expect(PendingQuery.savedConfirmation(for: long) == "Saved “\(String(repeating: "a", count: 24))…” for later")

        let multiline = "Trip planning\ncompare ferries"
        #expect(PendingQuery.savedConfirmation(for: multiline) == "Saved “Trip planning…” for later")
    }

    // MARK: The App Group codec

    @Test("the snapshot round-trips through its codec — the App Group blob the app writes at background and reads at activation")
    func snapshotRoundTrips() throws {
        let pending = PendingQuery(text: "do chores tonight", backgroundedAt: Date(timeIntervalSince1970: 1_000))
        #expect(PendingQuery.decode(try #require(pending.encoded())) == pending)

        let textless = PendingQuery(text: nil, backgroundedAt: Date(timeIntervalSince1970: 2_000))
        #expect(PendingQuery.decode(try #require(textless.encoded())) == textless)

        #expect(PendingQuery.decode(nil) == nil)
        #expect(PendingQuery.decode(Data("garbage".utf8)) == nil)
    }

    // MARK: The Pile provider's declared toggle (ADR 0020)

    @Test("the Pile schema declares the auto-save toggle, default on, its copy stating the 30 seconds")
    func pileSchemaDeclaresAutoSaveToggle() throws {
        let option = try #require(
            ProviderID.pile.settingsSchema.first { $0.key == SettingsKey.pileAutoSave }
        )
        #expect(option.kind == .toggle(default: true))
        #expect(option.footer?.contains("30 seconds") == true)
    }
}
