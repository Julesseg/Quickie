import Foundation
import UIKit
import Observation

/// The App-side bridge for Clipboard prefill (CONTEXT.md → Clipboard prefill;
/// ADR 0002). The platform-agnostic `ClipboardPrefill` decides *whether* to
/// offer the paste chip; this model supplies the one input that decision needs
/// from iOS — the silent metadata answer to "does the clipboard hold text?".
///
/// It reads `UIPasteboard.general.hasStrings`, which is metadata only: it never
/// fires the system "pasted from…" banner and never exposes the content. The
/// content is read solely when the user taps the paste control (see
/// `ClipboardPasteChip`), never ambiently. We re-check on `didBecomeActive` so
/// text copied elsewhere while Quickie was backgrounded is reflected on return.
@MainActor
@Observable
final class ClipboardPrefillModel {
    /// The launch-time (and resume-time) answer to the silent `hasStrings`
    /// check. Drives the chip's visibility; carries no clipboard content.
    private(set) var clipboardHasText: Bool = false

    // Written once at init, read again only in the nonisolated deinit; see
    // KeyboardLayoutModel for the same single-writer pattern.
    @ObservationIgnored private nonisolated(unsafe) var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The silent metadata check. `hasStrings` inspects only whether text is
    /// present — no content read, no banner.
    private func refresh() {
        clipboardHasText = UIPasteboard.general.hasStrings
    }
}
