import Observation
import QuickieCore

/// The app-side hook that feeds a `dynamic choice` its live options (ADR 0020;
/// issue #69) — the app-supplied bridge the ADR calls for. Core names the source
/// (`DynamicOptionSource`); this resolves it to the concrete `[ChoiceOption]` the
/// generic Options renderer's picker shows: the user's writable EventKit calendars
/// for the New Event calendar picker, their modifiable reminder lists for New
/// Reminder's. Injected into the provider pages' environment like
/// `ProviderEnablementStore`, so every dynamic choice reads the same live source the
/// captures themselves build their steps from.
///
/// An unauthorized EventKit store returns an empty set — resolving here never prompts
/// for permission (that stays just-in-time on capture, ADR 0012), so a dynamic choice
/// simply offers its "Ask each time" placeholder until access is granted elsewhere.
@MainActor
@Observable
final class DynamicSettingOptions {
    @ObservationIgnored private let events: EventsService
    @ObservationIgnored private let reminders: RemindersService

    init(events: EventsService = EventsService(), reminders: RemindersService = RemindersService()) {
        self.events = events
        self.reminders = reminders
    }

    /// The live options for a dynamic choice's source, resolved at render time.
    func options(for source: DynamicOptionSource) async -> [ChoiceOption] {
        switch source {
        case .eventCalendars: return await events.writableCalendars()
        case .reminderLists: return await reminders.reminderLists()
        }
    }
}
