import SwiftUI
import UIKit

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
/// Four variants, because they can fail differently if the cause is subtle: the
/// textbook `EditButton` shape, an always-on edit mode driven by real state, a reorder
/// with no edit mode at all (long-press then drag, a separate code path in SwiftUI),
/// and — once those three had all failed — a plain `UITableView`, to find out what a
/// workaround can be built on.
struct ReorderDiagnosticRoot: View {
    @State private var withEditButton = ["A1", "A2", "A3"]
    @State private var alwaysEditing = ["B1", "B2", "B3"]
    @State private var noEditMode = ["C1", "C2", "C3"]
    @State private var uikitItems = ["D1", "D2", "D3"]
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

                Section {
                    NavigationLink("Open the UIKit table probe") {
                        UIKitReorderProbe(items: $uikitItems)
                            .ignoresSafeArea()
                            .navigationTitle("UIKit table")
                    }
                } header: {
                    Text("D — UIKit UITableView reorder")
                } footer: {
                    Text(uikitItems.joined(separator: " › ")).font(.caption2.monospaced())
                }
            }
            .navigationTitle("Reorder diagnostic")
            .toolbar { EditButton() }
        }
    }
}

/// ⚠️ TEMPORARY DIAGNOSTIC — the workaround floor.
///
/// A plain `UITableView` in permanent editing mode: the same thing Settings →
/// Keyboards uses, which reorders correctly on the affected device. If SwiftUI's
/// `.onMove` is broken at the framework level, this is what a fix has to be built on,
/// so it is worth proving it works *inside this app* before committing to that route.
///
/// Deliberately does **not** `reloadData` on update: UIKit has already animated the
/// move itself, and reloading on top of it would fight that animation. The order is
/// pushed back through the binding, so the SwiftUI footer on the previous screen is
/// the independent readout that the drop actually committed.
private struct UIKitReorderProbe: UIViewControllerRepresentable {
    @Binding var items: [String]

    func makeCoordinator() -> Coordinator { Coordinator(items: $items) }

    func makeUIViewController(context: Context) -> UITableViewController {
        let controller = UITableViewController(style: .insetGrouped)
        controller.tableView.dataSource = context.coordinator
        controller.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        controller.tableView.isEditing = true
        return controller
    }

    func updateUIViewController(_ controller: UITableViewController, context: Context) {}

    final class Coordinator: NSObject, UITableViewDataSource {
        @Binding var items: [String]

        init(items: Binding<[String]>) { _items = items }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            items.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: path)
            var content = cell.defaultContentConfiguration()
            content.text = items[path.row]
            cell.contentConfiguration = content
            return cell
        }

        func tableView(_ tableView: UITableView, canMoveRowAt path: IndexPath) -> Bool { true }

        func tableView(_ tableView: UITableView, moveRowAt from: IndexPath, to: IndexPath) {
            var next = items
            next.insert(next.remove(at: from.row), at: to.row)
            items = next
        }

        func tableView(
            _ tableView: UITableView, editingStyleForRowAt path: IndexPath
        ) -> UITableViewCell.EditingStyle { .none }

        func tableView(
            _ tableView: UITableView, shouldIndentWhileEditingRowAt path: IndexPath
        ) -> Bool { false }
    }
}
