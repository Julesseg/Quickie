import AppIntents
import SwiftData
import QuickieCore
import QuickieStoreKit

/// The four **headline App Shortcuts** (CONTEXT.md → Bridged Action; issue #121;
/// ADR 0024), registered so Siri, Spotlight, the Shortcuts app, and the Action
/// Button picker can invoke Quickie's headline verbs. These are the static,
/// phrase-invoked verbs — distinct from the derived, parameterized Bridged Action
/// shortcut (Favorites ∪ Custom Actions), which is slice 3's job.
///
/// The intent types live in the App target because App Intents is app-process and
/// Apple-only, but everything *decidable* lives in `QuickieCore.HeadlineAppShortcut`
/// under the Linux `swift test` gate: the split invoke shapes, the `quickie://` route
/// each foreground verb opens, and the Save-for-later write guard. These structs are
/// the thin Apple shell over that. (`QuickCaptureIntent` is the one exception to
/// "here": it lives in the `QuickieEntry` folder shared with the widget extension so
/// the Control Center control (#125) can ride the very same intent.)
struct QuickieAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickCaptureIntent(),
            phrases: [
                "Quick Capture in \(.applicationName)",
                "Quick capture with \(.applicationName)",
                "New capture in \(.applicationName)",
            ],
            shortTitle: "Quick Capture",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SaveForLaterIntent(),
            phrases: [
                "Save for later in \(.applicationName)",
                "Save to \(.applicationName) for later",
                "Add to my \(.applicationName) pile",
            ],
            shortTitle: "Save for later",
            systemImageName: "tray.and.arrow.down"
        )
        AppShortcut(
            intent: NewReminderIntent(),
            phrases: [
                "New Reminder in \(.applicationName)",
                "Create a reminder in \(.applicationName)",
            ],
            shortTitle: "New Reminder",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: NewEventIntent(),
            phrases: [
                "New Event in \(.applicationName)",
                "Create an event in \(.applicationName)",
            ],
            shortTitle: "New Event",
            systemImageName: "calendar.badge.plus"
        )
        // The single **parameterized** App Shortcut over the derived [[Bridged Action]]
        // set (slice 3; ADR 0024): one entity, one phrase, whose `<name>` slot the
        // dynamic `BridgedActionQuery` fills with the user's Favorites ∪ Custom Actions
        // — so each member surfaces individually in Siri and Spotlight without a
        // per-Action shortcut. `updateAppShortcutParameters()` (fired by `RootView` on
        // every set change) keeps the offered names in step with the live set.
        AppShortcut(
            intent: RunBridgedActionIntent(),
            phrases: [
                "Run \(\.$target) with \(.applicationName)",
                "Run \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Run Action",
            systemImageName: "bolt"
        )
    }
}

// MARK: - Foreground verbs (steer the app through the slice-1 deeplink door)

// `QuickCaptureIntent` and the shared `openInApp(_:)` hand-off live in
// `QuickieEntry/QuickCaptureIntent.swift`, a folder synced into both this app target
// and the widget extension so the Control Center control (issue #125) can ride the
// exact same intent — one intent, one inbound door (ADR 0024).

/// **New Reminder** — opens the app into the Reminder capture breadcrumb at
/// Argument 1 via `quickie://run/builtin.new-reminder` (ADR 0024: a tap-equivalent
/// run of the built-in capture command row *is* "open that capture"). A disabled
/// Reminders kind degrades to Home, the same graceful-staleness rule every bridged
/// id follows.
struct NewReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "New Reminder"
    static let description = IntentDescription(
        "Open Quickie and start a new reminder."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        openInApp(.newReminder)
        return .result()
    }
}

/// **New Event** — opens the app into the Event capture breadcrumb at Argument 1 via
/// `quickie://run/builtin.new-event`, the same shape as New Reminder.
struct NewEventIntent: AppIntent {
    static let title: LocalizedStringResource = "New Event"
    static let description = IntentDescription(
        "Open Quickie and start a new calendar event."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        openInApp(.newEvent)
        return .result()
    }
}

// MARK: - Background verb (silent write, no app switch)

/// **Save for later** — the background verb (ADR 0024): Siri dictates the text and
/// this intent writes a titleless [[Pile]] entry silently through `QuickieStoreKit`
/// to the shared App Group store — the Share Extension's write pattern (ADR 0022),
/// surfacing in the app on the next foreground re-index. No app switch, true to the
/// glossary's "silent capture".
///
/// Empty dictation is re-prompted by Siri, never written: `HeadlineAppShortcut`'s
/// pure write guard returns `nil` for whitespace-only text, and this throws a
/// `needsValueError` so Siri asks again instead of inserting a blank row — the same
/// trim-and-drop-empty rule the in-app "Save for later" capture applies.
struct SaveForLaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Save for later"
    static let description = IntentDescription(
        "Save a note to your Quickie pile to deal with later."
    )
    // Silent capture: no app switch (ADR 0024). `openAppWhenRun` stays false.

    @Parameter(title: "Text", requestValueDialog: "What would you like to save for later?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text) for later")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // The pure guard shared with the in-app capture: trim, and treat an empty
        // dictation as "nothing to write" so Siri re-prompts rather than saving a
        // blank Pile entry.
        guard let entryText = HeadlineAppShortcut.pileText(fromDictated: text) else {
            throw $text.needsValueError("What would you like to save for later?")
        }

        // Write through the shared store exactly like the Share Extension (ADR 0022):
        // the App Group container or an honest failure, never a silent private
        // fallback that the app could never read. Failures are surfaced as
        // Siri-readable messages that mirror the Share Extension's crafted copy for
        // the same failure modes, so the two write surfaces tell one consistent story
        // instead of one leaking a raw thrown error.
        do {
            let container = try QuickieStore.appGroupContainer()
            let context = ModelContext(container)
            context.insert(StoredPileEntry(text: entryText))
            try context.save()
        } catch QuickieStore.AppGroupStoreError.appGroupUnavailable {
            throw SaveForLaterError.storageUnavailable
        } catch {
            throw SaveForLaterError.saveFailed
        }

        return .result()
    }
}

/// The Siri-facing failures of the background Save for later write, worded to match
/// the Share Extension's crafted messages for the same shared-store failure modes
/// (ADR 0022): the two write surfaces should read the same when the App Group is
/// missing or the store won't open. Conforms to `CustomLocalizedStringResourceConvertible`
/// so App Intents surfaces the message to the user rather than a generic error.
enum SaveForLaterError: Error, CustomLocalizedStringResourceConvertible {
    /// The App Group isn't provisioned, so there is no shared store to write into.
    case storageUnavailable
    /// The shared store exists but the write failed.
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storageUnavailable:
            return "Quickie's shared storage isn't available, so nothing could be saved."
        case .saveFailed:
            return "Saving to your pile failed, so nothing was saved."
        }
    }
}
