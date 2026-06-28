import SwiftUI
import SwiftData
import UIKit
import QuickieCore

/// The whole screen, and the whole loop made visible: a bottom auto-focused
/// input, a reversed Result list above it, and tap-to-run. The empty-query
/// state shows the Home placeholder (ADR 0008 / issue #3).
struct RootView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context

    /// User Quicklinks from the store feed the index alongside the built-ins
    /// (ADR 0006: index rebuilt from the source of truth).
    @Query(sort: \StoredQuicklink.createdAt) private var quicklinks: [StoredQuicklink]

    /// User Snippets feed the same index — copy-out Actions ranked beside every
    /// other capability (issue #6).
    @Query(sort: \StoredSnippet.createdAt) private var snippets: [StoredSnippet]

    /// User Notes feed the same index — read Actions whose main action opens the
    /// note (issue #7), ranked beside every other capability.
    @Query(sort: \StoredNote.createdAt) private var notes: [StoredNote]

    /// The user's editable default search engine — just a URL template
    /// (CONTEXT.md → Quicklink; issue #5 AC #6). Persisted in app storage and
    /// fed to the built-in web-search Fallback.
    @AppStorage("searchEngineTemplate")
    private var engineTemplate = "https://duckduckgo.com/?q={query}"

    /// The user's ranking signals — pinned Favorites and Frecency of past
    /// selections — persisted across launches (issue #9). Feeds the engine and
    /// is updated on every pin/unpin and main-action tap.
    @State private var signals = SignalsStore.launch()

    @State private var query = ""
    @State private var showingManage = false
    @State private var showingSnippets = false
    @State private var showingNotes = false
    /// The Note a result row's main action opened for reading, presented in the
    /// note editor sheet (CONTEXT.md → Note: main action is Open/read).
    @State private var noteUnderRead: StoredNote?
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
        let storedNotes = notes.map { note in
            Action.note(id: Self.noteActionID(note), title: note.title)
        }
        return SearchEngine(
            providers: [
                // The Dynamic Calculator + unit-conversion Provider: when the
                // query parses as math or a conversion it injects a boosted top
                // result whose main action copies the answer (issue #8).
                CalculatorProvider(),
                IndexedProvider.builtIns(webSearchTemplate: engineTemplate),
                IndexedProvider(catalog: storedLinks),
                IndexedProvider(catalog: storedSnippets),
                // Stored Notes plus the always-present "New Note" capture
                // (CONTEXT.md → Note, Fallback Action) — the instant, silent
                // brain-dump that turns the typed text into a Note.
                IndexedProvider(catalog: storedNotes + [.newNote()]),
            ],
            layout: keyboardLayout.layout,
            favorites: signals.favorites,
            frecency: signals.frecency
        )
    }

    /// The stable Action id derived from a stored Note's identity, used both when
    /// indexing the Note and when resolving an `openNote(id:)` outcome back to the
    /// StoredNote to present. Built on the note's persisted, collision-free `id`
    /// (a UUID) — namespaced with a `note.` prefix to keep it distinct from other
    /// providers' Action ids in the shared index.
    private static func noteActionID(_ note: StoredNote) -> String {
        "note.\(note.id)"
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
                    HomeView(
                        content: engine.home(),
                        onRun: run,
                        isFavorite: { signals.isFavorite($0.id) },
                        onToggleFavorite: { signals.toggleFavorite($0.id) }
                    )
                } else {
                    ResultListView(
                        results: engine.results(for: query),
                        onRun: run,
                        isFavorite: { signals.isFavorite($0.id) },
                        onToggleFavorite: { signals.toggleFavorite($0.id) }
                    )
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

            // Quiet affordances into the user's libraries — Notes, Snippets, and
            // Quicklink management — sharing one top-trailing row so none
            // competes with the typing fast path nor overlaps the others.
            libraryButtons

            if let copyConfirmation {
                CopyConfirmationBanner(text: copyConfirmation)
            }
        }
        // Auto-focus on launch, keyboard up — the core promise (ADR 0012).
        .onAppear { inputFocused = true }
        // A note's main action opens it here for reading/editing — the read
        // counterpart to a snippet's silent copy.
        .sheet(item: $noteUnderRead) { note in
            NoteEditorView(note: note)
        }
    }

    /// The top-trailing library buttons. Each owns its own `.sheet` so the
    /// presentations never collide (SwiftUI ignores a second `.sheet` attached
    /// to the same view).
    private var libraryButtons: some View {
        VStack {
            HStack(spacing: 4) {
                Spacer()
                Button {
                    showingNotes = true
                } label: {
                    Image(systemName: "note.text")
                        .font(.title3)
                        .padding(10)
                }
                .accessibilityIdentifier("open-notes")
                .accessibilityLabel("Manage Notes")
                .sheet(isPresented: $showingNotes) {
                    NoteManagerView()
                }

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
    /// Selecting an Action records a frecency event (issue #9 AC #2), so the
    /// chosen row climbs the next Home Frecency list and Results ranking.
    private func run(_ action: Action) {
        signals.record(action.id)
        switch action.run(input: query) {
        case .openURL(let url):
            openURL(url)
        case .copyText(let text):
            UIPasteboard.general.string = text
            flashConfirmation("Copied")
        case .openNote(let id):
            // A note's main action opens it for reading — resolve the id back to
            // the stored note and present the reader/editor. If the note was
            // deleted after the list was indexed the lookup misses; flash a
            // confirmation rather than letting the tap do nothing silently.
            if let note = notes.first(where: { Self.noteActionID($0) == id }) {
                noteUnderRead = note
            } else {
                flashConfirmation("Note not found")
            }
        case .createNote(let text):
            captureNote(text)
        case .none:
            break
        }
    }

    /// The instant, silent "New Note" capture (CONTEXT.md → Note): turn the typed
    /// text into a stored Note with no app switch, clear the input back to Home,
    /// and flash a lightweight confirmation — the capture is silent, so the banner
    /// is the only acknowledgement. A blank capture is ignored.
    private func captureNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(StoredNote.capture(text: trimmed))
        query = ""
        flashConfirmation("Note saved")
    }

    /// Flashes a lightweight confirmation banner, then clears it after a beat.
    /// Each flash stamps a fresh token; only the latest flash's timer clears the
    /// banner, so two confirmations in quick succession keep it up for the full
    /// beat after the most recent one rather than the first. Shared by the silent
    /// copy-out ("Copied") and the silent note capture ("Note saved").
    private func flashConfirmation(_ message: String) {
        let token = UUID()
        copyToken = token
        withAnimation { copyConfirmation = message }
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
