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
/// draft for whichever branch it landed in, and write it through the shared App
/// Group store — or refuse with an error when that store isn't there (ADR 0022:
/// a silent write to a container the app can never read is a fake "saved").
@Observable @MainActor
final class ShareModel {
    /// The editable fields the URL branch's sheet collects, pre-filled from the
    /// shared item (name from the page title or host — Core's rule).
    struct QuicklinkDraft {
        var title = ""
        var urlString = ""
        var alias = ""
    }

    /// Which record the text branch will save (CONTEXT.md → Share Extension):
    /// a titled, reusable [[Snippet]] (the default) or a titleless [[Pile]]
    /// entry, chosen by the sheet's segmented switch.
    enum TextKind: Hashable {
        case snippet
        case pile
    }

    /// The editable fields the text branch's sheet collects. `title` seeds the
    /// Snippet name from the first line of the shared text (Core's rule) and is
    /// ignored when the user switches to Pile — a Pile entry is just `text`.
    struct TextDraft {
        var kind: TextKind = .snippet
        var title = ""
        var text = ""
    }

    enum Phase {
        case loading
        /// The URL branch's classification sheet is up, editing `quicklinkDraft`.
        case editingQuicklink
        /// The text branch's sheet is up (Snippet ⇄ Pile), editing `textDraft`.
        case editingText
        /// The payload has no branch (odd mixed payloads are guarded here
        /// defensively; the activation rule keeps images/files out entirely).
        case unsupported(String)
        /// The shared store refused — App Group missing or the write failed.
        /// Terminal: nothing was saved, and the sheet says so.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    var quicklinkDraft = QuicklinkDraft()
    var textDraft = TextDraft()

    /// Set only for the ambiguous "plain text that is itself a web URL" payload
    /// (issue #103): the Quicklink branch is the default, but the sheet can flip
    /// to the text branch and back. These hold the two seeds; both stay `nil`
    /// for an unambiguous payload (a genuine `public.url` attachment, or non-URL
    /// text), where no switch is offered.
    private var switchableURL: URL?
    private var switchableText: String?

    /// Whether the active sheet offers a switch to the *other* branch — only the
    /// URL-shaped-plain-text payload does (issue #103).
    var canSwitchBranch: Bool { switchableURL != nil && switchableText != nil }

    private let complete: () -> Void
    private let cancelRequest: () -> Void

    init(complete: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.complete = complete
        self.cancelRequest = cancel
    }

    /// Whether the active sheet has enough to save. The URL branch mirrors the
    /// in-app Quicklink editor's gate (a name, a URL, and no `{placeholder}` —
    /// a templated URL is a Custom Action, not a Quicklink); the text branch
    /// mirrors the Snippet editor (a title *and* a body) for a Snippet and just
    /// non-empty text for a titleless Pile entry.
    var canSave: Bool {
        switch phase {
        case .editingQuicklink:
            return !quicklinkDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !quicklinkDraft.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !Action.templateContainsPlaceholder(quicklinkDraft.urlString)
        case .editingText:
            let hasText = !textDraft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            switch textDraft.kind {
            case .snippet:
                return hasText
                    && !textDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .pile:
                return hasText
            }
        case .loading, .unsupported, .failed:
            return false
        }
    }

    func load(items: [NSExtensionItem]) {
        // The page title, when the sharing app sent one along (Safari does);
        // Core treats a "title" that just restates the URL as absent.
        let pageTitle = items.lazy
            .compactMap { $0.attributedTitle?.string ?? $0.attributedContentText?.string }
            .first

        let providers = items.flatMap { $0.attachments ?? [] }
        let urlProvider = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }
        let textProvider = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        // Where a raw *selection* lands when it isn't vended as a plain-text
        // attachment (Safari, Books, Notes put the highlighted text here).
        let contentText = firstNonEmptyContentText(in: items)

        Task {
            await classify(
                urlProvider: urlProvider,
                textProvider: textProvider,
                contentText: contentText,
                pageTitle: pageTitle
            )
        }
    }

