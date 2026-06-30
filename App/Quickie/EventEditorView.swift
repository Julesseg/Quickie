import EventKit
import EventKitUI
import SwiftUI
import QuickieCore

/// The system event editor for New Event's editor mode (CONTEXT.md → Event; issue
/// #38): the pre-filled `EKEventEditViewController` the user reviews and confirms
/// instead of a silent write, reaching native fields (alerts, invitees, recurrence,
/// travel time) the breadcrumb never collects.
///
/// It builds its **own** main-thread `EKEventStore` and `EKEvent` from the pure
/// `EventDraft` — the editor controller is main-thread-affine, so it can't share the
/// `EventsService` actor's store. By the time editor mode is reached the capture has
/// already resolved calendar permission just-in-time (ADR 0012), and authorization is
/// process-wide, so this fresh store is authorized too. `onComplete` dismisses the
/// hosting sheet when the user saves, cancels, or deletes — the controller itself has
/// already committed any save to EventKit.
struct EventEditorView: UIViewControllerRepresentable {
    let draft: EventDraft
    var onComplete: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = makeEvent(in: store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    /// Pre-fills an `EKEvent` from the pure draft: title, the timed-vs-all-day span
    /// the Core already resolved, and the chosen calendar (or the system default when
    /// the draft routed to it or the chosen one is gone).
    private func makeEvent(in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.end
        if let id = draft.calendarID, let calendar = store.calendar(withIdentifier: id) {
            event.calendar = calendar
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }
        return event
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            // The controller commits a save itself; whatever the user chose, dismiss
            // the hosting sheet and return to the launcher.
            onComplete()
        }
    }
}
