import Foundation
import UIKit
import Observation
import QuickieCore

/// Keeps the matcher's keyboard layout in step with the keyboard the user is
/// actually typing on (ADR 0005 — layout-adaptive adjacency).
///
/// The platform-agnostic Core can't see `UITextInputMode`, so this App-side
/// model is the bridge: it reads the active keyboard's primary language, maps
/// it to a `KeyboardLayout` (`KeyboardLayout.forLanguage`), and swaps live when
/// the user switches keyboards (`UITextInputMode.currentInputModeDidChange…`).
/// Third-party/opaque keyboards fall back to QWERTY via `forLanguage`.
@MainActor
@Observable
final class KeyboardLayoutModel {
    private(set) var layout: KeyboardLayout = .qwerty
    // `nonisolated(unsafe)` so the (nonisolated) deinit can remove the observer
    // token; it is written once at init and only read again at dealloc, so the
    // unchecked access is safe in practice. `removeObserver` is thread-safe.
    @ObservationIgnored private nonisolated(unsafe) var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: UITextInputMode.currentInputModeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func refresh() {
        layout = KeyboardLayout.forLanguage(Self.currentPrimaryLanguage())
    }

    /// The primary language of the keyboard currently driving input. The active
    /// first responder's `textInputMode` is authoritative for *which* keyboard
    /// is showing; we fall back to the first enabled mode, then to `nil` (which
    /// `forLanguage` resolves to QWERTY).
    private static func currentPrimaryLanguage() -> String? {
        UIResponder.currentFirstResponder?.textInputMode?.primaryLanguage
            ?? UITextInputMode.activeInputModes.first?.primaryLanguage
    }
}

@MainActor
private extension UIResponder {
    private static weak var found: UIResponder?

    /// The app's current first responder, found via the standard nil-targeted
    /// action trick (UIKit routes a nil-target action to the first responder).
    static var currentFirstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(captureFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    @objc private func captureFirstResponder() {
        UIResponder.found = self
    }
}
