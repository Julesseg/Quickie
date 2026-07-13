import AppIntents
import SwiftUI
import WidgetKit

/// The **Control Center control** (CONTEXT.md → Entry surface; issue #125; epic #16
/// slice 2): a `ControlWidgetButton` in the widget extension that opens Quickie on a
/// clean, focused Home — the same open-focused semantics as the deep-link widget
/// (#124), because it **rides the exact same `QuickCaptureIntent`** (#121) the
/// headline App Shortcut does. One intent, one inbound door (`quickie://entry`), no
/// parallel path (ADR 0024): the intent's `perform()` deposits the Core-built entry
/// URL into `DeeplinkInbox`, which `RootView` drains through the single root
/// `onOpenURL` — so the warm-resume reset (clear a stale query, abandon a half-filled
/// breadcrumb) matches the deep-link widget exactly.
///
/// The control surfaces in the Control Center gallery with the app glyph (the same
/// Quickie mark the deep-link widget shows, via `QuickieGlyph.image`) and the Quick
/// Capture title (drawn straight from `QuickCaptureIntent.title` so the label can't
/// drift from the intent it invokes).
///
/// The Action Button criterion of epic #16 needs nothing here: #121's App Shortcut
/// already surfaces Quick Capture in the Action Button picker.
struct QuickCaptureControl: ControlWidget {
    /// The control kind, stable across reloads and distinct from the deep-link
    /// widget's kind — the identity Control Center addresses this control by.
    static let kind = "QuickieQuickCaptureControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            // `QuickCaptureIntent.openAppWhenRun` is true, so activating the control
            // foregrounds the app and runs `perform()` in-app — the same door the
            // Quick Capture App Shortcut uses, not a second one.
            ControlWidgetButton(action: QuickCaptureIntent()) {
                // `Label(_:image:)`, not an `icon:` closure wrapping an `Image`:
                // Control Center archives the label out-of-process and resolves
                // only symbol *references* — a custom symbol nested as a plain
                // `Image` view silently renders nothing there.
                Label(String(localized: QuickCaptureIntent.title), image: QuickieGlyph.name)
            }
        }
        .displayName(QuickCaptureIntent.title)
        .description("Open Quickie on a clean, focused Home.")
    }
}
