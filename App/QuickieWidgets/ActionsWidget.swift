import AppIntents
import SwiftUI
import WidgetKit
import QuickieCore

/// The interactive **Actions widget** (CONTEXT.md → Actions widget; ADR 0027): a
/// second Home-Screen widget beside the [[Favorites widget]], the same 2×2 grid and
/// the same cell language (`WidgetActionGrid`), but showing a **user-chosen** list of
/// Actions instead of the pinned four.
///
/// The chosen list lives in *this placed instance's* `AppIntentConfiguration`
/// (`ActionsWidgetConfigIntent`), edited in the system Edit-Widget sheet — no in-app
/// page holds or mirrors it, and each placed instance carries its own list (ADR
/// 0027). The configuration stores **ids only**; the timeline joins them against the
/// app-published eligible-action catalog (`EligibleActionCatalog.resolve`) to render.
/// The widget process never opens SwiftData.
///
/// Degenerate states (never blank, never inert, never an error): an **unconfigured**
/// instance (no ids chosen) shows a one-line "choose actions" invitation deep-linking
/// to a clean focused Home; a chosen id that no longer resolves (deleted or
/// [[Disabled]]) **drops from the grid**, its slot rendering as the dashed empty-cell
/// tap target.
struct ActionsWidget: Widget {
    static let kind = EligibleActionCatalogStore.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ActionsWidgetConfigIntent.self, provider: ActionsProvider()) { entry in
            ActionsWidgetView(configured: entry.configured, actions: entry.actions)
        }
        .configurationDisplayName("Actions")
        .description("Run a chosen set of Quickie Actions without opening the app.")
        // The same two families the Favorites widget supports: glyph-only small,
        // titled medium — one cell language across both (ADR 0027).
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The per-instance configuration (ADR 0027): the ordered list of chosen Actions,
/// picked from the shared eligible-action catalog. The first four fill the grid in
/// chosen order; extras are ignored (clamped when the timeline resolves them).
struct ActionsWidgetConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Actions"
    static let description = IntentDescription("Pick the Actions this widget runs.")

    // Optional because AppIntents requires **every** `WidgetConfigurationIntent`
    // parameter to be optional (the ExtractAppIntentsMetadata build step rejects a
    // non-optional one); an unconfigured instance reads as `nil`, treated as "no
    // actions chosen" — the invitation state.
    @Parameter(title: "Actions")
    var actions: [EligibleActionEntity]?
}

/// Joins the configured ids against the published catalog every render (ADR 0027).
/// A one-shot `.never` timeline: the catalog only changes when the app rewrites it,
/// and every rewrite is paired with an explicit `reloadTimelines(ofKind:)`, so
/// WidgetKit never polls — the render stays as cheap as a projection should be.
private struct ActionsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ActionsTimelineEntry {
        // No configuration at placeholder time — show the empty grid shell.
        ActionsTimelineEntry(configured: false, actions: [])
    }

    func snapshot(for configuration: ActionsWidgetConfigIntent, in context: Context) async -> ActionsTimelineEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: ActionsWidgetConfigIntent, in context: Context) async -> Timeline<ActionsTimelineEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    /// The resolved entry: the chosen ids joined against the live catalog, clamped to
    /// the grid's four. `configured` records whether the user chose *anything* — the
    /// one bit that tells an unconfigured instance (→ invitation) from a configured
    /// instance whose ids all went stale (→ grid of dashed slots).
    private func entry(for configuration: ActionsWidgetConfigIntent) -> ActionsTimelineEntry {
        let ids = (configuration.actions ?? []).map(\.id)
        let resolved = EligibleActionCatalog.resolve(ids: ids, in: EligibleActionCatalogStore.load())
        return ActionsTimelineEntry(
            configured: !ids.isEmpty,
            actions: Array(resolved.prefix(WidgetActionGrid.capacity))
        )
    }
}

/// The resolved chosen Actions, whether the instance was configured at all, and the
/// date `TimelineEntry` requires.
private struct ActionsTimelineEntry: TimelineEntry {
    var date = Date()
    var configured: Bool
    var actions: [WidgetAction]
}

/// The widget surface: the shared 2×2 grid of chosen Actions, or — when nothing has
/// been chosen — the one-line choose-actions invitation deep-linking into the app.
/// A configured-but-all-stale instance still renders the grid (all cells dashed),
/// never the invitation: the ADR 0027 degrade keeps the chosen slots visible as
/// empty tap targets rather than pretending the widget was never set up.
private struct ActionsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let configured: Bool
    let actions: [WidgetAction]

    var body: some View {
        Group {
            if configured {
                WidgetActionGrid(actions: actions, showsTitles: family != .systemSmall)
            } else {
                chooseInvitation
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    /// The unconfigured placeholder (ADR 0027): a one-line invitation whose whole
    /// surface deep-links to a fresh, focused Home — never blank, never an error.
    private var chooseInvitation: some View {
        VStack(spacing: 6) {
            Image(systemName: QuickieGlyph.app)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Long-press to choose actions")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(QuickieDeeplink.entryURL())
    }
}
