import SwiftUI
import QuickieCore

/// The **Shortcuts** management page (CONTEXT.md → Management page; issue #45):
/// the home for the user's imported Shortcut Actions. Reached by typing
/// "shortcuts" (its own full-screen page, **not** nested under Settings) and
/// pushed onto the launcher's navigation stack, so it adds no stack or Done
/// button of its own.
///
/// It lists each imported shortcut by name with a per-row **"accepts input"**
/// toggle — the only way Quickie learns a shortcut takes input, since import is
/// names-only — plus swipe-to-delete, and hosts the Sync-Shortcut **install** and
/// **re-sync** entry points. There is no manual add: the list is populated solely
/// by the Sync Shortcut import (ADR 0007).
struct ShortcutsView: View {
    @Environment(\.openURL) private var openURL

    let store: ShortcutsStore

    var body: some View {
        List {
            Section {
                Button {
                    if let url = ShortcutsStore.syncShortcutInstallURL { openURL(url) }
                } label: {
                    Label("Install Sync Shortcut", systemImage: "square.and.arrow.down")
                }
                // Disabled until a human publishes the companion Sync Shortcut and
                // supplies its iCloud share link (ADR 0007 HITL) — never open a
                // dead URL.
                .disabled(ShortcutsStore.syncShortcutInstallURL == nil)
                .accessibilityIdentifier("install-sync-shortcut")

                Button {
                    openURL(Self.reSyncURL)
                } label: {
                    Label("Re-sync now", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("resync-shortcuts")
            } header: {
                Text("Sync Shortcut")
            } footer: {
                Text(ShortcutsStore.syncShortcutInstallURL == nil
                     ? "Install the companion Sync Shortcut, then run it to import your shortcuts. Re-syncing rebuilds the list to match your library, keeping each \u{201C}accepts input\u{201D} setting."
                     : "Run the Sync Shortcut to import your shortcuts. Re-syncing rebuilds the list to match your library, keeping each \u{201C}accepts input\u{201D} setting.")
            }

            if store.entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No shortcuts yet",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        description: Text("Install and run the Sync Shortcut above to import your iOS Shortcuts. They'll show up here and in the result list.")
                    )
                }
            } else {
                Section {
                    ForEach(store.entries, id: \.name) { entry in
                        ShortcutRowView(
                            entry: entry,
                            onToggleAcceptsInput: { store.toggleAcceptsInput(entry.name) }
                        )
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("Imported shortcuts")
                } footer: {
                    Text("Turn on \u{201C}accepts input\u{201D} for a shortcut that takes text — Quickie can't tell from the import. Swipe to remove one; a later re-sync re-adds it if it's still in your library.")
                }
            }
        }
        .navigationTitle("Shortcuts")
    }

    /// A `shortcuts://` run URL for the installed companion Sync Shortcut — the
    /// re-sync entry point runs it in place, and it round-trips the fresh names
    /// back over `quickie://import`. Built with encoding so the name's space is
    /// safe. Falls back to the raw scheme string only if construction fails (it
    /// won't for this fixed name).
    private static var reSyncURL: URL {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: ShortcutsStore.syncShortcutName)]
        return components.url ?? URL(string: "shortcuts://run-shortcut")!
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            store.delete(store.entries[index].name)
        }
    }
}

/// One Shortcuts-page row: the shortcut's name and its "accepts input" toggle.
private struct ShortcutRowView: View {
    let entry: ShortcutEntry
    let onToggleAcceptsInput: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { entry.acceptsInput }, set: { _ in onToggleAcceptsInput() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("Accepts input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("shortcut-accepts-input.\(entry.name)")
    }
}
