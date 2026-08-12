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
                     ? "Install the companion Sync Shortcut, then run it to import your shortcuts. New imports start disabled; a re-sync rebuilds the list to match your library, keeping each \u{201C}accepts input\u{201D} setting."
                     : "New imports start disabled. A re-sync rebuilds the list to match your library, keeping each \u{201C}accepts input\u{201D} setting.")
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
                            HStack(spacing: 12) {
                                // The shortcut's customization appears as a leading
                                // badge on the management-page row (CONTEXT.md →
                                // Shortcut Action, Action color; issues #163, #243) —
                                // the same badge, tint, and weight the result rows
                                // wear, and the same show-when-either-is-set rule
                                // `CustomActionRow` uses, so an untouched import reads
                                // exactly as before.
                                if entry.normalizedGlyph != nil || entry.color != nil {
                                    ProviderBadge(kind: .shortcut, symbol: entry.normalizedGlyph, color: entry.color)
                                }
                                Text(entry.name)
                                    .foregroundStyle(
                                        enablement.isDisabled(Action.shortcutID(for: entry.name))
                                            ? .secondary : .primary
                                    )
                            }
                        }
                        .accessibilityIdentifier("shortcut-row.\(entry.name)")
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("Imported shortcuts")
                } footer: {
                    Text("Removing one here isn't permanent: a later re-sync re-adds it, disabled and without its alias, if it's still in your library.")
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
/// input** switch, the **appearance** row (issues #163, #243), and the optional
/// **Alias** field, each in its own explained section — the several controls a
/// single list row couldn't hold apart. Pushed from the Shortcuts page's
/// navigation rows, riding the launcher's stack like every other pushed page.
struct ShortcutDetailView: View {
    let name: String
    let store: ShortcutsStore
    let enablement: EnablementStore

    /// The shortcut's stable Action id — the same derivation the engine
    /// filters by (`Action.shortcutID(for:)`), so the toggle can't drift.
    private var actionID: String { Action.shortcutID(for: name) }

    /// The live entry, re-read on every access so a re-sync landing while this page
    /// is up (or a deletion) is reflected immediately rather than a stale snapshot.
    private var entry: ShortcutEntry? {
        store.entries.first(where: { $0.name == name })
    }

    /// Read live from the store: the entry can be re-synced while this page is
    /// up, and a deleted entry simply reads as input-off.
    private var acceptsInput: Bool {
        entry?.acceptsInput ?? false
    }

    /// The shortcut's current alias, read live from the store (like `acceptsInput`),
    /// bound to the field. Its setter routes through `ShortcutsStore.setAlias`, which
    /// normalizes a blank back to no alias — so clearing the field removes the alias
    /// and its pill (issue #198).
    private var aliasBinding: Binding<String> {
        Binding(
            get: { entry?.alias ?? "" },
            set: { store.setAlias($0, for: name) }
        )
    }

    /// The shortcut's chosen glyph, bound straight to the store — the shared
    /// `AppearancePickerView`'s binding, mirroring the Custom Action editor's
    /// `$def.glyph` (issues #163, #243).
    private var glyphBinding: Binding<String?> {
        Binding(
            get: { entry?.glyph },
            set: { store.setGlyph($0, for: name) }
        )
    }

    /// The shortcut's chosen Action color, bound the same way as `glyphBinding`.
    private var colorBinding: Binding<ActionColor?> {
        Binding(
            get: { entry?.color },
            set: { store.setColor($0, for: name) }
        )
    }

    /// The row's trailing summary — both parts when both are set ("Mail · Teal"),
    /// the one that is set otherwise, and "Default" when neither is. Mirrors
    /// `CustomActionEditorView.appearanceValueLabel` so the two appearance rows read
    /// identically.
    private var appearanceValueLabel: String {
        switch (symbolValueLabel, entry?.color?.label) {
        case ("None", nil): return "Default"
        case ("None", let color?): return color
        case (let symbol, nil): return symbol
        case (let symbol, let color?): return "\(symbol) · \(color)"
        }
    }

    /// The trailing value label's symbol half — the chosen symbol's human name, or
    /// "None" when unset, read through the same normalization the surfaces use.
    private var symbolValueLabel: String {
        guard let glyph = entry?.normalizedGlyph else { return "None" }
        return CustomActionGlyphCatalog.all.first { $0.name == glyph }?.label ?? glyph
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
                Text("This setting survives a re-sync.")
            }

            Section {
                Toggle("Accepts input", isOn: Binding(
                    get: { acceptsInput },
                    set: { _ in store.toggleAcceptsInput(name) }
                ))
                .accessibilityIdentifier("shortcut-accepts-input.\(name)")
            } footer: {
                Text("Turn on for a shortcut that takes text — Quickie collects the input before running it. The import can't tell on its own.")
            }

            Section {
                NavigationLink {
                    AppearancePickerView(glyph: glyphBinding, color: colorBinding, kind: .shortcut)
                } label: {
                    HStack(spacing: 12) {
                        // The same badge every surface renders (CONTEXT.md → Shortcut
                        // Action, Action color; issues #163, #243): the chosen symbol
                        // over the chosen colour, or the kind-derived glyph when None.
                        ProviderBadge(kind: .shortcut, symbol: entry?.normalizedGlyph, color: entry?.color)
                        Text("Symbol & Color")
                        Spacer(minLength: 8)
                        Text(appearanceValueLabel)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("shortcut-appearance-row")
            } footer: {
                Text("Give this shortcut its own symbol and color, shown everywhere it appears. Leave them as None and Default to use the ones Shortcuts provides.")
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
                Text("Another name to find this shortcut by. Its result rows wear the alias as a pill, and it survives a re-sync.")
            }
        }
        .navigationTitle(name)
    }
}
