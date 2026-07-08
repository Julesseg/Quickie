import Foundation

/// The four **headline App Shortcuts** (issue #121; ADR 0024) — the static,
/// phrase-invoked verbs the App Intents bridge registers so they surface in Siri,
/// Spotlight, the Shortcuts app, and the Action Button picker. Distinct from the
/// [[Bridged Action]] set (Favorites ∪ Custom Actions), which is a *derived*,
/// parameterized shortcut and slice 3's job.
///
/// The type is Core-owned and `swift test`-covered on purpose: the App target's
/// `AppIntent`s are a thin shell over it (App Intents is app-process, Apple-only),
/// and everything *decidable* — which shape each verb invokes in, the `quickie://`
/// route each foreground one opens, and the Save-for-later write guard — lives here
/// where the Linux test gate reaches it. Keeping the routes beside the built-in ids
/// they steer is the same "can never drift" rationale as `Action.saveForLaterID`.
///
/// ## Split invoke shapes (ADR 0024)
///
/// - **Quick Capture / New Reminder / New Event** run in the **foreground**: they
///   steer the app by opening a slice-1 `quickie://` deeplink through the single
///   root `onOpenURL` — Quick Capture rides `quickie://entry` (the open-focused
///   fresh-Home reset every entry surface of epic #16 uses), the two captures ride
///   `quickie://run/builtin.new-*` (a tap-equivalent run of the built-in capture
///   command row *is* "open that capture" — no parallel `capture/*` door).
/// - **Save for later** runs in the **background**: Siri dictates the text and the
///   intent writes the [[Pile]] entry silently through `QuickieStoreKit` to the
///   shared App Group store — the Share Extension's write pattern (ADR 0022),
///   surfacing on the next foreground re-index. It opens no deeplink, so its
///   `deeplink` is `nil`.
public enum HeadlineAppShortcut: String, CaseIterable, Sendable {
    case quickCapture
    case newReminder
    case newEvent
    case saveForLater

    /// The `quickie://` route a **foreground** shortcut opens, or `nil` for the
    /// **background** Save for later (which writes to the store instead of steering
    /// the app). Foreground routing goes through slice-1's `QuickieDeeplink`, so the
    /// whole grammar stays in one place the app only dispatches on.
    public var deeplink: QuickieDeeplink? {
        switch self {
        case .quickCapture:
            return .entry
        case .newReminder:
            return .run(id: Action.newReminderID)
        case .newEvent:
            return .run(id: Action.newEventID)
        case .saveForLater:
            return nil
        }
    }

    /// The concrete `quickie://` URL a foreground shortcut hands to the root
    /// `onOpenURL`, built through slice-1's `QuickieDeeplink` builders (so a
    /// title-derived id round-trips through `parse` intact); `nil` for the
    /// background Save for later. The App Intent opens this URL rather than
    /// string-joining one, keeping a single home for the grammar.
    public var deeplinkURL: URL? {
        switch deeplink {
        case .entry:
            return QuickieDeeplink.entryURL()
        case .run(let id):
            return QuickieDeeplink.runURL(id: id)
        case nil:
            return nil
        }
    }

    /// Whether this verb runs in the **background** — true only for Save for later,
    /// which writes silently to the store with no app switch (ADR 0024). The three
    /// foreground verbs steer the app through a deeplink, so they are `false`.
    public var runsInBackground: Bool { deeplink == nil }

    /// The [[Pile]] text a dictated **Save for later** value writes, or `nil` when
    /// there is nothing to write (empty or whitespace-only). This is the pure guard
    /// behind the acceptance rule "empty text is re-prompted by Siri, never written":
    /// the background intent asks this what to persist, gets `nil` for an empty
    /// dictation, and re-prompts instead of inserting a blank Pile row — the same
    /// trim-and-drop-empty rule the in-app "Save for later" capture applies, kept
    /// here so the two write surfaces can't diverge.
    public static func pileText(fromDictated raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
