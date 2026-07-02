import SwiftUI
import QuickieCore

/// The Events provider page (CONTEXT.md → Management page; ADR 0019, issue #66)
/// — the former New Event settings panel, now the unified page the hub's Events
/// row lands on. Its options shape the capture: whether to ask which calendar
/// each time (vs. routing silently to the default calendar), and whether to
/// open the pre-filled system event editor for final review instead of writing
/// silently. An instance-less capture provider, so there is no actions list
/// beneath the options (its one capture is the typed "New Event" row itself).
///
/// Both persist via `@AppStorage`, so flipping one here updates the value the next
/// New Event activation reads in `RootView.startEventCapture`. The `@AppStorage`
/// defaults must match `RootView`'s declarations of the same keys, so the first read
/// before any write agrees no matter which view loads first.
struct EventSettingsView: View {
    @AppStorage(EventSettings.askCalendarKey) private var askCalendar = true
    @AppStorage(EventSettings.editorKey) private var useEditor = false

    var body: some View {
        Form {
            // The unified page shape (ADR 0019; issue #66): the shared Options
            // lead-in, with the real capture options beneath until the declared
            // settings schema absorbs them (a later slice).
            ProviderOptionsSection(provider: .events)

            Section {
                Toggle("Ask which calendar each time", isOn: $askCalendar)
                    .accessibilityIdentifier("event-ask-calendar")
            } header: {
                Text("Calendar")
            } footer: {
                Text("On adds a calendar step to the capture. Off saves to your default calendar.")
            }

            Section {
                Toggle("Review in Calendar before saving", isOn: $useEditor)
                    .accessibilityIdentifier("event-use-editor")
            } header: {
                Text("Saving")
            } footer: {
                Text("On opens the system event editor pre-filled with what you captured — so you can set alerts, invitees, or recurrence before saving. Off saves silently.")
            }
        }
        .navigationTitle("Events")
    }
}
