import UIKit
import QuickieCore

// The input-collecting run of a Shortcut Action as a `Capture` recipe (CONTEXT.md
// → Shortcut Action; issue #46). When a shortcut's `acceptsInput` toggle is on
// (set on the Shortcuts management page in #45), running it collects one optional
// `text` Argument through the same breadcrumb engine New Reminder / New Event use,
// then fires `shortcuts://x-callback-url/run-shortcut` with that text as the
// shortcut's input. A shortcut with the toggle off never reaches here — it fires
// immediately through `RootView.perform` with no input.
//
// Running a shortcut needs no permission, so `access` is always `.ready` and the
// primer/denial affordances are never shown. The hand-off to the Shortcuts app is
// its own feedback (Quickie leaves the foreground), so it reports no confirmation
// toast — the same "the outcome speaks for itself" case as New Event's editor mode.
struct ShortcutCapture: Capture {
    /// The shortcut's name — its identity and the x-callback `name` (ADR 0007).
    let name: String

    /// No permission gate: running a Shortcut is always available.
    var access: CaptureAccess { .ready }

    /// Never reached (`access` is always `.ready`); granted by definition.
    func requestAccess() async -> Bool { true }

    /// The input-accepting Shortcut Action, which declares the single optional
    /// `text` Argument the breadcrumb collects (issue #46).
    func makeAction() async -> Action {
        .shortcut(name: name, acceptsInput: true)
    }

    /// Fires the shortcut at the platform edge: build the x-callback-url run
    /// (`ShortcutRun.runURL`) with the collected text as input and open it. The
    /// returned output comes back later on the inbound `quickie://shortcut-result`
    /// route (handled in `RootView`), not here, so this reports no toast.
    func perform(_ outcome: ActionOutcome) async -> CaptureConfirmation? {
        guard case .runShortcut(let name, let input) = outcome else { return nil }
        let url = ShortcutRun.runURL(name: name, input: input)
        await MainActor.run { UIApplication.shared.open(url) }
        return nil
    }

    /// No permission affordances are ever shown, so the copy is unused; the default
    /// empty wording keeps the generic bar happy.
    var copy: CaptureCopy { CaptureCopy() }
}
