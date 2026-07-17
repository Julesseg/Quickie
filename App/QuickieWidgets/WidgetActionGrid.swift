import SwiftUI
import WidgetKit
import QuickieCore

/// The **one cell language** every widget-grid [[Entry surface]] renders (ADR 0025;
/// ADR 0027): the 2×2 geometry, the pinned/chosen cell, and the empty tap-target
/// cell — extracted here so the [[Favorites widget]] and the [[Actions widget]] draw
/// identical cells and can never drift onto different radii, badges, or execution
/// wiring. Each widget keeps only its own *empty-state* copy (a pin invitation vs. a
/// choose-actions invitation); everything inside the grid is shared.
///
/// A cell executes the lane Core classified into its `WidgetAction`
/// (`WidgetExecution`) — a Snippet copies in-place, a Quicklink / no-input Shortcut
/// hands off directly, anything input-needing opens the app tap-equivalently — via
/// the same button intents (`FavoriteRunIntents`, in the folder synced into both the
/// app and widget targets). The widget performs the lane, it never re-decides it.

/// The one cell shape both filled and empty cells wear, so their radii can never
/// drift apart — `QuickieRadius.card`, the same step the in-app Favorites card it
/// mirrors uses, so the two surfaces stay one design rather than two.
enum WidgetCell {
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous) }
}

/// The 2×2 grid shared by the Favorites and Actions widgets: the chosen cells in
/// order, then dashed `quickie://entry` tap targets for the unfilled slots (or the
/// stale-id slots an ADR 0027 join dropped). At most four cells — the caller clamps
/// its list to the grid's capacity before handing it in.
struct WidgetActionGrid: View {
    /// The grid's cell count — the 2×2 geometry below drawn out — owned here beside
    /// that geometry so a caller clamping its list (the Actions widget's timeline) and
    /// the grid's actual cells can't drift apart. Sourced from the Core-canonical
    /// `FavoritesWidgetSnapshot.capacity` (the Favorites snapshot codec clamps against
    /// the same number), surfaced under the shared grid's name so neither widget has to
    /// reach into a Favorites-specific type for it.
    static let capacity = FavoritesWidgetSnapshot.capacity

    let actions: [WidgetAction]
    /// Whether cells show their title (`systemMedium`) or are glyph-only
    /// (`systemSmall`) — passed in so the grid needn't read the environment itself.
    let showsTitles: Bool

    var body: some View {
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
        if index < actions.count {
            WidgetActionCellButton(action: actions[index], showsTitle: showsTitles)
        } else {
            WidgetEmptyCellButton()
        }
    }
}

/// One filled cell: a `Button(intent:)` wearing the same provider badge as the
/// in-app card (`ProviderBadge`, shared via the synced folder) — its symbol read off
/// the snapshot's denormalized glyph, its tint off the kind, so the render stays
/// snapshot-only — plus the title when `showsTitle`. The intent is picked by the
/// snapshot's classified execution — the widget performs the lane, it never
/// re-decides it.
struct WidgetActionCellButton: View {
    let action: WidgetAction
    let showsTitle: Bool

    var body: some View {
        switch action.execution {
        case .copySnippet(let id):
            // In-place: the pasteboard write happens in the widget process; the
            // body is read fresh from the shared store by the intent, never here.
            Button(intent: CopyFavoriteSnippetIntent(actionID: id)) { label }
                .buttonStyle(.plain)
        case .handOff(let url):
            // Direct hand-off: the browser / Shortcuts app opening is the main
            // action, so the run is credited through the outbox.
            Button(intent: OpenFavoriteIntent(url: url, recordingRunOf: action.id)) { label }
                .buttonStyle(.plain)
        case .openApp:
            // Tap-equivalent open, through the proven openAppWhenRun + inbox door
            // (not an OpenURLIntent — a custom scheme through it is unreliable from a
            // widget): the app resolves the id live and records the run itself; an
            // unresolvable id degrades to clean Home (#120).
            Button(intent: RunFavoriteInAppIntent(actionID: action.id)) { label }
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
                Text(action.title)
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
        .background(WidgetCell.shape.fill(.quaternary.opacity(0.6)))
        .contentShape(WidgetCell.shape)
        .accessibilityLabel(action.title)
    }

    /// The provider badge, drawn from the snapshot's own glyph — the projection
    /// rule (ADR 0025): the widget renders what the app wrote, it never re-derives.
    private var badge: some View {
        ProviderBadge(kind: action.kind, symbol: action.glyph)
    }
}

/// An unfilled slot: a quiet tap target that opens the app on a fresh, focused Home
/// (`quickie://entry`) — the open-focused entry-surface route (CONTEXT.md → Entry
/// surface). Also the shape a stale configured id degrades to (ADR 0027). A button
/// (not a `Link`) so it works in `systemSmall` too, riding the same openAppWhenRun +
/// inbox door as the open-app lane (a `nil` id is the fresh-entry reset).
struct WidgetEmptyCellButton: View {
    var body: some View {
        Button(intent: RunFavoriteInAppIntent(actionID: nil)) {
            WidgetCell.shape
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(WidgetCell.shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Quickie")
    }
}
