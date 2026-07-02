import SwiftUI
import SwiftData
import QuickieCore

/// The Pile provider's **Management page** (CONTEXT.md → Management page;
/// ADR 0019), reached from the Settings hub's Providers list — distinct from
/// the Pile *entries* page (`PileView`), which stays pure content (tap stages,
/// swipe discards; ADR 0018's carve-out). This page is the configuration side:
/// Options lead, and the actions section lists each entry with its
/// **enable/disable toggle** (the instance-level Disabled switch, issue #68)
/// plus swipe-to-delete — disable hides the entry from results/Recents/
/// Favorites while it stays in the Pile; delete discards it for good.
struct PileProviderPage: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredPileEntry.createdAt, order: .reverse) private var entries: [StoredPileEntry]

    /// The instance-level Disabled state each row's toggle flips (issue #68).
    let enablement: EnablementStore

    /// The rows safe to render this instant, mirroring `PileView.liveEntries`:
    /// a deleted entry can linger in the `@Query` snapshot after its commit,
    /// and reading `text`/`id` on it traps once SwiftData frees the snapshot.
    private var liveEntries: [StoredPileEntry] {
        entries.filter { $0.modelContext != nil }
    }

    // Pushed onto the launcher's navigation stack — the back chevron and
    // edge-swipe handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        List {
            ProviderOptionsSection(provider: .pile)

            Section {
                if liveEntries.isEmpty {
                    Text("The Pile is empty")
                        .foregroundStyle(.secondary)
                }
                ForEach(liveEntries) { entry in
                    HStack(spacing: 12) {
                        Text(entry.text)
                            .font(.body)
                            .foregroundStyle(enablement.isDisabled(entry.actionID) ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        // Disabling keeps the entry in the Pile but hides it
                        // from every launcher surface — reversible, unlike
                        // swipe-to-delete.
                        Toggle(
                            "Enabled",
                            isOn: Binding(
                                get: { !enablement.isDisabled(entry.actionID) },
                                set: { _ in enablement.toggleDisabled(entry.actionID) }
                            )
                        )
                        .labelsHidden()
                        .accessibilityIdentifier("pile-enabled.\(entry.id)")
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("Saved queries")
            } footer: {
                Text("Disable an entry to hide it from results without removing it from the Pile. Swipe to delete it for good. To view and stage entries, type \u{201C}pile\u{201D}.")
            }
        }
        .navigationTitle("Pile")
    }

    /// Swipe-to-delete discards an entry without staging it — the same verb as
    /// the entries page. Commit synchronously, like every Pile delete: one left
    /// to autosave can invalidate a model the launcher's query snapshot still
    /// lists, trapping the next engine rebuild.
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(liveEntries[index])
        }
        try? context.save()
    }
}
