import SwiftUI
import WidgetKit

/// The WidgetKit extension's entry point (issue #124; epic #16 slice 1). This is
/// the **foundation** every widget-shaped [[Entry surface]] builds on: the target
/// itself, a member of the shared App Group, building in CI alongside the app.
///
/// This bundle ships the static [[deep-link widget]] (`EntryWidget`, #124), the
/// interactive [[Favorites widget]] (`FavoritesWidget`, ADR 0025 / #126), and the
/// Control Center control (`QuickCaptureControl`, #125) — the widget-shaped
/// [[Entry surface]]s: the first two get the user in (or run a Favorite without
/// going in at all), the control opens a clean, focused Home.
///
/// A `ControlWidget` sits in the same `WidgetBundle` as a `Widget`; the builder
/// accepts both and the body's `some Widget` still holds.
@main
struct QuickieWidgetBundle: WidgetBundle {
    var body: some Widget {
        EntryWidget()
        FavoritesWidget()
        QuickCaptureControl()
    }
}
