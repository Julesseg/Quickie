/// The concrete value or reference a result carries — the thing a secondary
/// action operates on (CONTEXT.md → Result content; ADR 0017). Distinct from
/// both its content *type* (the kind) and its *main action* (what tapping it
/// does). Encodes **presence and value**, not just type, which is exactly what
/// lets a text-bearing Snippet (`.text`) be told apart from a text-*typed*
/// Settings command (`.none`): a type-keyed table could not.
///
/// Either an inline value the App reads off the Action's own outcome (`.text`,
/// `.url`, `.number`) or an edge-resolved reference the App dereferences on
/// demand (a Pile entry's text by id, a file by bookmark + relative path, a
/// Shortcut by name). A command or capture row has **`.none`** — no content —
/// which is what makes it ineligible for secondary actions regardless of its
/// content type.
public enum ResultContent: Equatable, Hashable, Sendable {
    case text
    case url
    case number
    /// A saved Snippet, keyed by its Action id so the edge can resolve the
    /// stored record (CONTEXT.md → Snippet). Distinct from a bare `.text` value
    /// precisely because a Snippet is a *stored, titled* record the user can
    /// **edit** — a text-bearing Calculator result or Fallback URL cannot. That
    /// identity is what lets `secondaryActions(for:)` add Edit to a Snippet's
    /// menu while a plain `.text` row keeps only the universal copy/share.
    case snippet(id: String)
    /// An imported Shortcut Action, keyed by the shortcut's **name** — its stable
    /// identity (ADR 0007), the same handle the run path already carries. Unlike
    /// every other case it wraps **no textual value** to copy or share: it is a
    /// pure reference to a launchable item the user can open for editing in the
    /// Shortcuts app. That reference is what lets `secondaryActions(for:)` offer
    /// **Edit** (a deeplink into `shortcuts://open-shortcut`) on a Shortcut row
    /// that would otherwise, as a command-like `.none` row, expose nothing.
    case shortcut(name: String)
    /// A Pile entry's text, resolved from the store by the entry's id at the
    /// edge (CONTEXT.md → Pile; ADR 0018).
    case pileEntry(id: String)
    /// A file, resolved from its Indexed-Folder bookmark + relative path at the
    /// edge — never a filesystem URL in Core (ADR 0015).
    case file(bookmarkID: String, relativePath: String)
    case none
}

/// A one-shot verb a long-press menu offers for a result's content (ADR 0017).
/// A bare verb enum — Core decides *eligibility*; the App owns every execution
/// and edge-resolution (a Pile entry's text in the store, a file behind a
/// bookmark), so even Copy cannot run in Core. Deliberately narrow this slice: the universal
/// `copy`/`share`, plus `revealInFiles` on a file and `edit` on a Snippet or a
/// Shortcut — each a per-content verb the App resolves at the edge (open the
/// Snippet editor seeded from the stored record, or deeplink into the Shortcuts
/// app's editor by name). Multi-step per-type verbs (Make-Reminder, Convert, …)
/// are deferred to a later breadcrumb-seeding slice, where `secondaryActions(for:)`
/// is the extension point.
public enum SecondaryActionKind: Equatable, Hashable, Sendable {
    case copy
    case share
    case revealInFiles
    /// Open the item in its own editor. Offered for a `.snippet` — a stored,
    /// titled record the App opens in the Snippet editor — and for a `.shortcut`,
    /// where it deeplinks into `shortcuts://open-shortcut` to open the named
    /// shortcut in the Shortcuts app for editing. Never a bare `.text` value. The
    /// App resolves the reference by id/name and performs the open; Core only
    /// declares the verb eligible.
    case edit
}

/// The eligible secondary actions for a result's content (ADR 0017): a pure
/// switch on `ResultContent`, **not** a `[ContentType: …]` table. `.none`
/// excludes command / capture rows for free; `.file` adds `revealInFiles`;
/// `.snippet` adds `edit` on top of copy/share; a `.shortcut` offers `edit`
/// **alone** (no text to copy or share); every other content-bearing case gets
/// the universal `copy`/`share`. No dead items — a verb is listed only when it
/// can run.
public func secondaryActions(for content: ResultContent) -> [SecondaryActionKind] {
    switch content {
    case .none:
        return []
    case .file:
        return [.copy, .share, .revealInFiles]
    case .snippet:
        // A Snippet is a stored, titled record, so it earns Edit on top of the
        // universal copy/share — resolvable only because `.snippet` carries the
        // record's id, unlike a bare `.text` value.
        return [.copy, .share, .edit]
    case .shortcut:
        // A Shortcut carries no textual value to copy or share — it is a pure
        // reference to a launchable item — so it earns only Edit: a deeplink into
        // the Shortcuts app's editor for the named shortcut.
        return [.edit]
    case .text, .url, .number, .pileEntry:
        return [.copy, .share]
    }
}
