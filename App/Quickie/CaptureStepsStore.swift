import Foundation
import Observation
import QuickieCore

/// Owns a quick-capture's **enabled, ordered step plan** (issue #145 follow-up) — the
/// steps the user has turned on, in the order they'll appear after the pinned Title —
/// the mirror of `FallbacksStore` for a capture's reorderable double-list. The pool
/// (disabled steps) is derived from the kind's fixed universe, so it is never stored.
///
/// Persisted as a raw-value id list in `UserDefaults.standard` alongside the other
/// capture settings (the same store the `@AppStorage` capture options use), so the
/// plan and the pickers on the same page never drift onto different stores. Kept
/// non-generic (raw `String`s + the kind's `universe`) so the view is the only place
/// that needs the concrete `CaptureStep` type; the pure ordering rules live in Core's
/// `CaptureStepPlan`, exercised by `swift test`.
@MainActor
@Observable
final class CaptureStepsStore {
    /// The enabled steps as raw ids, most-important-first (the breadcrumb order after
    /// the Title). Reconciled against `universe` on read/write so a stale id from an
    /// older build that knew a since-removed step is dropped rather than resurrected.
    private(set) var enabledRaw: [String]

    /// The kind's full step universe as raw ids, in canonical (declaration) order —
    /// the source the derived pool subtracts the enabled list from.
    @ObservationIgnored let universe: [String]

    @ObservationIgnored private let key: String
    @ObservationIgnored private let defaults: UserDefaults

    /// Builds the store, seeding the plan on first run (the key absent) from `seed` —
    /// which reads the retired per-setting keys so an upgrade preserves the old flow,
    /// and yields the first-run default on a fresh install (the old keys absent too).
    init(key: String, universe: [String], defaults: UserDefaults = .standard, seed: (UserDefaults) -> [String]) {
        self.key = key
        self.universe = universe
        self.defaults = defaults
        if let stored = defaults.stringArray(forKey: key) {
            self.enabledRaw = Self.reconcile(stored, universe: universe)
        } else {
            let seeded = Self.reconcile(seed(defaults), universe: universe)
            self.enabledRaw = seeded
            defaults.set(seeded, forKey: key)
        }
    }

    /// Drops raw ids not in the universe and de-duplicates, order preserved.
    private static func reconcile(_ stored: [String], universe: [String]) -> [String] {
        let known = Set(universe)
        var seen = Set<String>()
        return stored.filter { known.contains($0) && seen.insert($0).inserted }
    }

    /// The derived **disabled pool** as raw ids, in the universe's canonical order.
    var poolRaw: [String] {
        let active = Set(enabledRaw)
        return universe.filter { !active.contains($0) }
    }

    func isEnabled(_ raw: String) -> Bool { enabledRaw.contains(raw) }

    /// **Enables** a step — appends it to the bottom of the active list (promotion says
    /// "on", not "most important", like the Fallback list's green plus).
    func promote(_ raw: String) {
        guard universe.contains(raw), !enabledRaw.contains(raw) else { return }
        enabledRaw.append(raw)
        persist()
    }

    /// **Disables** a step — removes it from the active list back to the derived pool
    /// (the red minus). Nothing here is destructive; a disabled step just isn't collected.
    func demote(_ raw: String) {
        guard enabledRaw.contains(raw) else { return }
        enabledRaw.removeAll { $0 == raw }
        persist()
    }

    /// Applies a drag-reorder of the active list. `order` is the full active set (the
    /// universe is small and always loaded, so there is no not-yet-loaded slot to
    /// preserve the way the Fallback list has); persisted only when it actually changed.
    func reorder(_ order: [String]) {
        let reordered = Self.reconcile(order, universe: universe)
        guard reordered.count == enabledRaw.count, reordered != enabledRaw else { return }
        enabledRaw = reordered
        persist()
    }

    private func persist() {
        defaults.set(enabledRaw, forKey: key)
    }
}

extension CaptureStepsStore {
    /// The New Reminder step store, seeded/migrated from the retired reminder settings
    /// (issue #69/#145): the due-date toggle and whether the list was "ask each time".
    static func reminder(defaults: UserDefaults = .standard) -> CaptureStepsStore {
        CaptureStepsStore(
            key: SettingsKey.reminderSteps,
            universe: ReminderStep.allCases.map(\.rawValue),
            defaults: defaults
        ) { store in
            let askDate = (store.object(forKey: SettingsKey.reminderAskDate) as? Bool) ?? true
            let listStored = store.string(forKey: SettingsKey.reminderList) ?? ""
            return ReminderStep.migrated(askDate: askDate, listAsksEachTime: listStored.isEmpty)
                .map(\.rawValue)
        }
    }

    /// The New Event step store, seeded/migrated from the retired event settings
    /// (issue #69/#145): whether the calendar was "ask each time". The start was always
    /// collected, so `.start` seeds enabled.
    static func event(defaults: UserDefaults = .standard) -> CaptureStepsStore {
        CaptureStepsStore(
            key: SettingsKey.eventSteps,
            universe: EventStep.allCases.map(\.rawValue),
            defaults: defaults
        ) { store in
            let calendarStored = store.string(forKey: SettingsKey.eventCalendar) ?? ""
            return EventStep.migrated(calendarAsksEachTime: calendarStored.isEmpty)
                .map(\.rawValue)
        }
    }
}
