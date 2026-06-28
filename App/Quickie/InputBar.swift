import SwiftUI

/// The single bottom input field — the one surface the whole app is built
/// around. It auto-focuses on launch (the binding is driven by `RootView`),
/// sits above the keyboard, and is a native Liquid Glass capsule over the quiet
/// backdrop (ADR 0010): no hand-rolled blur, so the material matches the system.
struct InputBar: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField("Type to search…", text: $query)
            .textFieldStyle(.plain)
            .font(.title3)
            .focused(focused)
            .submitLabel(.go)
            .accessibilityIdentifier("search-input")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }
}
