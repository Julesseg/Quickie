import SwiftUI
import QuickieCore

/// The single bottom input field — the one surface the whole app is built
/// around. It auto-focuses on launch (the binding is driven by `RootView`),
/// sits above the keyboard, and is a native Liquid Glass capsule over the quiet
/// backdrop (ADR 0010): no hand-rolled blur, so the material matches the system.
///
/// Its Return key carries the highlighted result's Enter intent (CONTEXT.md →
/// Highlighted result): the submit label maps to that row's closest system label
/// (`.search` for a web query, `.go` for a link) and pressing Return runs exactly
/// that row's main action. On Home (empty query) there is no highlight and submit
/// is a no-op.
struct InputBar: View {
    /// Stable identity for the input's Liquid Glass within the bottom
    /// `GlassEffectContainer`. Pairing it with the paste button's id in a shared
    /// namespace is what lets the button morph *out of and back into* this capsule
    /// as it is offered and withdrawn (see `ClipboardPasteButton`, `RootView`).
    static let glassID = "input-bar"

    /// The bottom row's height. Fixed (rather than padding-derived) so the paste
    /// button can be an exactly-matching circle beside it — see `ClipboardPasteButton`.
    static let barHeight: CGFloat = 52

    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    /// The highlighted result's Return-key label, or `.none` on Home.
    var returnKey: ReturnKeyLabel = .none
    /// Runs the highlighted result's main action; a no-op when there is none.
    var onSubmit: () -> Void = {}
    /// The shared namespace the bottom glass surfaces morph within.
    var glassNamespace: Namespace.ID

    var body: some View {
        TextField("Type to search…", text: $query)
            .textFieldStyle(.plain)
            .font(.title3)
            .focused(focused)
            .submitLabel(returnKey.submitLabel)
            .onSubmit(onSubmit)
            .accessibilityIdentifier("search-input")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 20)
            .frame(height: Self.barHeight)
            .glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectID(Self.glassID, in: glassNamespace)
    }
}
