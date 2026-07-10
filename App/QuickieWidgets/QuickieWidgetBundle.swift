import SwiftUI
import WidgetKit

/// The WidgetKit extension's entry point (issue #124; epic #16 slice 1). This is
/// the **foundation** every widget-shaped [[Entry surface]] builds on: the target
/// itself, a member of the shared App Group, building in CI alongside the app.
///
/// This bundle ships the static [[deep-link widget]] (`EntryWidget`, #124), the
/// interactive [[Favorites widget]] (`FavoritesWidget`, ADR 0025 / #126), the
/// user-chosen [[Actions widget]] and [[Action control]] (ADR 0027 / #140), and the
/// static Quick Capture Control Center control (`QuickCaptureControl`, #125) — the
/// widget-shaped [[Entry surface]]s: the first three get the user in (or run an
/// Action without going in at all), the two controls open a clean Home / run a chosen
/// Action.
///
/// A `ControlWidget` sits in the same `WidgetBundle` as a `Widget`; the builder
/// accepts both and the body's `some Widget` still holds.
@main
struct QuickieWidgetBundle: WidgetBundle {
    var body: some Widget {
        EntryWidget()
        FavoritesWidget()
        ActionsWidget()
        QuickCaptureControl()
        ActionControl()
    }
}
