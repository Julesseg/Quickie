# Replace the Note system with the Pile

## Context

A **Note** was a full mini-feature: a captured free-text thought with a
**title**, whose main action **opened it for reading** (`.openNote(id:)`), plus
a **New Note** Fallback that opened a seeded compose-editor (`.composeNote`) so
the user could title and confirm before storing. It had its own reader/editor
views and an "All Notes" library page, and was framed as a Snippet twin — "same
storage, opposite main action" (Note reads, Snippet copies).

In practice that is more notes-app than a launcher wants to own. The recurring
real need is narrower: a place to drop **a query you didn't want to process on
the spot** and come back to it later.

## Decision

Replace Notes wholesale with the **Pile**: a collection of **raw query texts**
saved for later. There is **no title, no reader, and no compose-editor**. A Pile
entry is just a block of text.

- Its main action **stages** the text — replaces the input query and re-runs the
  matcher (the same reinjection move as a [[Shortcut Action]]'s returned output),
  after which the entry **leaves the Pile** (staging consumes it).
- Capture is **silent**: the **Save for later** Fallback (replacing New Note)
  drops the typed text straight into the Pile with no editor and no confirm step.
- Pile entries stay **fuzzy-searchable in Results**, matched over their **body
  text** (there is no title to match).
- The **Pile page** replaces "All Notes"; discarding an entry without staging it
  happens there via swipe-to-delete.

## Consequences

- Losing the read/title brain-dump use-case is the accepted cost. Anyone who
  wants durable, titled, readable notes should use a real notes app; Quickie
  exports there rather than being one.
- SwiftData model change with migration: the stored note loses its title and its
  reader/editor; the concept collapses to a text blob. This is the meaningful
  cost of reversing the decision.
- `.openNote`/`.composeNote` outcomes and `NoteEditorView` are removed; the
  `.notes` management-page case becomes `.pile`. `Snippet` is untouched (it keeps
  its title, editor, and copy-out main action).
- Per-row removal from Results rides the long-press [[Secondary action]]
  mechanism (ADR 0017): "Remove from Pile" is a Pile entry's content-keyed
  secondary action, alongside the universal copy/share.

## Considered options

- **Keep the Note system** (status quo). Rejected: a launcher does not want to
  own a notes app — titles, a reader, and a confirm-editor are weight the core
  loop ("input text and decide what to do with it after") does not need. The Pile
  keeps only the part that serves the loop: deferring a query and re-staging it.
- **Keep Notes but drop only the title/reader**, still opening something on tap.
  Rejected: without a title there is nothing to read, and "open" has no meaning
  distinct from "stage the text back into the input" — so staging *is* the
  action, not a fallback for a missing reader.
