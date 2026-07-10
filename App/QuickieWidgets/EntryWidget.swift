import SwiftUI
import WidgetKit
import QuickieCore

/// The static **deep-link widget** (CONTEXT.md → Entry surface; issue #124): a
/// single Quickie-glyph tile whose whole surface is a `widgetURL` to
/// `quickie://entry` — the fresh-entry route (#120). Tapping it opens Quickie on a
/// clean, focused Home: on a **warm** app it clears a stale query and abandons a
/// half-filled breadcrumb; a cold launch already lands on the focused input (ADR
/// 0012), so the route's meaning is the warm case. Resuming via the app icon or app
/// switcher keeps state — the two paths coexist (CONTEXT.md → Entry surface).
///
/// The tile carries **no timeline data** — it is a fixed glyph — so its provider
/// hands back one entry on a `.never` refresh policy and the render stays trivially
/// cheap, as an entry surface's widget should.
struct EntryWidget: Widget {
    /// The widget kind, stable across reloads — the identity WidgetKit uses to
    /// address this widget's timelines.
    static let kind = "QuickieEntryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: EntryProvider()) { _ in
            EntryWidgetView()
        }
        .configurationDisplayName("Open Quickie")
        .description("Open Quickie on a clean, focused Home.")
        // Lock Screen (`accessoryCircular`) + Home Screen (`systemSmall`), the two
        // families this slice ships (issue #124).
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

/// A one-shot timeline: the tile is static, so a single entry serves forever and
/// never needs refreshing (`.never`).
private struct EntryProvider: TimelineProvider {
    func placeholder(in context: Context) -> EntryTimelineEntry { EntryTimelineEntry() }

    func getSnapshot(in context: Context, completion: @escaping (EntryTimelineEntry) -> Void) {
        completion(EntryTimelineEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntryTimelineEntry>) -> Void) {
        completion(Timeline(entries: [EntryTimelineEntry()], policy: .never))
    }
}

/// The lone timeline entry. It carries no payload — the tile is a fixed glyph — so
/// it holds only the render date WidgetKit's `TimelineEntry` requires.
private struct EntryTimelineEntry: TimelineEntry {
    var date = Date()
}

/// The tile: the Quickie glyph filling the family's shape, its whole surface a
/// `widgetURL` to `quickie://entry`. The URL is built through Core's
/// `QuickieDeeplink.entryURL()` — not string-joined — so the widget and the app's
/// root `onOpenURL` agree on the exact route the parser classifies.
private struct EntryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        glyph
            .containerBackground(for: .widget) { background }
            .widgetURL(QuickieDeeplink.entryURL())
    }

    @ViewBuilder private var glyph: some View {
        switch family {
        case .accessoryCircular:
            // Lock Screen: the system renders accessory widgets desaturated and
            // vibrant, so a plain symbol reads on any wallpaper without its own tint.
            Image(systemName: QuickieGlyph.app)
                .font(.title2)
        default:
            // Home Screen: the glyph centered large over the tinted background.
            Image(systemName: QuickieGlyph.app)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryCircular:
            AccessoryWidgetBackground()
        default:
            Color.accentColor
        }
    }
}
