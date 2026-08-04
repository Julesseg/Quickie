import SwiftUI
import UIKit

/// The `-uitest-keyboard-probe` seam: a hidden counter of `keyboardWillHide`
/// notifications, so a UI test can assert the keyboard *stays* up — XCUITest can
/// only snapshot `app.keyboards` at polling speed, which misses a fast
/// hide-then-show flicker entirely (the return-from-Settings flicker this seam
/// was built to catch). Like the `-uitest-entry` trigger, the swatch is 0.06
/// opacity — above UIKit's `alpha < 0.01` accessibility cutoff yet visually
/// inert — and gated on `--uitesting` so it can never surface in production.
struct KeyboardHideProbe: View {
    @State private var hideCount = 0

    private var isArmed: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains("-uitest-keyboard-probe")
    }

    var body: some View {
        if isArmed {
            Text("keyboard-hides:\(hideCount)")
                .font(.system(size: 6))
                .foregroundStyle(Color.primary.opacity(0.06))
                .accessibilityIdentifier("uitest-keyboard-hide-count")
                .accessibilityLabel("keyboard-hides:\(hideCount)")
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    hideCount += 1
                }
        }
    }
}
