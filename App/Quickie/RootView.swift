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

    /// The user's editable default search engine — just a URL template
    /// (CONTEXT.md → Quicklink; issue #5 AC #6). Persisted in app storage and
    /// fed to the built-in web-search Fallback.
    @AppStorage("searchEngineTemplate")
    private var engineTemplate = "https://duckduckgo.com/?q={query}"

    @State private var query = ""
    @State private var showingManage = false
    @FocusState private var inputFocused: Bool

    private var engine: SearchEngine {
        let stored = quicklinks.map { link in
            Action.quicklink(
                id: link.persistentModelID.hashValue.description,
                title: link.title,
                aliases: link.alias.map { [$0] } ?? [],
                template: link.urlString,
                isFallback: link.isFallback
            )
        }
        return SearchEngine(providers: [
            IndexedProvider.builtIns(webSearchTemplate: engineTemplate),
            IndexedProvider(catalog: stored),
        ])
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

            // A quiet affordance into Quicklink management — kept out of the
            // input's way so it never competes with the typing fast path.
            manageButton
        }
        // Auto-focus on launch, keyboard up — the core promise (ADR 0012).
        .onAppear { inputFocused = true }
        .sheet(isPresented: $showingManage) {
            ManageQuicklinksView(engineTemplate: $engineTemplate)
        }
    }

    private var manageButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    showingManage = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .padding(10)
                }
                .accessibilityIdentifier("manage-quicklinks")
                .accessibilityLabel("Manage Quicklinks")
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
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
