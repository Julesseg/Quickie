import Foundation
import QuickieCore

// The New Reminder quick capture as a `Capture` recipe (issue #37): the settings
// that gate its steps and the conformance that supplies EventKit permission, the
// configured `Action.newReminder`, and the `createReminder` performer. The
// breadcrumb engine, the morphing input, and the enter/leave animations are all
// generic (`Capture.swift`) — this file is purely what makes the capture a
// *reminder* rather than the next capture (a New Event).

// MARK: - Settings

/// The New Reminder settings, read from `@AppStorage` with working defaults (ADR
/// 0012) and rendered from the declared schema (ADR 0020; issue #69). The list picker
/// is now a single `dynamic choice`: `listStored` is empty for "Ask each time"
/// (`.ask`) or a fixed list id — the string the schema's picker persists, read back
/// here. Keys are Core-owned (`SettingsKey`) so the schema and the capture never drift.
struct ReminderSettings {
    /// Ask for a due date (default ON); OFF skips the date step.
    var askDate: Bool = true
    /// Ask for notes (issue #145, default OFF); ON adds the opt-in Notes step.
    var askNotes: Bool = false
    /// Ask for a priority (issue #145, default OFF); ON adds the opt-in Priority step.
    var askPriority: Bool = false
    /// The list dynamic choice's stored value: empty = "Ask each time" (`.ask`),
    /// else a fixed list id.
    var listStored: String = ""

    /// How the list step is routed (CONTEXT.md → Reminder): the stored dynamic
    /// choice, mapped by Core — empty is "Ask each time", any value a fixed list.
    var listSelection: ReminderListSelection {
        ReminderListSelection(stored: listStored)
    }
}

// MARK: - Capture recipe

/// The New Reminder capture (CONTEXT.md → Reminder; issue #37): the `Capture`
/// conformance that resolves EventKit permission just-in-time, builds the
/// configured `Action.newReminder` from the user's lists + settings, and performs
/// the resulting `ReminderDraft` against EventKit. Everything visible — the
/// breadcrumb, the morphing input, the enter/leave motion — comes from the generic
/// `CaptureModel`/views; this only fills in what is specific to reminders.
struct ReminderCapture: Capture {
    let settings: ReminderSettings
    let service: RemindersService

    init(settings: ReminderSettings, service: RemindersService = RemindersService()) {
        self.settings = settings
        self.service = service
    }

    /// Reminders permission resolved synchronously off the process-wide status
    /// (ADR 0012): refused → the inline affordance, granted → straight in,
    /// not-yet-asked → the primer before the system dialog.
    var access: CaptureAccess {
        if service.isDenied { return .denied }
        if service.isAuthorized { return .ready }
        return .needsPrimer
    }

    func requestAccess() async -> Bool {
        await service.requestAccess()
    }

    /// The list step's options are the user's modifiable reminder lists, resolved
    /// from EventKit at the moment the capture starts.
    func makeAction() async -> Action {
        let lists = await service.reminderLists()
        return .newReminder(
            askDate: settings.askDate,
            askNotes: settings.askNotes,
            askPriority: settings.askPriority,
            list: settings.listSelection,
            lists: lists
        )
    }

    /// Performs the completed capture's `createReminder` outcome against EventKit,
    /// reporting the tappable "Reminder added" confirmation (carrying the deep
    /// link) or an error acknowledgement. A non-`createReminder` outcome can't
    /// arise from this capture, so it is treated as a failure.
    func perform(_ outcome: ActionOutcome) async -> CaptureConfirmation? {
        guard case .createReminder(let draft) = outcome else {
            return CaptureConfirmation(message: "Couldn't add reminder", isError: true)
        }
        do {
            let link = try await service.create(draft)
            return CaptureConfirmation(message: "Reminder added", openURL: link)
        } catch {
            return CaptureConfirmation(message: "Couldn't add reminder", isError: true)
        }
    }

    var copy: CaptureCopy {
        CaptureCopy(
            primerIcon: "checklist",
            primerText: "Quickie saves this to your Reminders.",
            deniedIcon: "lock.fill",
            deniedText: "Enable Reminders access to capture reminders."
        )
    }
}

// MARK: - UI-test seam

/// A UI-test stand-in for the New Reminder capture (`-uitest-stub-reminders`):
/// the same configured `Action.newReminder` breadcrumb — title, due date, list —
/// with only the EventKit edge stubbed out (access granted, canned lists, no
/// write). It exists because XCUITest cannot pre-grant the simulator's Reminders
/// permission dialog, which otherwise kept the whole capture UI — most
/// importantly the date step's keyboard-less layout — out of the UI suite.
struct UITestReminderCapture: Capture {
    static let launchArgument = "-uitest-stub-reminders"

    /// Whether this run asked for the stub. Gated on `--uitesting` too, so the
    /// argument alone can never swap the real capture out of a production run.
    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains(launchArgument)
    }

    var access: CaptureAccess { .ready }

    func requestAccess() async -> Bool { true }

    func makeAction() async -> Action {
        .newReminder(
            askDate: true,
            list: .ask,
            lists: [
                ChoiceOption(id: "uitest.inbox", label: "Inbox"),
                ChoiceOption(id: "uitest.errands", label: "Errands"),
            ]
        )
    }

    /// No EventKit write — the completed capture is acknowledged with the same
    /// confirmation the real one flashes, so a test can drive the flow end-to-end.
    func perform(_ outcome: ActionOutcome) async -> CaptureConfirmation? {
        CaptureConfirmation(message: "Reminder added")
    }

    var copy: CaptureCopy { CaptureCopy() }
}
