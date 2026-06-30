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
/// 0012) so the capture is fully functional before any Settings UI exists. The
/// Settings → Actions registry that will host these lives elsewhere.
struct ReminderSettings {
    static let askDateKey = "reminder.askDate"
    static let askListKey = "reminder.askList"
    static let defaultListIDKey = "reminder.defaultListID"

    /// Ask for a due date (default ON); OFF skips the date step.
    var askDate: Bool = true
    /// Ask for the target list every capture (default ON → the list is the third
    /// breadcrumb step, fuzzy-found over the user's lists); OFF routes silently to
    /// `defaultListID` (empty → the system default reminders list).
    var askList: Bool = true
    /// The preset list's identifier; empty means the system default reminders list.
    var defaultListID: String = ""

    /// How the list step is routed (CONTEXT.md → Reminder): ask every capture, or
    /// a fixed default list — an empty id being the system default.
    var listSelection: ReminderListSelection {
        askList ? .ask : .fixed(id: defaultListID.isEmpty ? nil : defaultListID)
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
            list: settings.listSelection,
            lists: lists
        )
    }

    /// Performs the completed capture's `createReminder` outcome against EventKit,
    /// reporting the tappable "Reminder added" confirmation (carrying the deep
    /// link) or an error acknowledgement. A non-`createReminder` outcome can't
    /// arise from this capture, so it is treated as a failure.
    func perform(_ outcome: ActionOutcome) async -> CaptureConfirmation {
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
