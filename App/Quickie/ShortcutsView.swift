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

    /// The instance-level Disabled state (issue #68): each row's Enabled toggle
    /// reversibly hides that one Shortcut Action from results/Recents/Favorites
    /// — softer than swipe-to-delete, which a re-sync would undo anyway.
    let enablement: EnablementStore

    /// Whether the Remove-all confirmation dialog is up — a bulk delete is the
    /// one destructive tap on this page, so it always asks first.
    @State private var confirmingRemoveAll = false

    var body: some View {
        List {
            // The unified page shape (ADR 0019; issue #66): Options lead; the
            // Sync Shortcut entry points below belong with them (CONTEXT.md →
            // Management page), and the imported shortcuts are the actions list.
            ProviderOptionsSection(provider: .shortcuts)

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

                // The bulk version of swipe-to-delete, kept beside the import
                // entry points it mirrors: one confirmed tap clears the whole
                // imported set (a re-sync rebuilds it from the library,
                // everything arriving as a fresh disabled import). Destructive,
                // so it always asks first — and the icon is tinted explicitly so
                // it reads as red as the text does.
                if !store.entries.isEmpty {
                    Button(role: .destructive) {
                        confirmingRemoveAll = true
                    } label: {
                        Label("Remove all", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("remove-all-shortcuts")
                    .confirmationDialog(
                        "Remove all imported shortcuts?",
                        isPresented: $confirmingRemoveAll,
                        titleVisibility: .visible
                    ) {
                        // Labeled distinctly from the triggering row so the two
                        // controls never read (or hit-test) as the same button.
                        Button("Remove all imported shortcuts", role: .destructive) {
                            store.removeAll()
                        }
                    } message: {
                        Text("This clears the imported list. Running the Sync Shortcut again re-imports whatever is in your library.")
                    }
                }
            } header: {
                Text("Sync Shortcut")
            } footer: {
                Text(ShortcutsStore.syncShortcutInstallURL == nil
                     ? "Install the companion Sync Shortcut, then run it to import your shortcuts. New imports start disabled. Re-syncing rebuilds the list to match your library, keeping each \u{201C}accepts input\u{201D} setting."
                     : "Run the Sync Shortcut to import your shortcuts. New imports start disabled. Re-syncing rebuilds the list to match your library, keeping each \u{201C}accepts input\u{201D} setting.")
            }

            if store.entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No shortcuts yet",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        description: Text("Install and run the Sync Shortcut above to import your iOS Shortcuts. They'll show up here — enable the ones you want in the result list.")
                    )
                }
            } else {
                Section {
                    // Each shortcut is a navigation row into its own settings page —
                    // its Enabled switch, Accepts-input toggle, and alias field, kept
                    // off the list row so several controls never read as one mushy
                    // control. The row carries only the name and swipe-to-delete.
                    ForEach(store.entries, id: \.name) { entry in
                        NavigationLink {
                            ShortcutDetailView(name: entry.name, store: store, enablement: enablement)
                        } label: {
                            Text(entry.name)
                                .foregroundStyle(
                                    enablement.isDisabled(Action.shortcutID(for: entry.name))
                                        ? .secondary : .primary
                                )
                        }
                        .accessibilityIdentifier("shortcut-row.\(entry.name)")
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("Imported shortcuts")
                } footer: {
                    Text("Imported shortcuts start disabled — tap one to enable it, mark whether it accepts input, and give it a search alias. Swipe to remove one; a later re-sync re-adds it (disabled again, no alias) if it's still in your library.")
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
        // Resolve the names from the current snapshot *before* mutating, then
        // delete by name: `store.delete` removes from `store.entries` in place, so
        // indexing into it mid-loop would shift the rows and delete the wrong ones
        // on a multi-row swipe/Edit delete.
        let names = offsets.map { store.entries[$0].name }
        for name in names {
            store.delete(name)
        }
    }
}

/// One imported shortcut's own settings page (issue #68 follow-up; issue #198):
/// the **Enabled** switch (the instance-level Disabled toggle), the **Accepts
/// input** switch, and the optional **Alias** field, each in its own explained
/// section — the several controls a single list row couldn't hold apart. Pushed
/// from the Shortcuts page's navigation rows, riding the launcher's stack like
/// every other pushed page.
struct ShortcutDetailView: View {
    let name: String
    let store: ShortcutsStore
    let enablement: EnablementStore

    /// The shortcut's stable Action id — the same derivation the engine
    /// filters by (`Action.shortcutID(for:)`), so the toggle can't drift.
    private var actionID: String { Action.shortcutID(for: name) }

    /// Read live from the store: the entry can be re-synced while this page is
    /// up, and a deleted entry simply reads as input-off.
    private var acceptsInput: Bool {
        store.entries.first(where: { $0.name == name })?.acceptsInput ?? false
    }

    /// The shortcut's current alias, read live from the store (like `acceptsInput`),
    /// bound to the field. Its setter routes through `ShortcutsStore.setAlias`, which
    /// normalizes a blank back to no alias — so clearing the field removes the alias
    /// and its pill (issue #198).
    private var aliasBinding: Binding<String> {
        Binding(
            get: { store.entries.first(where: { $0.name == name })?.alias ?? "" },
            set: { store.setAlias($0, for: name) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: Binding(
                    get: { !enablement.isDisabled(actionID) },
                    set: { _ in enablement.toggleDisabled(actionID) }
                ))
                .accessibilityIdentifier("shortcut-enabled.\(name)")
            } footer: {
                Text("Imported shortcuts start disabled. Turn on to show this shortcut in results, Recents, and Favorites; turn off to hide it again without removing it. It stays in the list and keeps this setting through a re-sync.")
            }

            Section {
                Toggle("Accepts input", isOn: Binding(
                    get: { acceptsInput },
                    set: { _ in store.toggleAcceptsInput(name) }
                ))
                .accessibilityIdentifier("shortcut-accepts-input.\(name)")
            } footer: {
                Text("Turn on for a shortcut that takes text — Quickie collects the input before running it, since the import can't tell.")
            }

            Section {
                // One optional alias — the single-alias convention the Custom Action
                // editor uses (a whole editor sheet for one word is ceremony, so it
                // lives here beside the toggles). Autocaps/correct off: an alias is a
                // terse handle, not prose.
                TextField("Alias", text: aliasBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("shortcut-alias-field.\(name)")
            } header: {
                Text("Alias")
            } footer: {
                Text("Give this shortcut another name to find it by — typing the alias surfaces it, and its result rows wear the alias as a pill. Clear the field to remove it. The alias survives a re-sync.")
            }
        }
        .navigationTitle(name)
    }
}
