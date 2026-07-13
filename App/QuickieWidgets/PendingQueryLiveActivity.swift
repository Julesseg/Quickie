import SwiftUI
import WidgetKit
import ActivityKit

/// The **Pending query** Live Activity's presentations (issue #152): while the
/// 30-second window is open, the unfinished query is glanceable on the Lock
/// Screen / Dynamic Island and tappable to hop straight back to it.
///
/// - **Compact and minimal** Dynamic Island: generic glyphs only — never the
///   query text (it sits beside the clock and every other app's chrome).
/// - **Expanded and Lock Screen**: the truncated query preview plus a
///   return-arrow glyph expressing "return to it".
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
                DynamicIslandExpandedRegion(.leading) {
                    QuickieGlyph.image
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.preview)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                QuickieGlyph.image
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(.secondary)
            } minimal: {
                QuickieGlyph.image
                    .foregroundStyle(.tint)
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
                .foregroundStyle(.tint)
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
        .activityBackgroundTint(nil)
    }
}
