import SwiftUI
import WidgetKit
import ActivityKit

/// The **Pending query** Live Activity's presentations (issue #152): while the
/// 30-second window is open, the unfinished query is glanceable on the Lock
/// Screen / Dynamic Island and tappable to hop straight back to it.
///
/// - **Compact and minimal** Dynamic Island: the mark only — never the query
///   text (it sits beside the clock and every other app's chrome). The glyph
///   wears the solid `QuickieBrand.accent` (not the gradient — too small a mark
///   to read a ramp). `.tint` was the first intent here (ADR 0033's "shared
///   chrome keeps the system tint"), but this extension has **no** `AccentColor`
///   asset, so `.tint` resolves to *system blue* rather than a neutral system
///   tint — a stray blue mark next to the clock, not the wallpaper-respecting
///   neutral the ADR assumed. The brand accent is the honest read of that intent
///   in an asset-less extension.
/// - **Expanded and Lock Screen**: the truncated query preview plus a
///   return-arrow glyph expressing "return to it". These are Quickie's own
///   surface, so the mark wears the brand gradient (`QuickieBrand.markGradient`,
///   the icon trail's ramp the Entry widget already uses) over a faint brand
///   wash (`QuickieBrand.accentWash`) rather than `.tint` on nothing — this
///   extension has no `AccentColor` asset (only the app target declares one), so
///   `.tint` here resolves to *system blue*, which is exactly what ADR 0033
///   exists to end.
///
/// The tap is a **plain open** — icon-equivalent, restoring the query — so no
/// `widgetURL` is set: the system's default tap just opens the app, which is
/// exactly the plain-open path. Routing through `quickie://entry` would make
/// the tap an Entry surface and commit the text to the Pile instead. Since the
/// activity only exists inside the window, a tap always lands on the restored
/// query; no restore-after-expiry path exists.
struct PendingQueryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PendingQueryActivityAttributes.self) { context in
            // The Lock Screen / banner presentation.
            PendingQueryLockScreenView(preview: context.state.preview)
        } dynamicIsland: { context in
            DynamicIsland {
                // The two side glyphs share one font (`.title3`) and both stretch
                // to the region's full height, centered — so the mark and the
                // return arrow sit on the same vertical line as each other and as
                // the taller center text, instead of the mark riding up to the top
                // of its region while the arrow floats mid-height.
                DynamicIslandExpandedRegion(.leading) {
                    QuickieGlyph.image
                        .font(.title3)
                        .foregroundStyle(QuickieBrand.markGradient)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.preview)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            } compactLeading: {
                QuickieGlyph.image
                    .foregroundStyle(QuickieBrand.accent)
            } compactTrailing: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(.secondary)
            } minimal: {
                QuickieGlyph.image
                    .foregroundStyle(QuickieBrand.accent)
            }
        }
    }
}

/// The Lock Screen banner: the truncated query preview between the app's
/// mark and the return arrow — "your unfinished query; hop back to it".
private struct PendingQueryLockScreenView: View {
    let preview: String

    var body: some View {
        HStack(spacing: 12) {
            QuickieGlyph.image
                .font(.title3)
                .foregroundStyle(QuickieBrand.markGradient)
            Text(preview)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.uturn.backward")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        // A faint brand wash behind the banner instead of no tint — Quickie's own
        // surface reads as Quickie's, without becoming a backdrop (ADR 0033). The
        // system still supplies the material under it, so the query stays legible
        // on any wallpaper.
        .activityBackgroundTint(QuickieBrand.accentWash)
    }
}
