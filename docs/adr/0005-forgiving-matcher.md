# Custom layout-adaptive forgiving matcher

Quickie builds its own fuzzy matcher rather than using an off-the-shelf library, because the signature requirement — tolerance for fat-fingered phone typing — needs **keyboard-adjacency weighting**, which no Swift fuzzy library provides.

The matcher layers:

1. **Subsequence scoring** (fzf/Sublime-style) — base score rewarding consecutive runs, word-boundary starts, and prefixes.
2. **Damerau-Levenshtein** with a small edit budget — tolerates transpositions (the dominant thumb-typing error) plus single insert/delete/substitute.
3. **Keyboard-adjacency weighting** — substitutions to a physically adjacent key cost less than distant ones. This is the differentiator and the reason we build rather than borrow.
4. **Normalization** — lowercase + diacritic stripping (so `cafe` matches `café`), matched against per-Action aliases/keywords, token-order-independent.
5. **Trigram prefilter** — shortlists candidates before the expensive edit-distance pass so it scales per keystroke over a large index.

**Layout-adaptive adjacency:** the adjacency table is selected from the **active keyboard's primary language** (`UITextInputMode.primaryLanguage`), swapped live on `UITextInputCurrentInputModeDidChange`. We ship hardcoded tables (QWERTY, AZERTY, QWERTZ, …) and map language → layout, because iOS does not expose key geometry. For third-party/custom keyboards whose geometry is opaque, we fall back to the language-implied layout and ultimately to QWERTY; the non-adjacency layers still cover those cases.

Reversible in principle, but recorded because keyboard-adjacency and layout detection are non-obvious and a future reader would otherwise assume a stock fuzzy library.
