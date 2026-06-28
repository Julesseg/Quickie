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

    /// The user's editable default search engine — just a URL template
    /// (CONTEXT.md → Quicklink; issue #5 AC #6). Persisted in app storage and
    /// fed to the built-in web-search Fallback.
    @AppStorage("searchEngineTemplate")
    private var engineTemplate = "https://duckduckgo.com/?q={query}"

    @State private var query = ""
    @State private var showingManage = false
    @State private var showingSnippets = false
    @FocusState private var inputFocused: Bool
    /// A transient confirmation banner shown after a copy-out main action runs —
    /// the "lightweight confirmation" snippets need since copying is silent.
    @State private var copyConfirmation: String?
    /// Identifies the most recent copy so its dismiss timer is the only one that
    /// clears the banner — rapid copies coalesce instead of cutting each other
    /// short.
    @State private var copyToken = UUID()

    /// Tracks the active keyboard so the matcher weights adjacent-key typos for
    /// the layout the user is actually typing on (ADR 0005).
    @State private var keyboardLayout = KeyboardLayoutModel()

    /// The silent `hasStrings` metadata check behind the Clipboard prefill chip
    /// (ADR 0002). Carries no clipboard content — only whether text is present.
    @State private var clipboard = ClipboardPrefillModel()

    private var engine: SearchEngine {
        let storedLinks = quicklinks.map { link in
            Action.quicklink(
                id: link.persistentModelID.hashValue.description,
                title: link.title,
                aliases: link.alias.map { [$0] } ?? [],
                template: link.urlString,
                isFallback: link.isFallback
            )
        }
        let storedSnippets = snippets.map { snippet in
            Action.snippet(
                id: "snippet.\(snippet.persistentModelID.hashValue.description)",
                title: snippet.title,
                body: snippet.body
            )
        }
        return SearchEngine(
            providers: [
                IndexedProvider.builtIns(webSearchTemplate: engineTemplate),
                IndexedProvider(catalog: storedLinks),
                IndexedProvider(catalog: storedSnippets),
            ],
            layout: keyboardLayout.layout
        )
    }

    private var isHome: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The content-free decision (QuickieCore) on whether to offer the paste
    /// chip: only on Home, and only when the silent metadata check found text.
    private var clipboardPrefill: ClipboardPrefill {
        ClipboardPrefill(
            clipboardHasText: clipboard.clipboardHasText,
            isHome: isHome,
            hasBeenUsed: clipboard.hasBeenUsed
        )
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
                // The launch-time paste chip rides just above the input, offered
                // only on Home with text on the clipboard (ADR 0002). Typing
                // withdraws it transiently — it returns if the user clears back to
                // an unused Home. Tapping it is what retires it for good: we seed
                // `query` and mark the offer used, so a *used* chip stays gone for
                // the rest of the launch even when the cleared input returns to
                // Home with text still on the clipboard.
                if clipboardPrefill.isChipOffered {
                    ClipboardPasteChip { text in
                        query = text
                        clipboard.markUsed()
                    }
                }
                InputBar(query: $query, focused: $inputFocused)
            }

            // Quiet affordances into the user's libraries — Snippets and
            // Quicklink management — sharing one top-trailing row so neither
            // competes with the typing fast path nor overlaps the other.
            libraryButtons

            if let copyConfirmation {
                CopyConfirmationBanner(text: copyConfirmation)
            }
        }
        // Auto-focus on launch, keyboard up — the core promise (ADR 0012).
        .onAppear { inputFocused = true }
    }

    /// The top-trailing library buttons. Each owns its own `.sheet` so the two
    /// presentations never collide (SwiftUI ignores a second `.sheet` attached
    /// to the same view).
    private var libraryButtons: some View {
        VStack {
            HStack(spacing: 4) {
                Spacer()
                Button {
                    showingSnippets = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title3)
                        .padding(10)
                }
                .accessibilityIdentifier("open-snippets")
                .accessibilityLabel("Manage Snippets")
                .sheet(isPresented: $showingSnippets) {
                    SnippetManagerView()
                }

                Button {
                    showingManage = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .padding(10)
                }
                .accessibilityIdentifier("manage-quicklinks")
                .accessibilityLabel("Manage Quicklinks")
                .sheet(isPresented: $showingManage) {
                    ManageQuicklinksView(engineTemplate: $engineTemplate)
                }
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
            confirmCopy()
        case .none:
            break
        }
    }

    /// Flashes the copy confirmation, then clears it after a beat. Each copy
    /// stamps a fresh token; only the latest copy's timer clears the banner, so
    /// two copies in quick succession keep it up for the full beat after the
    /// most recent one rather than the first.
    private func confirmCopy() {
        let token = UUID()
        copyToken = token
        withAnimation { copyConfirmation = "Copied" }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard copyToken == token else { return }
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
