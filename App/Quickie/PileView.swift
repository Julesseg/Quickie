import SwiftUI
import SwiftData
import QuickieCore
import QuickieStoreKit

/// The Pile **entries** page (CONTEXT.md → Pile; ADR 0018): every
/// saved-for-later query text, newest first, reached by the typed "Pile"
/// command row. The entries are temporary, so this page is purely content to
/// view and act on — tapping an entry **stages** it, exactly like its result
/// row (the launcher pops back, the input becomes the saved text, and the
/// entry leaves the Pile), and swipe-to-delete is the counterpart, **discard
/// without staging**. Deliberately NOT the Pile provider's settings page
/// (reached from the Settings hub's Providers list), and so no Options
/// section: content here, configuration there.
///
/// Pile entries deliberately carry **no per-entry Enabled toggle** (issue #68
/// scoped them out): an entry is a deferred query you either act on or keep
/// waiting in results — "kept but hidden" is not a state this data has. Its
/// verbs are stage and discard, nothing in between.
struct PileView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredPileEntry.createdAt, order: .reverse) private var entries: [StoredPileEntry]

    /// The rows safe to render this instant, mirroring the launcher's
    /// `livePileEntries`: a deleted entry can linger in the `@Query` snapshot
    /// after its commit, and reading `text`/`id` on it traps once SwiftData
    /// frees the snapshot. `modelContext == nil` is the invalidation check that
    /// never touches the backing data itself.
    private var liveEntries: [StoredPileEntry] {
        entries.filter { $0.modelContext != nil }
    }

    /// The header line summarizing the Pile (CONTEXT.md → Pile, aging paragraph;
    /// issue #164): entry count + the oldest entry's age. `nil` for an empty Pile
    /// — no header, never "0 saved". Entries are newest-first, so the oldest is
    /// the last live row. Read as of `now` so it ages with the rows below it.
    private func headerText(asOf now: Date) -> String? {
        PileHeader.text(
            entryCount: liveEntries.count,
            oldest: liveEntries.last?.createdAt,
            asOf: now
        )
    }

    /// Stages a tapped entry (CONTEXT.md → Stage). The launcher owns the query,
    /// the navigation stack, and the consume, so the page only reports the tap —
    /// the same defer-to-the-owner shape as the result list's `onRun`.
    let onStage: (StoredPileEntry) -> Void

    // Pushed onto the launcher's navigation stack — the back chevron and
    // edge-swipe handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        Group {
            if liveEntries.isEmpty {
                ContentUnavailableView(
                    "The Pile is empty",
                    systemImage: "tray",
                    description: Text("Type a query you don't want to deal with right now and pick “Save for later” — it lands here until you stage it again.")
                )
            } else {
                // One `now` for the whole page so the header and every row age
                // against the same instant.
                let now = Date()
                List {
                    Section {
                        ForEach(liveEntries) { entry in
                            Button {
                                onStage(entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.text)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                    // The muted relative-age subtitle every entry
                                    // wears — the same optional-subtitle anatomy a
                                    // file row uses for its relative path, always
                                    // shown and never opacity (CONTEXT.md → Pile).
                                    Text(RelativeAge.label(from: entry.createdAt, asOf: now))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pile-row-\(entry.id)")
                        }
                        .onDelete(perform: delete)
                    } header: {
                        if let headerText = headerText(asOf: now) {
                            // Keep the authored casing: a List section header
                            // otherwise uppercases to "3W AGO", fighting the
                            // muted "3w ago" the ages elsewhere read as.
                            Text(headerText)
                                .textCase(nil)
                                .accessibilityIdentifier("pile-header")
                        }
                    }
                }
            }
        }
        .navigationTitle("Pile")
    }

    /// Swipe-to-delete discards an entry without staging it — the entries
    /// page's second verb (per-row removal from the Result list is the deferred
    /// "Remove from Pile" secondary action).
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(liveEntries[index])
        }
        // Commit synchronously, like the launcher's stage-consume: a delete left
        // to autosave can invalidate a model the launcher's query snapshot still
        // lists, trapping the next engine rebuild.
        try? context.save()
    }
}
