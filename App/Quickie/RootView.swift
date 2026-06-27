import SwiftUI
import SwiftData
import UIKit
import QuickieCore

/// The whole screen, and the whole loop made visible: a bottom auto-focused
/// input, a reversed Result list above it, and tap-to-run. The empty-query
/// state shows the Home placeholder (ADR 0008 / issue #3).
struct RootView: View {
    @Environment(\.openURL) private var openURL

    /// User Quicklinks from the store feed the index alongside the built-ins
    /// (ADR 0006: index rebuilt from the source of truth).
    @Query(sort: \StoredQuicklink.createdAt) private var quicklinks: [StoredQuicklink]

    @State private var query = ""
    @FocusState private var inputFocused: Bool

    /// Tracks the active keyboard so the matcher weights adjacent-key typos for
    /// the layout the user is actually typing on (ADR 0005).
    @State private var keyboardLayout = KeyboardLayoutModel()

    private var engine: SearchEngine {
        let stored = quicklinks.compactMap { link -> Action? in
            guard let url = URL(string: link.urlString) else { return nil }
            return .staticLink(id: link.persistentModelID.hashValue.description, title: link.title, url: url)
        }
        return SearchEngine(
            providers: [
                IndexedProvider.builtIns(),
                IndexedProvider(catalog: stored),
            ],
            layout: keyboardLayout.layout
        )
    }

    private var isHome: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            // A quiet backdrop for the Liquid Glass UI to sit over (ADR 0010).
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if isHome {
                    HomePlaceholder()
                } else {
                    ResultListView(results: engine.results(for: query), onRun: run)
                }
                InputBar(query: $query, focused: $inputFocused)
            }
        }
        // Auto-focus on launch, keyboard up — the core promise (ADR 0012).
        .onAppear { inputFocused = true }
    }

    /// Runs a row's main action and performs its outcome at the platform edge.
    private func run(_ action: Action) {
        switch action.run(input: query) {
        case .openURL(let url):
            openURL(url)
        case .copyText(let text):
            UIPasteboard.general.string = text
        case .none:
            break
        }
    }
}
