import SwiftUI

/// ⚠️ TEMPORARY DIAGNOSTIC — this whole file is reverted once it has answered.
///
/// SwiftUI drag-to-reorder is dead everywhere in Quickie: the Fallbacks page, the
/// capture-steps pages, the Custom Action editor, and a probe section of three plain
/// `@State` strings sharing nothing with any of them. UIKit reorder on the same device
/// (Settings → Keyboards) is fine, so the gesture and the hardware are healthy.
///
/// Two candidates remain, and this file separates them by standing **outside the app
/// shell entirely**: `QuickieApp` renders this instead of `RootView`, so there is no
/// launcher, no `NavigationStack` of ours, no backdrop, no keyboard observer, no
/// focused text field, no injected environment — nothing but a `List`.
///
/// - **These reorder** → SwiftUI is fine and the shell is the culprit. Something
///   `RootView`/`QuickieApp` puts above every page and sheet is eating the drop, and
///   the next step is bisecting that chain.
/// - **These do not reorder** → the fault is below us: SwiftUI's `List` reorder on this
///   OS/toolchain. Nothing in this repo caused it and no repo change fixes it; the
///   answer is a workaround (a UIKit-backed list, or `.draggable`/`.dropDestination`
///   in place of `.onMove`).
///
/// Three variants, because they fail differently if the cause is subtle: the textbook
/// `EditButton` shape, an always-on edit mode driven by real state, and a reorder with
/// no edit mode at all (long-press then drag, which is a different code path in
/// SwiftUI and worth knowing about independently).
struct ReorderDiagnosticRoot: View {
    @State private var withEditButton = ["A1", "A2", "A3"]
    @State private var alwaysEditing = ["B1", "B2", "B3"]
    @State private var noEditMode = ["C1", "C2", "C3"]
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(withEditButton, id: \.self) { Text($0) }
                        .onMove { withEditButton.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("A — EditButton (tap Edit first)")
                } footer: {
                    Text(withEditButton.joined(separator: " › ")).font(.caption2.monospaced())
                }

                Section {
                    ForEach(alwaysEditing, id: \.self) { Text($0) }
                        .onMove { alwaysEditing.move(fromOffsets: $0, toOffset: $1) }
                        .environment(\.editMode, $editMode)
                } header: {
                    Text("B — always in edit mode")
                } footer: {
                    Text(alwaysEditing.joined(separator: " › ")).font(.caption2.monospaced())
                }

                Section {
                    ForEach(noEditMode, id: \.self) { Text($0) }
                        .onMove { noEditMode.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("C — no edit mode (long-press, then drag)")
                } footer: {
                    Text(noEditMode.joined(separator: " › ")).font(.caption2.monospaced())
                }
            }
            .navigationTitle("Reorder diagnostic")
            .toolbar { EditButton() }
        }
    }
}
