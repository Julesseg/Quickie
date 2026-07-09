import SwiftUI
import WidgetKit

/// The WidgetKit extension's entry point (issue #124; epic #16 slice 1). This is
/// the **foundation** every widget-shaped [[Entry surface]] builds on: the target
/// itself, a member of the shared App Group, building in CI alongside the app.
///
/// This bundle ships the static [[deep-link widget]] (`EntryWidget`, #124) and the
/// Control Center control (`QuickCaptureControl`, #125) — two [[Entry surface]]s that
/// both open Quickie on a clean, focused Home. The interactive Favorites widget (ADR
/// 0025) joins the bundle in a later slice, so it exists now with room to grow rather
/// than being introduced twice.
///
/// A `ControlWidget` sits in the same `WidgetBundle` as a `Widget`; the builder
/// accepts both and the body's `some Widget` still holds.
@main
struct QuickieWidgetBundle: WidgetBundle {
    var body: some Widget {
        EntryWidget()
        QuickCaptureControl()
    }
}
