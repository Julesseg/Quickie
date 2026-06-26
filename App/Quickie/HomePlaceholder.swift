import SwiftUI

/// The empty-query Home state. Deliberately minimal for the skeleton (issue #3)
/// — Favorites and the Frecency list land in later M1 slices. Its only job
/// today is to fill the space above the input before the first keystroke.
struct HomePlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Start typing")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("home-placeholder")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
