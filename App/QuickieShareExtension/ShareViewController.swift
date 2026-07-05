import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import QuickieCore
import QuickieStoreKit

/// The Share Extension's principal controller — deliberately a thin shell (ADR
/// 0022): it unpacks the shared items into plain values, hands them to
/// `ShareModel` (which leans on `QuickieCore.ShareClassification` for the
/// rules), and hosts the SwiftUI sheet. Everything decision-shaped lives in
/// Core where the Linux `swift test` gate covers it.
final class ShareViewController: UIViewController {
    private var model: ShareModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = ShareModel(
            complete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        )
        self.model = model

        let host = UIHostingController(rootView: ShareSheetView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        model.load(items: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
    }
}

/// The extension's state: classify the shared payload, hold the editable
/// Quicklink draft, and write it through the shared App Group store — or
/// refuse with an error when that store isn't there (ADR 0022: a silent write
/// to a container the app can never read is a fake "saved").
@Observable @MainActor
final class ShareModel {
    /// The editable fields the classification sheet collects, pre-filled from
    /// the shared item (name from the page title or host — Core's rule).
    struct QuicklinkDraft {
        var title = ""
        var urlString = ""
        var alias = ""
    }

    enum Phase {
        case loading
        /// The URL branch's classification sheet is up, editing `draft`.
        case editing
        /// The payload has no branch this slice (bare text lands in its own
        /// slice; odd mixed payloads are guarded here defensively).
        case unsupported(String)
        /// The shared store refused — App Group missing or the write failed.
        /// Terminal: nothing was saved, and the sheet says so.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    var draft = QuicklinkDraft()

    private let complete: () -> Void
    private let cancelRequest: () -> Void

    init(complete: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.complete = complete
        self.cancelRequest = cancel
    }

    /// Mirrors the in-app Quicklink editor's gate: a name, a URL, and no
    /// `{placeholder}` (a templated URL is a Custom Action, not a Quicklink).
    var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !Action.templateContainsPlaceholder(draft.urlString)
    }

    func load(items: [NSExtensionItem]) {
        // The page title, when the sharing app sent one along (Safari does);
        // Core treats a "title" that just restates the URL as absent.
        let pageTitle = items.lazy
            .compactMap { $0.attributedTitle?.string ?? $0.attributedContentText?.string }
            .first

        let providers = items.flatMap { $0.attachments ?? [] }

        // URL wins even when the sharer also supplies plain text (ADR 0022) —
        // Safari sends both for a page share.
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            Task { await classifyURL(from: urlProvider, pageTitle: pageTitle) }
        } else if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            Task { await classifyText(from: textProvider) }
        } else {
            // The activation rule shouldn't let this in; guard defensively.
            phase = .unsupported("Quickie can save a link or text from the share sheet.")
        }
    }

    private func classifyURL(from provider: NSItemProvider, pageTitle: String?) async {
        guard let url = try? await provider.loadURL() else {
            phase = .unsupported("Quickie couldn't read the shared link.")
            return
        }
        // Files are out of scope (the activation rule keeps them away; a
        // file URL inside an odd mixed payload is refused here).
        guard !url.isFileURL else {
            phase = .unsupported("Quickie can't save files — share a link instead.")
            return
        }
        startEditing(url: url, pageTitle: pageTitle)
    }

    private func classifyText(from provider: NSItemProvider) async {
        guard let text = try? await provider.loadText() else {
            phase = .unsupported("Quickie couldn't read the shared text.")
            return
        }
        // Text that *is* a web URL takes the URL branch (ADR 0022 — the
        // "I shared a link" reading). Bare text becomes a Snippet or Pile
        // entry in the text-branch slice; until that lands it is refused
        // honestly rather than half-saved.
        if let url = ShareClassification.webURL(fromSharedText: text) {
            startEditing(url: url, pageTitle: nil)
        } else {
            phase = .unsupported("Saving shared text is coming soon. Quickie can save a link today.")
        }
    }

    private func startEditing(url: URL, pageTitle: String?) {
        draft = QuicklinkDraft(
            title: ShareClassification.quicklinkName(pageTitle: pageTitle, url: url),
            urlString: url.absoluteString,
            alias: ""
        )
        phase = .editing
    }

    /// Writes the Quicklink through the shared App Group container and
    /// completes the request — or surfaces the refusal. The error paths never
    /// call `complete`, so a failure is never reported back as a save.
    func save() {
        do {
            let container = try QuickieStore.appGroupContainer()
            let context = ModelContext(container)
            let alias = draft.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(StoredQuicklink(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                urlString: draft.urlString.trimmingCharacters(in: .whitespacesAndNewlines),
                alias: alias.isEmpty ? nil : alias
            ))
            try context.save()
            complete()
        } catch QuickieStore.AppGroupStoreError.appGroupUnavailable {
            phase = .failed("Quickie's shared storage isn't available, so the link can't be saved. Nothing was saved.")
        } catch {
            phase = .failed("Saving the link failed: \(error.localizedDescription). Nothing was saved.")
        }
    }

    func cancel() {
        cancelRequest()
    }
}

extension NSItemProvider {
    /// The shared URL, bridged to a plain `Sendable` value on whatever queue
    /// the provider calls back on. `@MainActor` keeps the provider itself from
    /// ever crossing an isolation boundary — only the `Sendable` result does —
    /// which is the one shape that stays simple under strict concurrency.
    @MainActor
    func loadURL() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: url) }
            }
        }
    }

    /// The shared plain text, bridged like `loadURL`.
    @MainActor
    func loadText() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: String.self) { text, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: text) }
            }
        }
    }
}
