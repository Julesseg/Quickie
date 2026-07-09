import SwiftUI
import WidgetKit

/// The WidgetKit extension's entry point (issue #124; epic #16 slice 1). This is
/// the **foundation** every widget-shaped [[Entry surface]] builds on: the target
/// itself, a member of the shared App Group, building in CI alongside the app.
///
/// This slice ships a single widget — the static [[deep-link widget]]. The
/// interactive Favorites widget (ADR 0025) joins the bundle in a later slice, so
/// the bundle exists now with room to grow rather than being introduced twice.
@main
struct QuickieWidgetBundle: WidgetBundle {
    var body: some Widget {
        EntryWidget()
    }
}
