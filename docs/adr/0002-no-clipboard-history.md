# No automatic clipboard history

Despite the Raycast inspiration, Quickie will **not** offer an automatic clipboard history. iOS provides no clipboard-history API and no background pasteboard access: an app can read the clipboard only while foregrounded and in response to explicit user action, and every content read fires the system "pasted from…" banner (iOS 14+). Ambient capture of everything the user copies is therefore impossible.

Instead:

- **Snippets** cover the "saved text I want to re-copy" need — a user-curated, searchable list, addable via the Share Extension (banner-free).
- **Clipboard prefill** covers "act on what I just copied" — a launch-time, tap-to-fill paste chip using the iOS Paste control (no banner), gated by a silent `hasStrings` metadata check.

This sidesteps the privacy banners entirely and removes the need to special-case capture from password managers, since nothing is ever captured without an explicit user tap.
