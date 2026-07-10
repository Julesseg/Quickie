import AppIntents
import SwiftUI
import WidgetKit
import QuickieCore

/// The configurable **Action control** (CONTEXT.md → Action control; ADR 0027): a
/// Control Center control beside the static Quick Capture control (`QuickCaptureControl`,
/// #125) that runs **one** user-chosen Action, picked from the same eligible catalog
/// the [[Actions widget]] draws from.
///
/// It executes the same **three-way split** as a widget button — the control body
/// picks the button's intent by the resolved `WidgetExecution` lane: a Snippet copies
/// in-place, a Quicklink / no-input Shortcut hands off directly, anything
/// input-needing opens the app tap-equivalently — and wears the action's own glyph
/// and title in Control Center. Out-of-app runs credit Frecency through the same
/// shared outbox the widget buttons use (`FavoritesWidgetStore.recordRun`, inside the
/// button intents).
///
/// The chosen id lives in this control's `AppIntentControlConfiguration`
/// (`ActionControlConfigIntent`); the value provider joins it against the published
/// catalog every render. Unconfigured or **stale** (the chosen action was deleted or
/// [[Disabled]]) it falls back to the app glyph and a clean, focused Home open —
/// never inert, never an error (the ADR 0025 degrade, extended to the control).
struct ActionControl: ControlWidget {
    static let kind = EligibleActionCatalogStore.controlKind

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: ActionControlValueProvider()) { action in
            // The resolved lane picks the button's intent; a `nil` action (unconfigured
            // or stale) falls through to the clean-Home entry, app glyph and all.
            switch action?.execution {
            case .copySnippet(let id):
                ControlWidgetButton(action: CopyFavoriteSnippetIntent(actionID: id)) {
                    ActionControlLabel(action: action)
                }
            case .handOff(let url):
                ControlWidgetButton(action: OpenFavoriteIntent(url: url, recordingRunOf: action?.id)) {
                    ActionControlLabel(action: action)
                }
            case .openApp:
                ControlWidgetButton(action: RunFavoriteInAppIntent(actionID: action?.id)) {
                    ActionControlLabel(action: action)
                }
            case nil:
                // Unconfigured or stale: the app glyph, opening a clean focused Home
                // — the same `nil`-id fresh-entry the widget's empty cells ride.
                ControlWidgetButton(action: RunFavoriteInAppIntent(actionID: nil)) {
                    ActionControlLabel(action: nil)
                }
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
/// resolved `WidgetAction`, or `nil` when unconfigured or the chosen id no longer
/// resolves, which the control body renders as the app-glyph clean-Home fallback.
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
