import SwiftUI
import QuickLook
import UIKit

/// A pending QuickLook preview of a File Search result (CONTEXT.md → File Search;
/// ADR 0015): the resolved `FileAccess` handle whose security-scoped folder access
/// is held open while previewing, plus a fresh identity so each open drives a
/// distinct `.sheet(item:)` presentation. Presenting QuickLook here — at the app
/// edge — keeps the Core pure: it only ever named the file by `(bookmarkID,
/// relativePath)`, and the app resolved that to a URL under the start/stop bracket.
struct FilePreviewRequest: Identifiable {
    let id = UUID()
    /// The live security-scoped access, released when the preview is dismissed.
    let access: FileAccess
}

/// Presents a file in **QuickLook** (`QLPreviewController`) — the File Search main
/// action (issue #51). QuickLook supplies its own chrome, including the **Share**
/// and open-in-place affordances, so those ride its built-in UI rather than the
/// deferred long-press secondary-action system (CONTEXT.md → Secondary action).
///
/// The security-scoped access to the granting folder is opened *before* this view
/// is presented (`IndexedFoldersStore.beginFileAccess`) and released when it
/// disappears, so QuickLook can read the file lazily throughout the preview.
struct FilePreview: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        // A stable identifier so the XCUITest can assert the preview appeared without
        // depending on QuickLook's own (localized, versioned) chrome.
        controller.view.accessibilityIdentifier = "file-quicklook"
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.fileURL = fileURL
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(fileURL: fileURL) }

    /// Feeds the single resolved file URL to QuickLook. One item — a File Search row
    /// opens exactly the file it names.
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var fileURL: URL
        init(fileURL: URL) { self.fileURL = fileURL }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}
