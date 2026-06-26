import SwiftUI

/// The single bottom input field — the one surface the whole app is built
/// around. It auto-focuses on launch (the binding is driven by `RootView`),
/// sits above the keyboard, and is wrapped in a Liquid Glass material over the
/// quiet backdrop (ADR 0010).
struct InputBar: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField("Type to search…", text: $query)
            .textFieldStyle(.plain)
            .font(.title3)
            .focused(focused)
            .submitLabel(.go)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }
}
