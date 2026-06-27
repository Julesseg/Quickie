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

    /// User Snippets feed the same index — copy-out Actions ranked beside every
    /// other capability (issue #6).
    @Query(sort: \StoredSnippet.createdAt) private var snippets: [StoredSnippet]

    @State private var query = ""
    @FocusState private var inputFocused: Bool
    @State private var showingSnippets = false
    /// A transient confirmation banner shown after a copy-out main action runs —
    /// the "lightweight confirmation" snippets need since copying is silent.
    @State private var copyConfirmation: String?

    private var engine: SearchEngine {
        let storedLinks = quicklinks.compactMap { link -> Action? in
            guard let url = URL(string: link.urlString) else { return nil }
            return .staticLink(id: link.persistentModelID.hashValue.description, title: link.title, url: url)
        }
        let storedSnippets = snippets.map { snippet in
            Action.snippet(
                id: "snippet.\(snippet.persistentModelID.hashValue.description)",
                title: snippet.title,
                body: snippet.body
            )
        }
        return SearchEngine(providers: [
            IndexedProvider.builtIns(),
            IndexedProvider(catalog: storedLinks),
            IndexedProvider(catalog: storedSnippets),
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

            // The library affordance: an unobtrusive top-trailing button to
            // manage Snippets, kept out of the input's way (ADR 0012).
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showingSnippets = true
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .padding(12)
                    }
                    .accessibilityIdentifier("open-snippets")
                }
                Spacer()
            }

            if let copyConfirmation {
                CopyConfirmationBanner(text: copyConfirmation)
            }
        }
        // Auto-focus on launch, keyboard up — the core promise (ADR 0012).
        .onAppear { inputFocused = true }
        .sheet(isPresented: $showingSnippets) {
            SnippetManagerView()
        }
    }

    /// Runs a row's main action and performs its outcome at the platform edge.
    private func run(_ action: Action) {
        switch action.run(input: query) {
        case .openURL(let url):
            openURL(url)
        case .copyText(let text):
            UIPasteboard.general.string = text
            confirmCopy()
        case .none:
            break
        }
    }

    /// Flashes the copy confirmation, then clears it after a beat.
    private func confirmCopy() {
        withAnimation { copyConfirmation = "Copied" }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { copyConfirmation = nil }
        }
    }
}

/// The lightweight "Copied" confirmation: a brief, non-blocking banner that
/// acknowledges a silent copy-out without stealing focus from the input.
private struct CopyConfirmationBanner: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 90)
                .accessibilityIdentifier("copy-confirmation")
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
