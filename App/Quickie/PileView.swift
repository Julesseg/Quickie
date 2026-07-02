import SwiftUI
import SwiftData
import QuickieCore

/// The Pile provider's unified Management page (CONTEXT.md → Pile, Management
/// page; ADR 0018, ADR 0019): every saved-for-later query text, newest first,
/// reached by the typed "Pile" command row or the Settings hub's Providers
/// list. Replaces the "All Notes" library — there is no editor and no reader,
/// because a Pile entry is just a block of text. Tapping an entry **stages**
/// it, exactly like its result row: the launcher pops back, the input becomes
/// the saved text, and the entry leaves the Pile. Swipe-to-delete is the
/// counterpart — **discard without staging**. Like every provider page it
/// leads with the Options section, the entries beneath.
struct PileView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredPileEntry.createdAt, order: .reverse) private var entries: [StoredPileEntry]

    /// Stages a tapped entry (CONTEXT.md → Stage). The launcher owns the query,
    /// the navigation stack, and the consume, so the page only reports the tap —
    /// the same defer-to-the-owner shape as the result list's `onRun`.
    let onStage: (StoredPileEntry) -> Void

    // Pushed onto the launcher's navigation stack — the back chevron and
    // edge-swipe handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        // The unified page shape (ADR 0019): Options lead, the entries follow —
        // so the empty state sits inside the list, beneath the always-present
        // Options section.
        List {
            ProviderOptionsSection(provider: .pile)

            if entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "The Pile is empty",
                        systemImage: "tray",
                        description: Text("Type a query you don't want to deal with right now and pick “Save for later” — it lands here until you stage it again.")
                    )
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        Button {
                            onStage(entry)
                        } label: {
                            Text(entry.text)
                                .font(.body)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pile-row-\(entry.id)")
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Pile")
    }

    /// Swipe-to-delete discards an entry without staging it — the Pile page's
    /// whole job (per-row removal from the Result list is the deferred
    /// "Remove from Pile" secondary action).
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(entries[index])
        }
        // Commit synchronously, like the launcher's stage-consume: a delete left
        // to autosave can invalidate a model the launcher's query snapshot still
        // lists, trapping the next engine rebuild.
        try? context.save()
    }
}
