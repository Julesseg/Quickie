import AppIntents
import SwiftUI
import WidgetKit
import QuickieCore

/// The configurable **Action control** (CONTEXT.md → Action control; ADR 0027): a
/// Control Center control beside the static Quick Capture control (`QuickCaptureControl`,
/// #125) that runs **one** user-chosen Action, picked from the same eligible catalog
/// the [[Actions widget]] draws from. It wears the chosen action's own glyph and title
/// in Control Center.
///
/// **Execution — tap-equivalent open, not the widget's three-way split.** A Control
/// Center control body is a *single, non-branching* `ControlWidgetTemplate`: WidgetKit's
/// `ControlWidgetTemplateBuilder` has no `buildEither`, so the body can't `switch` on the
/// resolved lane to pick a per-lane intent the way a widget grid cell (an ordinary
/// SwiftUI `Button`) can — and a single intent can't span the lanes either (one
/// `perform()` has one return type, so it can't mix the copy lane's `.result()` with the
/// hand-off lane's `.result(opensIntent:)`, and `openAppWhenRun` is `static`, not
/// per-lane). So the control runs the one intent that works for **every** eligible
/// action: `RunFavoriteInAppIntent` (`openAppWhenRun`), which opens Quickie and runs the
/// action **tap-equivalently** through the shared inbox door — a Snippet copies, a
/// Quicklink opens the browser, a capture opens its breadcrumb, each the correct outcome,
/// but via a brief app open rather than the widget's in-place / direct hand-off. The
/// Frecency credit rides the app's ordinary tap path (not the outbox), since the run
/// lands in-app. The [[Actions widget]] keeps the full three-way split — only the control
/// is constrained. Unconfigured or **stale** (the chosen action was deleted or
/// [[Disabled]], so the catalog join misses) the id resolves to `nil` and the control
/// falls back to the app glyph and a clean focused Home — never inert, never an error.
struct ActionControl: ControlWidget {
    static let kind = EligibleActionCatalogStore.controlKind

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: ActionControlValueProvider()) { (action: WidgetAction?) in
            // One non-branching template: open Quickie and run the chosen action
            // tap-equivalently. A `nil` action (unconfigured or stale) carries a `nil`
            // id, which `RunFavoriteInAppIntent` routes to the clean-Home entry.
            ControlWidgetButton(action: RunFavoriteInAppIntent(actionID: action?.id)) {
                ActionControlLabel(action: action)
            }
        }
        .displayName("Quickie Action")
        .description("Run a chosen Quickie Action from Control Center.")
    }
}

/// The control's label — the chosen action's title beside its provider glyph, or the
/// app glyph and "Quickie" when nothing resolves. Drawn from the resolved
/// `WidgetAction` alone, so Control Center shows what the app published (ADR 0027).
private struct ActionControlLabel: View {
    let action: WidgetAction?

    var body: some View {
        Label {
            Text(action?.title ?? "Quickie")
        } icon: {
            Image(systemName: action?.glyph ?? QuickieGlyph.app)
        }
    }
}

/// The single chosen Action's configuration (ADR 0027): one entity from the shared
/// picker, or none. Stores the **id only** (inside the entity) — the value provider
/// re-joins it against the live catalog, so a deleted or disabled choice degrades.
struct ActionControlConfigIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Action"
    static let description = IntentDescription("Pick the Action this control runs.")

    @Parameter(title: "Action")
    var action: EligibleActionEntity?
}

/// Resolves the configured id against the published catalog (ADR 0027) — the
/// control's render-time join, mirroring the Actions widget timeline. Returns the
/// resolved `WidgetAction` (for the label and the run id), or `nil` when unconfigured
/// or the chosen id no longer resolves, which the control body renders as the
/// app-glyph clean-Home fallback.
struct ActionControlValueProvider: AppIntentControlValueProvider {
    /// The gallery preview: no configuration yet, so the app-glyph fallback — what an
    /// unconfigured control looks like before the user picks an Action.
    func previewValue(configuration: ActionControlConfigIntent) -> WidgetAction? {
        nil
    }

    func currentValue(configuration: ActionControlConfigIntent) async throws -> WidgetAction? {
        guard let id = configuration.action?.id else { return nil }
        return EligibleActionCatalog.resolve(ids: [id], in: EligibleActionCatalogStore.load()).first
    }
}
