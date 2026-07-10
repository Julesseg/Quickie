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
    /// A stored **Quicklink**, keyed by its Action id so the edge can resolve the
    /// record the user opens for editing (CONTEXT.md → Quicklink). Distinct from a
    /// bare `.url` value precisely because a Quicklink is a *stored, titled* static
    /// link the user can **edit** — a Calculator-derived or otherwise value-only URL
    /// cannot. It still carries a real URL to copy or share (unlike `.customAction`
    /// or `.shortcut`, whose values only exist once run), so its identity adds
    /// **Edit** *on top of* the universal copy/share — the Snippet pattern, for a URL.
    case quicklink(id: String)
    /// A stored **Custom Action** (a URL template), keyed by its Action id so the
    /// edge can resolve the record the user opens in the live-mirroring editor
    /// (CONTEXT.md → Custom Action). Like a `.shortcut` it wraps **no textual value**
    /// to copy or share — its URL only exists once the breadcrumb fills its `{slots}`
    /// — so it is a pure reference to an editable item. That reference is what lets
    /// `secondaryActions(for:)` offer **Edit** (open the editor) on a Custom Action
    /// row that would otherwise, as a hand-off `.none` row, expose nothing.
    case customAction(id: String)
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
/// bookmark), so even Copy cannot run in Core. The content-keyed verbs: the universal
/// `copy`/`share`, plus `revealInFiles` on a file and `edit` on a Snippet or a
/// Shortcut — each a per-content verb the App resolves at the edge (open the
/// Snippet editor seeded from the stored record, or deeplink into the Shortcuts
/// app's editor by name). Alongside them one **id-keyed** verb, `copyDeeplink`,
/// eligible on *every* row (§`secondaryActions`). Multi-step per-type verbs
/// (Make-Reminder, Convert, …) are deferred to a later breadcrumb-seeding slice,
/// where `secondaryActions(for:)` is the extension point.
public enum SecondaryActionKind: Equatable, Hashable, Sendable {
    case copy
    case share
    case revealInFiles
    /// Open the item in its own editor. Offered for every **user-authored,
    /// editable** record — a `.snippet` (opened in the Snippet editor), a
    /// `.quicklink` (its create/edit form) and a `.customAction` (the live-mirroring
    /// URL-template editor), all resolved by id to the stored record the App opens
    /// in-app — and for a `.shortcut`, where it deeplinks into
    /// `shortcuts://open-shortcut` to open the named shortcut in the Shortcuts app.
    /// Never a bare `.text`/`.url` *value* (a Calculator result, a value-only URL):
    /// only a stored record the user can revise earns it. The App resolves the
    /// reference by id/name and performs the open; Core only declares the verb eligible.
    case edit
    /// **Copy action deeplink**: put this row's `quickie://run/<id>` URL on the
    /// pasteboard (issue #120; `QuickieDeeplink.runURL`). Unlike every other verb
    /// this keys off the Action's **id**, not its Result content, so it is offered on
    /// *every* row — a content-less command or capture row included — since every
    /// row is addressable by its id (a Favorite/Custom Action resolves live; other
    /// ids simply degrade to Home on open, the same graceful-staleness rule). The
    /// App builds the URL and writes the pasteboard; Core only declares the verb.
    case copyDeeplink
}

/// The eligible secondary actions for a result's content (ADR 0017): a pure
/// switch on `ResultContent`, **not** a `[ContentType: …]` table. The content-keyed
/// verbs come first — `.file` adds `revealInFiles`; a `.snippet` and a `.quicklink`
/// each add `edit` on top of copy/share (a stored, editable record that still carries
/// a value); a `.shortcut` and a `.customAction` offer `edit` **alone** (an editable
/// reference with no text or pre-resolved URL to copy or share); a `.none`
/// command/capture row has none of them; every other content-bearing case gets the
/// universal `copy`/`share`. Then **`copyDeeplink` is appended** (issue #120): it
/// keys off the Action's id, which every row has, so it is the one verb a content-less
/// row still exposes — **but only when the row's `quickie://run/<id>` actually runs to
/// an effect**. A **query-only capture** (Save for later / New Snippet) does nothing
/// standalone (issue #140 review), so its deeplink is a no-op not worth copying: the
/// caller passes `includeDeeplink: false` for it and the verb is dropped, leaving that
/// row with no secondary actions at all. `includeDeeplink` defaults to `true`, so every
/// other row — a command, a Pile entry (whose deeplink stages), any content row — keeps
/// it exactly as before. Content verbs stay first so the menu reads value-first; the
/// deeplink utility sits last. No dead items — every listed verb can run (a copy always
/// succeeds; whether the copied deeplink later resolves is the open path's
/// graceful-staleness concern).
public func secondaryActions(for content: ResultContent, includeDeeplink: Bool = true) -> [SecondaryActionKind] {
    let contentVerbs: [SecondaryActionKind]
    switch content {
    case .none:
        contentVerbs = []
    case .file:
        contentVerbs = [.copy, .share, .revealInFiles]
    case .snippet, .quicklink:
        // A Snippet and a Quicklink are each stored, titled records the user can
        // revise, so each earns Edit on top of the universal copy/share — resolvable
        // only because the content carries the record's id, unlike a bare `.text`
        // value or a value-only `.url`. The App resolves the id and opens the
        // matching in-app editor (Snippet editor / Quicklink form).
        contentVerbs = [.copy, .share, .edit]
    case .shortcut, .customAction:
        // Neither carries a textual value to copy or share — a Shortcut is a pure
        // reference to a launchable item, and a Custom Action's URL only exists once
        // its slots are filled — so each earns only Edit: a Shortcut deeplinks into
        // the Shortcuts app's editor, a Custom Action opens its live-mirroring editor.
        contentVerbs = [.edit]
    case .text, .url, .number, .pileEntry:
        contentVerbs = [.copy, .share]
    }
    // Every runnable row is addressable by its id, so Copy action deeplink rides on it —
    // the lone verb a content-less command row exposes. A query-only capture's deeplink
    // is a no-op, so the caller drops it (`includeDeeplink: false`).
    return includeDeeplink ? contentVerbs + [.copyDeeplink] : contentVerbs
}
