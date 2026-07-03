import UIKit
import QuickieCore

// The breadcrumb run of a Custom Action as a `Capture` recipe (CONTEXT.md → Custom
// Action; ADR 0021). A Custom Action collects its `{name}` slots as ordered `text`
// Arguments through the same engine New Reminder / New Event / Shortcut input use,
// then percent-encodes each value into the URL template and opens the filled URL.
//
// Two ways in, both this recipe:
//   • verb-first — a name match starts the breadcrumb empty at Argument 1;
//   • fallback seed-and-commit — a fallback selection seeds the typed query as
//     Argument 1 (RootView passes it as the capture's `seed`), so a one-slot
//     fallback (web search) completes in one tap and a multi-slot one continues.
//
// Opening a URL needs no permission, so `access` is always `.ready` and the
// primer/denial affordances never show. The hand-off to another app (or the
// browser) is its own feedback, so a success reports no toast; an unopenable scheme
// — app-not-installed — reuses the same failure toast as the Shortcut x-error path
// (ADR 0021: no `canOpenURL` pre-flight, arbitrary user schemes can't be whitelisted).
struct CustomActionCapture: Capture {
    /// The pre-built Custom Action, whose `arguments` the breadcrumb drives and whose
    /// multi-step fill produces the `openURL` outcome.
    let action: Action

    /// No permission gate: opening a URL is always available.
    var access: CaptureAccess { .ready }

    /// Never reached (`access` is always `.ready`); granted by definition.
    func requestAccess() async -> Bool { true }

    /// The Custom Action to drive — already carries its slot Arguments and template.
    func makeAction() async -> Action { action }

    /// Opens the filled URL at the platform edge. `UIApplication.open` reports
    /// whether a handler existed: an unopenable scheme (the target app isn't
    /// installed) surfaces the failure toast, matching the Shortcut x-error path
    /// (ADR 0021). The `await` hops to the main actor `UIApplication` requires.
    func perform(_ outcome: ActionOutcome) async -> CaptureConfirmation? {
        guard case .openURL(let url) = outcome else { return nil }
        let opened = await UIApplication.shared.open(url)
        return opened ? nil : CaptureConfirmation(message: "Couldn't open", isError: true)
    }

    /// No permission affordances are ever shown, so the copy is unused; the default
    /// empty wording keeps the generic bar happy.
    var copy: CaptureCopy { CaptureCopy() }
}
