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
/// to draw. Each button executes the lane Core classified into the snapshot
/// (`WidgetExecution`): a Snippet copies in-place, a Quicklink / no-input Shortcut
/// hands off directly, and anything input-needing opens the app tap-equivalently
/// via `quickie://run/<id>` — a stale id degrading to clean Home. Under-filled
/// cells are `quickie://entry` tap targets, and zero pins renders the one-line
/// pin invitation: never blank, never an error.
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
    var favorites: [WidgetFavorite]
}

/// The widget surface: the 2×2 grid in pin order, or — with nothing pinned — the
/// one-line pin invitation deep-linking into the app. Both states carry a tap
/// everywhere, so the widget is never inert.
private struct FavoritesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let favorites: [WidgetFavorite]

    var body: some View {
        Group {
            if favorites.isEmpty {
                pinInvitation
            } else {
                grid
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    /// The zero-pins placeholder (issue #126): a one-line invitation whose whole
    /// surface deep-links to a fresh, focused Home — never blank, never an error.
    private var pinInvitation: some View {
        VStack(spacing: 6) {
            Image(systemName: QuickieGlyph.app)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Pin favorites in Quickie")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(QuickieDeeplink.entryURL())
    }

    /// The 2×2 grid, mirroring the in-app Favorites grid: pinned cells in pin
    /// order, then `quickie://entry` tap targets for the unfilled slots.
    private var grid: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { column in
                        cell(at: row * 2 + column)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        if index < favorites.count {
            FavoriteCellButton(favorite: favorites[index], showsTitle: family != .systemSmall)
        } else {
            EmptyCellButton()
        }
    }
}

/// The one cell shape both pinned and empty cells wear, so their radii can
/// never drift apart.
private enum FavoriteCell {
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }
}

/// One pinned cell: a `Button(intent:)` wearing the same provider badge as the
/// in-app Favorite card (`ProviderBadge`, shared via the synced folder) — its
/// symbol read off the snapshot's denormalized glyph, its tint off the kind, so
/// the render stays snapshot-only — plus the title in `systemMedium`. The intent
/// is picked by the snapshot's classified execution — the widget performs the
/// lane, it never re-decides it.
private struct FavoriteCellButton: View {
    let favorite: WidgetFavorite
    let showsTitle: Bool

    var body: some View {
        switch favorite.execution {
        case .copySnippet(let id):
            // In-place: the pasteboard write happens in the widget process; the
            // body is read fresh from the shared store by the intent, never here.
            Button(intent: CopyFavoriteSnippetIntent(actionID: id)) { label }
                .buttonStyle(.plain)
        case .handOff(let url):
            // Direct hand-off: the browser / Shortcuts app opening is the main
            // action, so the run is credited through the outbox.
            Button(intent: OpenFavoriteIntent(url: url, recordingRunOf: favorite.id)) { label }
                .buttonStyle(.plain)
        case .openApp:
            // Tap-equivalent open, through the Control's proven openAppWhenRun +
            // inbox door (not an OpenURLIntent — a custom scheme through it is
            // unreliable from a widget): the app resolves the id live and records
            // the run itself; an unresolvable id degrades to clean Home (#120).
            Button(intent: RunFavoriteInAppIntent(actionID: favorite.id)) { label }
                .buttonStyle(.plain)
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            if showsTitle {
                badge
                // Two lines, not one: a medium cell is wide but shallow, and a
                // truncated single line wastes the height it does have — a longer
                // title (most Shortcut and Custom Action names) reads whole.
                Text(favorite.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            } else {
                // Glyph-only in systemSmall: the badge centered, the title spoken
                // rather than drawn.
                badge
            }
        }
        .padding(.horizontal, showsTitle ? 10 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsTitle ? .leading : .center)
        .background(FavoriteCell.shape.fill(.quaternary.opacity(0.6)))
        .contentShape(FavoriteCell.shape)
        .accessibilityLabel(favorite.title)
    }

    /// The provider badge, drawn from the snapshot's own glyph — the projection
    /// rule (ADR 0025): the widget renders what the app wrote, it never re-derives.
    private var badge: some View {
        ProviderBadge(kind: favorite.kind, symbol: favorite.glyph)
    }
}

/// An unfilled slot: a quiet tap target that opens the app on a fresh, focused
/// Home (`quickie://entry`) — the open-focused entry-surface route (issue #126;
/// CONTEXT.md → Entry surface). A button (not a `Link`) so it works in
/// `systemSmall` too, riding the same openAppWhenRun + inbox door as the
/// open-app lane (a `nil` id is the fresh-entry reset).
private struct EmptyCellButton: View {
    var body: some View {
        Button(intent: RunFavoriteInAppIntent(actionID: nil)) {
            FavoriteCell.shape
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(FavoriteCell.shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Quickie")
    }
}
