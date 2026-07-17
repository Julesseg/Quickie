import SwiftUI
import WidgetKit
import QuickieCore

/// The interactive **Favorites widget** (CONTEXT.md → Favorites widget; ADR 0025;
/// issue #126): the Home-Screen projection of the in-app Favorites grid — the same
/// 2×2, the same pin order, the same provider badges — whose buttons run a
/// Favorite's main action with as little Quickie as possible.
///
/// A **projection, not a second engine**: it renders from the app-written App
/// Group snapshot alone (`FavoritesWidgetStore.load()`) and never opens SwiftData
/// to draw. The grid itself is the shared `WidgetActionGrid` (ADR 0027) — the same
/// cell language the Actions widget renders — so each button executes the lane Core
/// classified into the snapshot (`WidgetExecution`): a Snippet copies in-place, a
/// Quicklink / no-input Shortcut hands off directly, and anything input-needing
/// opens the app tap-equivalently via `quickie://run/<id>` — a stale id degrading to
/// clean Home. Under-filled cells are `quickie://entry` tap targets, and zero pins
/// renders the one-line pin invitation: never blank, never an error.
struct FavoritesWidget: Widget {
    /// The widget kind — shared with the app through `FavoritesWidgetStore`, whose
    /// snapshot writes pair with a `reloadTimelines(ofKind:)` on this identity.
    static let kind = FavoritesWidgetStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FavoritesProvider()) { entry in
            FavoritesWidgetView(favorites: entry.favorites)
        }
        .configurationDisplayName("Favorites")
        .description("Run your pinned Favorites without opening Quickie.")
        // systemSmall is glyph-only; systemMedium adds titles. Both draw the same
        // 2×2 grid the in-app Favorites grid pins (issue #126).
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// A one-shot timeline on `.never`: the snapshot only changes when the app
/// rewrites it, and every rewrite is paired with an explicit
/// `WidgetCenter.reloadTimelines(ofKind:)` (`RootView`), so WidgetKit never needs
/// to poll — the render stays as cheap as a projection should be (ADR 0025).
private struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoritesTimelineEntry {
        FavoritesTimelineEntry(favorites: FavoritesWidgetStore.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (FavoritesTimelineEntry) -> Void) {
        completion(FavoritesTimelineEntry(favorites: FavoritesWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesTimelineEntry>) -> Void) {
        completion(Timeline(entries: [FavoritesTimelineEntry(favorites: FavoritesWidgetStore.load())], policy: .never))
    }
}

/// The rendered snapshot plus the date `TimelineEntry` requires.
private struct FavoritesTimelineEntry: TimelineEntry {
    var date = Date()
    var favorites: [WidgetAction]
}

/// The widget surface: the 2×2 grid in pin order (the shared `WidgetActionGrid`), or
/// — with nothing pinned — the one-line pin invitation deep-linking into the app.
/// Both states carry a tap everywhere, so the widget is never inert.
private struct FavoritesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let favorites: [WidgetAction]

    var body: some View {
        Group {
            if favorites.isEmpty {
                pinInvitation
            } else {
                WidgetActionGrid(actions: favorites, showsTitles: family != .systemSmall)
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    /// The zero-pins placeholder (issue #126): a one-line invitation whose whole
    /// surface deep-links to a fresh, focused Home — never blank, never an error.
    private var pinInvitation: some View {
        VStack(spacing: 6) {
            QuickieGlyph.image
                .font(.title3.weight(.semibold))
                // The empty state's mark wears the brand gradient (as the Entry
                // widget's does), an accent on the system container rather than a
                // gray placeholder (ADR 0033). The invitation copy stays
                // `.secondary`: the mark carries the brand, the text stays quiet.
                .foregroundStyle(QuickieBrand.markGradient)
            Text("Pin favorites in Quickie")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(QuickieDeeplink.entryURL())
    }
}
