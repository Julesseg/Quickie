import Foundation

/// A reorderable, opt-in **capture step** (issue #145 follow-up) — one member of a
/// quick-capture's fixed step universe that the user can enable/disable and reorder
/// on the provider page, exactly like the Fallback list's two-section double-list.
/// The pinned first step (the free-text **Title**) is never a member: it always
/// leads, so only the steps *after* it are arrangeable.
///
/// Raw values are **stable persisted identifiers** (never display strings), so a
/// title reword can't re-key a stored plan; `title`/`symbol` drive the settings row.
public protocol CaptureStepKind: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    /// The settings-row label — also the breadcrumb step's prompt.
    var title: String { get }
    /// The SF Symbol the settings row (and, for choice steps, each option row) shows.
    var symbol: String { get }
}

/// The pure resolution rules for a capture's step plan (issue #145 follow-up) —
/// mirroring `FallbackActivation`'s enabled-list model, kept in Core so the ordering,
/// the derived pool, and the first-run/migration seed are all covered by `swift test`.
/// The App's `CaptureStepsStore` is a thin `@Observable` edge wrapper over these.
///
/// The step universe is a small **fixed enum** per kind (not a live catalog), so there
/// is no eligibility-loss or launch-race care here: the enabled list is just the
/// ordered members the user has turned on, and the pool is everything else.
public enum CaptureStepPlan {
    /// The enabled steps in stored order, reconciled against the universe: raw values
    /// that don't resolve to a step are dropped and duplicates removed, order preserved.
    /// Robust to a stale store from an older build that knew a since-removed step.
    public static func resolved<Step: CaptureStepKind>(_ stored: [String], as type: Step.Type = Step.self) -> [Step] {
        var seen = Set<Step>()
        return stored.compactMap { Step(rawValue: $0) }.filter { seen.insert($0).inserted }
    }

    /// The derived **disabled pool**: every step not in `enabled`, in the universe's
    /// canonical (declaration) order — the Available section of the double-list.
    public static func pool<Step: CaptureStepKind>(enabled: [Step]) -> [Step] {
        let active = Set(enabled)
        return Array(Step.allCases).filter { !active.contains($0) }
    }
}

/// The reorderable steps a **New Reminder** capture can collect after its pinned
/// Title (issue #145 follow-up). Enabled+ordered here, they become the breadcrumb
/// steps in that order; `.list` enabled means "ask each time", disabled routes to the
/// page's default-list choice.
public enum ReminderStep: String, CaseIterable, CaptureStepKind {
    case dueDate
    case notes
    case priority
    case list

    public var title: String {
        switch self {
        case .dueDate: return "Due Date"
        case .notes: return "Notes"
        case .priority: return "Priority"
        case .list: return "List"
        }
    }

    public var symbol: String {
        switch self {
        case .dueDate: return "calendar"
        case .notes: return "note.text"
        case .priority: return "exclamationmark"
        case .list: return "list.bullet"
        }
    }

    /// The first-run enabled plan — today's default flow: ask for a due date and the
    /// list (Notes and Priority ship off). Also what a fresh install seeds.
    public static let firstRun: [ReminderStep] = [.dueDate, .list]

    /// Seeds the plan from the retired per-setting toggles on upgrade (issue #69/#145):
    /// due-date on → the Due Date step; a list left at "ask each time" (the empty
    /// stored value) → the List step. Notes/Priority shipped off, so they start
    /// disabled. Order matches the old fixed order (Due Date before List). With the old
    /// defaults (ask-date on, list ask) this yields exactly `firstRun`, so first-run and
    /// migration are one path.
    public static func migrated(askDate: Bool, listAsksEachTime: Bool) -> [ReminderStep] {
        var steps: [ReminderStep] = []
        if askDate { steps.append(.dueDate) }
        if listAsksEachTime { steps.append(.list) }
        return steps
    }
}

/// The reorderable steps a **New Event** capture can collect after its pinned Title
/// (issue #145 follow-up). `.start` enabled collects a start date; disabled makes the
/// event all-day today. `.calendar` enabled means "ask each time", disabled routes to
/// the page's default-calendar choice.
public enum EventStep: String, CaseIterable, CaptureStepKind {
    case start
    case location
    case notes
    case calendar

    public var title: String {
        switch self {
        case .start: return "Start"
        case .location: return "Location"
        case .notes: return "Notes"
        case .calendar: return "Calendar"
        }
    }

    public var symbol: String {
        switch self {
        case .start: return "clock"
        case .location: return "mappin.and.ellipse"
        case .notes: return "note.text"
        case .calendar: return "calendar"
        }
    }

    /// The first-run enabled plan — today's default flow: collect a start and ask for
    /// the calendar (Location and Notes ship off). Also what a fresh install seeds.
    public static let firstRun: [EventStep] = [.start, .calendar]

    /// Seeds the plan from the retired per-setting values on upgrade (issue #69/#145):
    /// the start was always collected, so `.start` is always enabled; a calendar left
    /// at "ask each time" (the empty stored value) → the Calendar step. Location/Notes
    /// shipped off, so they start disabled.
    public static func migrated(calendarAsksEachTime: Bool) -> [EventStep] {
        var steps: [EventStep] = [.start]
        if calendarAsksEachTime { steps.append(.calendar) }
        return steps
    }
}
