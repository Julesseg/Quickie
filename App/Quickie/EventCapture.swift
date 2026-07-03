import SwiftUI
import QuickieCore

// The New Event quick capture as a `Capture` recipe (issue #38): the settings that
// gate its steps and pick silent-vs-editor, the conformance that supplies EventKit
// permission, the configured `Action.newEvent`, and the performer that either writes
// silently or hands off to the system event editor. The breadcrumb engine, the
// morphing input, and the enter/leave animations are all generic (`Capture.swift`) —
// this file is purely what makes the capture an *event* rather than a reminder.

// MARK: - Settings

/// The New Event settings, read from `@AppStorage` with working defaults (ADR 0012)
/// and rendered from the declared schema (ADR 0020; issue #69). The calendar picker
/// is now a single `dynamic choice`: `calendarStored` is empty for "Ask each time"
/// (`.ask`) or a fixed calendar id — the string the schema's picker persists, read
/// back here. Keys are Core-owned (`SettingsKey`) so the schema and the capture never
/// drift onto different keys.
struct EventSettings {
    /// The calendar dynamic choice's stored value: empty = "Ask each time" (`.ask`),
    /// else a fixed calendar id.
    var calendarStored: String = ""
    /// Open the pre-filled system event editor for final review instead of writing
    /// silently (default **silent**, OFF).
    var useEditor: Bool = false

    /// How the calendar step is routed (CONTEXT.md → Event): the stored dynamic
    /// choice, mapped by Core — empty is "Ask each time", any value a fixed calendar.
    var calendarSelection: EventCalendarSelection {
        EventCalendarSelection(stored: calendarStored)
    }
}

// MARK: - Editor presenter

/// The bridge that lets the (`Sendable`) `EventCapture` recipe ask the SwiftUI layer
/// to present the system event editor (issue #38). A `@MainActor @Observable`
/// reference type — so it is `Sendable` and can be held by the recipe across the
/// capture's `Task`s — whose `request` drives a `.sheet` in `RootView`. Editor mode's
/// `perform` sets the request here rather than returning a toast; the system editor
/// is its own confirmation surface.
@MainActor
@Observable
final class EventEditorPresenter {
    /// The pending editor request, or `nil` when no editor is showing.
    var request: EventEditorRequest?

    /// Presents the system event editor pre-filled from `draft`.
    func present(_ draft: EventDraft) {
        request = EventEditorRequest(draft: draft)
    }
}

/// One request to present the system event editor — the pure `EventDraft` to
/// pre-fill, plus a fresh identity so `.sheet(item:)` presents each handoff distinctly.
struct EventEditorRequest: Identifiable {
    let id = UUID()
    let draft: EventDraft
}

// MARK: - Capture recipe

/// The New Event capture (CONTEXT.md → Event; issue #38): the `Capture` conformance
/// that resolves EventKit permission just-in-time, builds the configured
/// `Action.newEvent` from the user's calendars + settings, and either writes the
/// resulting `EventDraft` silently or hands it to the system editor. Everything
/// visible — the breadcrumb, the morphing input, the enter/leave motion — comes from
/// the generic `CaptureModel`/views; this only fills in what is specific to events.
struct EventCapture: Capture {
    let settings: EventSettings
    let service: EventsService
    /// The handoff target for editor mode — the app's editor presenter, set when the
    /// final commit resolves to `.composeEvent`.
    let presenter: EventEditorPresenter

    init(settings: EventSettings, presenter: EventEditorPresenter, service: EventsService = EventsService()) {
        self.settings = settings
        self.presenter = presenter
        self.service = service
    }

    /// Calendar permission resolved synchronously off the process-wide status (ADR
    /// 0012): refused → the inline affordance, granted → straight in, not-yet-asked →
    /// the primer before the system dialog.
    var access: CaptureAccess {
        if service.isDenied { return .denied }
        if service.isAuthorized { return .ready }
        return .needsPrimer
    }

    func requestAccess() async -> Bool {
        await service.requestAccess()
    }

    /// The calendar step's options are the user's writable calendars, resolved from
    /// EventKit at the moment the capture starts; the `editor` setting bakes in
    /// whether the final commit writes silently or opens the system editor.
    func makeAction() async -> Action {
        let calendars = await service.writableCalendars()
        return .newEvent(
            calendar: settings.calendarSelection,
            calendars: calendars,
            editor: settings.useEditor
        )
    }

    /// Performs the completed capture's outcome: `createEvent` writes silently and
    /// reports the tappable "Event added" confirmation; `composeEvent` hands the
    /// draft to the system event editor and returns `nil` (the editor is its own
    /// confirmation). A non-event outcome can't arise from this capture, so it is
    /// treated as a failure.
    func perform(_ outcome: ActionOutcome) async -> CaptureConfirmation? {
        switch outcome {
        case .createEvent(let draft):
            do {
                let link = try await service.create(draft)
                return CaptureConfirmation(message: "Event added", openURL: link)
            } catch {
                return CaptureConfirmation(message: "Couldn't add event", isError: true)
            }
        case .composeEvent(let draft):
            await presenter.present(draft)
            return nil
        default:
            return CaptureConfirmation(message: "Couldn't add event", isError: true)
        }
    }

    var copy: CaptureCopy {
        CaptureCopy(
            primerIcon: "calendar",
            primerText: "Quickie saves this to your Calendar.",
            deniedIcon: "lock.fill",
            deniedText: "Enable Calendar access to capture events."
        )
    }
}
