# Actions come from Providers, split into Indexed and Dynamic

Every Action in Quickie originates from a **Provider**, and Providers are one of two kinds:

- **Indexed Providers** contribute a known, enumerable set of Actions (Snippets, Quicklinks, Shortcuts, favorites, built-in commands). These are loaded into an in-memory fuzzy index and re-indexed only when their data changes. They satisfy the "fast, reliable search over many results" goal — querying is index lookups, not recomputation.
- **Dynamic Providers** compute Actions on the fly from the current query and are never in the fuzzy index (Calculator, Unit Converter, File Search over Indexed Folders, Web Search and other Fallbacks). They are invoked live per keystroke — debounced, cancellable, possibly async — and each decides whether it even applies to the current query.

The result list merges both streams under one ranking policy; indexed matches and dynamic results compete in the same list.

This split is the core extensibility seam. It is chosen over a single uniform "search everything live" model (too slow for large static sets) and over a single "index everything" model (impossible for computed results like a calculator answer that doesn't exist until typed). New capabilities are added by writing a Provider of the appropriate kind.

"Extension" was rejected as the name because it collides with iOS app-extension terminology.
