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
    /// The single RootView-level sheet — reading a note, composing a seeded
    /// note/snippet, or opening a library list page. One optional drives one
    /// `.sheet`, sidestepping SwiftUI's one-`.sheet`-per-view rule now that these
    /// presentations are triggered from the result list rather than chrome
    /// buttons (each of which used to own its own sheet).
    @State private var activeSheet: ActiveSheet?
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
                // Stored Snippets plus the always-present "New Snippet" Fallback —
                // typing then picking it opens the editor seeded with the text.
                IndexedProvider(catalog: storedSnippets + [.newSnippet()]),
                // Stored Notes plus the always-present "New Note" Fallback — the
                // brain-dump that opens the editor seeded with the typed text.
                IndexedProvider(catalog: storedNotes + [.newNote()]),
                // The library commands: filterable main-list rows that open the
                // full Snippet / Note list pages, in place of chrome buttons.
                IndexedProvider(catalog: [.openNotesLibrary(), .openSnippetsLibrary()]),
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
            // A quiet, adaptive backdrop for the Liquid Glass chrome to refract
            // (ADR 0010): iOS can't show the wallpaper, so the glass needs its own
            // calm base with a little depth — not a flat fill, not a busy one.
            QuietBackdrop()

            // The Home / Result list fills the whole screen so its bottom-anchored
            // rows scroll *under* the floating input, where the Liquid Glass
            // refracts them (ADR 0010) — rather than a flow layout that walls the
            // input off behind an opaque strip the results can't pass.
            Group {
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
            }

            // Quiet affordances into the user's libraries — Notes, Snippets, and
            // Quicklink management — sharing one top-trailing row so none
            // competes with the typing fast path nor overlaps the others.
            libraryButtons

            if let copyConfirmation {
                CopyConfirmationBanner(text: copyConfirmation)
            }
        }
        // The input — and the launch-time paste chip just above it — float in the
        // bottom safe area, so the result list scrolls behind the glass instead of
        // being walled off. Attached to the whole screen (not the Home/Result list
        // that swaps as the query changes) so the field keeps its identity and
        // focus across that swap. The chip is offered only on Home with text on the
        // clipboard (ADR 0002); typing withdraws it and tapping it retires it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if clipboardPrefill.isChipOffered {
                    ClipboardPasteChip { text in
                        query = text
                        clipboard.markUsed()
                    }
                }
                InputBar(query: $query, focused: $inputFocused)
            }
        }
        // Auto-focus on launch, keyboard up — the core promise (ADR 0012).
        .onAppear { inputFocused = true }
        // Re-arm focus when a full-screen page closes. Presenting a page
        // (Settings, All Notes, All Snippets, a note reader, a compose editor)
        // drops the keyboard, and the system doesn't restore first-responder on
        // return — so the input would come back unfocused, breaking the
        // zero-tap promise the moment the user leaves and comes back. Watch the
        // "any page presented" flag and refocus the instant it flips back to
        // false. (Comparing the optional to `nil` keeps this Equatable without
        // forcing `ActiveSheet` to be.)
        .onChange(of: activeSheet == nil && !showingManage) { _, noPagePresented in
            if noPagePresented { inputFocused = true }
        }
        // The one RootView sheet: a note opened for reading, a seeded compose
        // editor, or a library list page — all reached from the result list.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .readNote(let note):
                NoteEditorView(note: note)
            case .composeNote(let seed):
                NoteEditorView(seed: seed.text)
            case .composeSnippet(let seed):
                SnippetEditorView(seed: seed.text)
            case .notesLibrary:
                NoteManagerView()
            case .snippetsLibrary:
                SnippetManagerView()
            }
        }
    }

    /// The top-trailing settings button — a single Liquid Glass toolbar control
    /// for Quicklink management and the default search engine. The Notes and
    /// Snippet libraries are no longer chrome buttons: they're reached as "All
    /// Notes" / "All Snippets" rows in the result list, alongside everything else.
    private var libraryButtons: some View {
        VStack {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        showingManage = true
                    } label: {
                        // Pad around the icon so the glass circle has room to
                        // breathe — the button grows, the glyph stays the same size.
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .padding(8)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityIdentifier("manage-quicklinks")
                    .accessibilityLabel("Manage Quicklinks")
                    .sheet(isPresented: $showingManage) {
                        ManageQuicklinksView(engineTemplate: $engineTemplate)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
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
                activeSheet = .readNote(note)
            } else {
                flashConfirmation("Note not found")
            }
        case .composeNote(let seed):
            // "New Note": open the editor seeded with the typed text. The text now
            // lives in the editor, so clear the input back to Home behind the sheet.
            activeSheet = .composeNote(ComposeSeed(text: seed))
            query = ""
        case .composeSnippet(let seed):
            // "New Snippet": same, into the snippet editor.
            activeSheet = .composeSnippet(ComposeSeed(text: seed))
            query = ""
        case .openLibrary(let library):
            switch library {
            case .notes: activeSheet = .notesLibrary
            case .snippets: activeSheet = .snippetsLibrary
            }
        case .none:
            break
        }
    }

    /// Flashes a lightweight confirmation banner, then clears it after a beat.
    /// Each flash stamps a fresh token; only the latest flash's timer clears the
    /// banner, so two confirmations in quick succession keep it up for the full
    /// beat after the most recent one rather than the first. Used by the silent
    /// copy-out ("Copied") and the rare "Note not found" miss.
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

/// A one-shot seed for a compose editor: the typed text plus a fresh identity so
/// each invocation drives a distinct `.sheet(item:)` presentation.
private struct ComposeSeed: Identifiable {
    let id = UUID()
    let text: String
}

/// The single RootView-level sheet, as an Identifiable enum so one `.sheet(item:)`
/// can present any of them without colliding on SwiftUI's one-sheet-per-view rule.
private enum ActiveSheet: Identifiable {
    case readNote(StoredNote)
    case composeNote(ComposeSeed)
    case composeSnippet(ComposeSeed)
    case notesLibrary
    case snippetsLibrary

    var id: String {
        switch self {
        case .readNote(let note): return "read-\(note.id)"
        case .composeNote(let seed): return "compose-note-\(seed.id)"
        case .composeSnippet(let seed): return "compose-snippet-\(seed.id)"
        case .notesLibrary: return "notes-library"
        case .snippetsLibrary: return "snippets-library"
        }
    }
}

/// The quiet adaptive backdrop the Liquid Glass chrome floats over (ADR 0010).
/// Built from system colors so it follows light/dark automatically: a soft
/// top-to-bottom gradient with a faint accent glow pooled at the bottom, near the
/// input, giving the glass capsules something with depth to refract — calm enough
/// never to compete with the result text.
private struct QuietBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
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
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, 90)
                .accessibilityIdentifier("copy-confirmation")
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