    /// The first non-empty `attributedContentText` across the shared items —
    /// where a raw text *selection* lands (as opposed to a `public.plain-text`
    /// attachment, which is how an app vending a whole `String` delivers it).
    private func firstNonEmptyContentText(in items: [NSExtensionItem]) -> String? {
        items.lazy
            .compactMap { $0.attributedContentText?.string }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Load whatever the payload carries, then let Core's pure rule pick the
    /// branch (ADR 0022). A genuine shared/selected string wins over the page
    /// URL that Safari's highlight-share hands over alongside it — so a text
    /// selection reaches the text sheet even though a `public.url` attachment
    /// is also present. A shared string that is itself a web URL, and a page
    /// share with no selection, both land on the Quicklink branch.
    private func classify(
        urlProvider: NSItemProvider?,
        textProvider: NSItemProvider?,
        contentText: String?,
        pageTitle: String?
    ) async {
        // Prefer a plain-text attachment (a whole shared `String`) over the
        // item's content text; either is a genuine selection to Core.
        let sharedText: String?
        if let textProvider {
            sharedText = (try? await textProvider.loadText()) ?? contentText
        } else {
            sharedText = contentText
        }

        let attachedURL: URL?
        if let urlProvider {
            attachedURL = try? await urlProvider.loadURL()
        } else {
            attachedURL = nil
        }

        switch ShareClassification.route(sharedText: sharedText, attachedURL: attachedURL) {
        case .text(let text):
            startEditingText(text)
        case .quicklink(let url, let textFallback):
            // Files are out of scope (the activation rule keeps them away; a
            // file URL inside an odd mixed payload is refused here).
            guard !url.isFileURL else {
                phase = .unsupported("Quickie can't save files — share a link instead.")
                return
            }
            if let textFallback {
                // Plain text that is itself a URL: default to the link, but keep
                // both seeds so the sheet can switch to the text branch (#103).
                switchableURL = url
                switchableText = textFallback
            }
            // A page URL from the attachment keeps its page title; a URL the
            // shared *text* itself was (`textFallback` present) has none.
            startEditingQuicklink(url: url, pageTitle: textFallback == nil ? pageTitle : nil)
        case .unsupported:
            // The activation rule shouldn't let anything else in; guard
            // defensively.
            phase = .unsupported("Quickie can save a link or text from the share sheet.")
        }
    }

    private func startEditingQuicklink(url: URL, pageTitle: String?) {
        quicklinkDraft = QuicklinkDraft(
            title: ShareClassification.quicklinkName(pageTitle: pageTitle, url: url),
            urlString: url.absoluteString,
            alias: ""
        )
        phase = .editingQuicklink
    }

    private func startEditingText(_ text: String) {
        // Default to Snippet, its title pre-filled from the first line (Core's
        // rule) and its body the whole shared text; switching to Pile drops the
        // title. The body keeps the shared text verbatim apart from trimming the
        // surrounding whitespace, matching the in-app editors' seed behaviour.
        textDraft = TextDraft(
            kind: .snippet,
            title: ShareClassification.snippetTitle(fromSharedText: text),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        phase = .editingText
    }

    /// Flip the ambiguous URL-shaped-text payload to the text branch (issue
    /// #103), re-seeding the Snippet/Pile draft from the original shared string.
    /// A no-op unless the payload is switchable.
    func switchToText() {
        guard let text = switchableText else { return }
        startEditingText(text)
    }

    /// Flip back to the Quicklink branch, re-seeding from the URL the shared text
    /// parsed as. The text-derived URL never carries a page title.
    func switchToQuicklink() {
        guard let url = switchableURL else { return }
        startEditingQuicklink(url: url, pageTitle: nil)
    }

    /// Writes the classified item through the shared App Group container and
    /// completes the request — or surfaces the refusal. The error paths never
    /// call `complete`, so a failure is never reported back as a save.
    func save() {
        do {
            let container = try QuickieStore.appGroupContainer()
            let context = ModelContext(container)
            switch phase {
            case .editingQuicklink:
                let alias = quicklinkDraft.alias.trimmingCharacters(in: .whitespacesAndNewlines)
                context.insert(StoredQuicklink(
                    title: quicklinkDraft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    urlString: quicklinkDraft.urlString.trimmingCharacters(in: .whitespacesAndNewlines),
                    alias: alias.isEmpty ? nil : alias
                ))
            case .editingText:
                let text = textDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                switch textDraft.kind {
                case .snippet:
                    context.insert(StoredSnippet(
                        title: textDraft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: text
                    ))
                case .pile:
                    context.insert(StoredPileEntry(text: text))
                }
            case .loading, .unsupported, .failed:
                // No editable draft to save; the Save button isn't shown here.
                return
            }
            try context.save()
            complete()
        } catch QuickieStore.AppGroupStoreError.appGroupUnavailable {
            phase = .failed("Quickie's shared storage isn't available, so nothing could be saved.")
        } catch {
            phase = .failed("Saving failed: \(error.localizedDescription). Nothing was saved.")
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
