# Split Quicklink into static Quicklink + Fallback query

## Context

Originally a **Quicklink** was one polymorphic concept: a URL *template* that
behaved as a static link when it had no `{placeholder}` and as a query-consuming
link when it did, and any placeholder one could be flagged a Fallback (ADR 0008:
"Any placeholder-Quicklink can be flagged a Fallback"). One data type, two
behaviours, with `templateHasPlaceholder` auto-detecting which and a "Pin as
Fallback" toggle gating the rest.

## Decision

Split it into two single-behaviour concepts:

- **Quicklink** — a *static* URL that opens directly. No placeholder, consumes no
  typed text, matches by name. Quickie ships **no default Quicklinks**.
- **Fallback query** — a URL template that **requires** a `{placeholder}` and
  consumes the typed text as its query. It is one kind of **Fallback Action**
  (alongside New Note / New Snippet) and lives on the unified Fallbacks page.

Web search stops being a privileged built-in and becomes an ordinary,
default-seeded, fully deletable Fallback query.

## Consequences

- The thing's *page* now determines its type; the auto-detecting
  `templateHasPlaceholder` branch and the "Pin as Fallback" toggle disappear.
- SwiftData model change with migration: `StoredQuicklink` loses its
  template/fallback affordances and a new `StoredFallbackQuery` entity is
  introduced. This is the meaningful cost of reversing the decision.
- Supersedes the "any placeholder-Quicklink can be flagged a Fallback" point in
  ADR 0008; the rest of 0008 (result list, main/secondary actions) stands.

## Considered options

- **Keep the polymorphic Quicklink** (status quo). Rejected: overloading one
  concept with two behaviours kept the editor branchy and made "is this a link
  or a search?" an inferred property rather than a clear, separately-managed
  type. A reset-to-defaults affordance for seeded Fallback queries can recover
  the small convenience the built-in web search gave, without the overload.
