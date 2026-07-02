/// The concrete value or reference a result carries — the thing a secondary
/// action operates on (CONTEXT.md → Result content; ADR 0017). Distinct from
/// both its content *type* (the kind) and its *main action* (what tapping it
/// does). Encodes **presence and value**, not just type, which is exactly what
/// lets a text-bearing Snippet (`.text`) be told apart from a text-*typed*
/// Settings command (`.none`): a type-keyed table could not.
///
/// Either an inline value the App reads off the Action's own outcome (`.text`,
/// `.url`, `.number`) or an edge-resolved reference the App dereferences on
/// demand (a Pile entry's text by id, a file by bookmark + relative path). A
/// command, capture, or Shortcut row has **`.none`** — no content — which is
/// what makes it ineligible for secondary actions regardless of its content
/// type.
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
/// `copy`/`share`, plus `revealInFiles` on a file and `edit` on a Snippet — each
/// a per-content verb the App resolves at the edge (open the Snippet editor
/// seeded from the stored record). Multi-step per-type verbs (Make-Reminder,
/// Convert, …) are deferred to a later breadcrumb-seeding slice, where
/// `secondaryActions(for:)` is the extension point.
public enum SecondaryActionKind: Equatable, Hashable, Sendable {
    case copy
    case share
    case revealInFiles
    /// Open the Snippet editor on a saved Snippet (CONTEXT.md → Snippet). Offered
    /// only for `.snippet` content — a stored, titled record the user can revise —
    /// never a bare `.text` value. The App resolves the record by id and presents
    /// the editor; Core only declares the verb eligible.
    case edit
}

/// The eligible secondary actions for a result's content (ADR 0017): a pure
/// switch on `ResultContent`, **not** a `[ContentType: …]` table. `.none`
/// excludes command / capture / shortcut rows for free; `.file` adds
/// `revealInFiles`; `.snippet` adds `edit`; every content-bearing case gets the
/// universal `copy`/`share`. No dead items — a verb is listed only when it can
/// run.
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
    case .text, .url, .number, .pileEntry:
        return [.copy, .share]
    }
}
