import SwiftUI
import UniformTypeIdentifiers

/// The **Indexed Folders** management page (CONTEXT.md → Indexed Folder; issue
/// #49): where the user grants, lists, and revokes the folders Quickie is allowed
/// to search. Reached as the typed "Indexed Folders" command row and presented
/// full-screen — never chrome, consistent with Quicklinks / Fallbacks / Settings.
///
/// This is the access foundation of File Search; it does **no** searching yet.
/// **Add Folder** presents the system document picker in folder-selection mode; a
/// granted folder appears in the list and can be removed (revoking the grant). The
/// picker/store wiring is verified by the XCUITest CI job.
struct IndexedFoldersView: View {
    let store: IndexedFoldersStore

    @State private var importing = false

    // Pushed onto the launcher's navigation stack — the system back chevron and
    // edge-swipe handle dismissal, so this view adds no stack or Done button.
    var body: some View {
        List {
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
        .navigationTitle("Indexed Folders")
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
        for index in offsets {
            store.remove(store.grants[index].id)
        }
    }
}
