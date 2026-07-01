import SwiftUI
import UniformTypeIdentifiers
import QuickieCore

/// The **File Search** provider page (ADR 0019; issue #66): the unified home of
/// the provider's options and its folder grants — the former standalone Indexed
/// Folders page (issue #49), folded in as this page's content. Here the user
/// grants, lists, and revokes the folders Quickie is allowed to search. Reached
/// by typing "File Search" (or "folders" / "file access") or from the hub's
/// Providers row, and presented full-screen — never chrome.
///
/// **Add Folder** presents the system document picker in folder-selection mode;
/// a granted folder appears in the list and can be removed (revoking the
/// grant). The picker/store wiring is verified by the XCUITest CI job.
struct IndexedFoldersView: View {
    let store: IndexedFoldersStore

    @State private var importing = false

    // Pushed onto the launcher's navigation stack — the system back chevron and
    // edge-swipe handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019; issue #66): Options lead, the
            // folder grants — this provider's content — follow.
            ProviderOptionsSection(provider: .fileSearch)

            Section {
                if store.grants.isEmpty {
                    Text("No folders yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.grants) { grant in
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(grant.displayName)
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("Indexed Folders")
            } footer: {
                Text("Folders Quickie is allowed to search. Access is stored on this device only and never synced.")
            }
        }
        .navigationTitle("File Search")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addFolder()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("add-indexed-folder")
                .accessibilityLabel("Add Folder")
            }
        }
        // The system document picker in folder-selection mode: a granted folder
        // arrives as a security-scoped URL the store bookmarks and persists.
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                store.addFolder(url)
            }
        }
    }

    private func addFolder() {
        // The system document picker can't be driven in CI, so under UI testing we
        // grant a real temporary folder directly — exercising add → list → remove
        // and relaunch-persistence against a resolvable bookmark. Normal runs present
        // the picker.
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            store.addTemporaryFolderForTesting()
        } else {
            importing = true
        }
    }

    private func delete(_ offsets: IndexSet) {
        // Snapshot ids first: `store.remove` shrinks `grants` synchronously, so
        // re-indexing per removal would target the wrong grant (or run past the
        // shortened array) on a multi-select delete.
        let ids = offsets.map { store.grants[$0].id }
        ids.forEach(store.remove)
    }
}
