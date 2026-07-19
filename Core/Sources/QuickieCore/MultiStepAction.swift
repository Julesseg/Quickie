import Foundation

/// The breadcrumb engine that drives a multi-step Action (CONTEXT.md → Argument;
/// issue #37) — the in-flight run of an Action with ordered, typed Arguments.
///
/// It collects one Argument at a time in the single bottom input: committing a
/// value seals it into a `pill` and advances; the final commit resolves to the
/// Action's outcome (the auto-create — no separate confirm step). The app drives
/// it from the input region and renders `actionTitle` + `pills` as the breadcrumb,
/// morphing the control to `current`'s input method. Pure and EventKit-free, so
/// the whole capture lifecycle is testable without UIKit.
public struct MultiStepAction {
    /// The active Action's name — the leading breadcrumb crumb (`[New Reminder] ▸`).
    public let actionTitle: String
    private let action: Action
    /// The values sealed so far, in Argument order — the filled breadcrumb pills.
    public private(set) var pills: [ArgumentValue]
    /// Index of the Argument currently being collected.
    private var index: Int

    public init(action: Action) {
        self.action = action
        self.actionTitle = action.title
        self.pills = []
        self.index = 0
    }

    /// The Argument currently being collected — what the input region morphs for —
    /// or `nil` once every Argument is filled.
    public var current: Argument? {
        index < action.arguments.count ? action.arguments[index] : nil
    }

    /// Whether the cursor sits on the last Argument, so the next commit completes
    /// the capture (the auto-create). The app reads this to label the Return key.
    public var isFinalStep: Bool {
        index == action.arguments.count - 1
    }

    /// Every step of the Action in order — the whole breadcrumb, all crumbs shown
    /// from the start (issue #37): each carries its `label`, its committed `value`
    /// (`nil` while still unfilled), and whether the cursor is currently collecting
    /// it. Re-editing keeps the later pills' values intact while moving `isCurrent`
    /// back to the tapped step.
    public var steps: [BreadcrumbStep] {
        action.arguments.enumerated().map { offset, argument in
            BreadcrumbStep(
                index: offset,
                label: argument.label,
                value: offset < pills.count ? pills[offset] : nil,
                isCurrent: offset == index
            )
        }
    }

    /// Seals `value` into the current Argument's pill and advances. Returns
    /// `.collecting` while Arguments remain, or `.completed` with the Action's
    /// outcome once the final Argument is filled — the auto-create, no confirm step.
    ///
    /// On a forward step the value is appended and the cursor advances; when
    /// re-editing an earlier pill (cursor sitting on a filled step) the value
    /// replaces that pill in place and the cursor resumes at the first unfilled
    /// step, leaving the later pills intact.
    public mutating func commit(_ value: ArgumentValue) -> CaptureStep {
        if index < pills.count {
            pills[index] = value
            index = pills.count
        } else {
            pills.append(value)
            index += 1
        }
        guard current != nil else {
            return .completed(action.run(arguments: pills))
        }
        return .collecting
    }

    /// The value already committed for the step under the cursor, or `nil` when
    /// that step is still unfilled. What the input region seeds with when the cursor
    /// lands on a filled pill to re-edit it — whether reached by tapping the pill or
    /// by backspacing back onto it — so the value is corrected, never retyped.
    public var currentValue: ArgumentValue? {
        index < pills.count ? pills[index] : nil
    }

    /// Moves the cursor back to a filled pill so the next commit re-edits it
    /// (CONTEXT.md → Argument: "tapping a filled pill re-edits it"). Out-of-range
    /// indices are ignored.
    public mutating func editPill(at index: Int) {
        guard pills.indices.contains(index) else { return }
        self.index = index
    }

    /// Backspace pressed on an empty input (CONTEXT.md → Argument): steps the cursor
    /// back onto the previous pill to **re-edit** it, keeping its value (read via
    /// `currentValue`) so it is corrected rather than cleared. Returns `.collecting`
    /// after stepping back, or — already on the first step, with nothing earlier —
    /// `.abandoned`, the signal to clear the breadcrumb and return to normal search.
    public mutating func backspaceOnEmpty() -> CaptureStep {
        guard index > 0 else { return .abandoned }
        index -= 1
        return .collecting
    }

    /// The current choice Argument's options filtered by `filter`, each paired with
    /// its **Match highlight** (issue #195) and ranked best-first by the same
    /// `Matcher` the Result list uses (CONTEXT.md → Input method, Match highlight) —
    /// the app renders them in the reversed list so the best match sits nearest the
    /// thumb, bolding the matched letters of each label. An empty filter shows every
    /// option in its supplied order with no highlight (nothing was matched); outside
    /// a choice step there are no options. The highlight is computed only for the
    /// options actually returned, mirroring the Result list's rows.
    public func matchedOptions(matching filter: String, layout: KeyboardLayout = .qwerty) -> [ChoiceMatch] {
        guard case .choice(let options)? = current?.inputMethod else { return [] }

        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return options.map { ChoiceMatch(option: $0, match: nil) } }

        return options
            .compactMap { option -> (option: ChoiceOption, score: Double)? in
                guard let score = Matcher.score(query: trimmed, candidate: option.label, layout: layout)
                else { return nil }
                return (option, score)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.option.label < $1.option.label }
            .map {
                ChoiceMatch(
                    option: $0.option,
                    match: MatchHighlight.titleMatch(query: trimmed, title: $0.option.label, layout: layout)
                )
            }
    }

    /// The filtered choice options without their highlights — the `option`-only
    /// projection of `matchedOptions(matching:layout:)`, for callers keying off id or
    /// order alone, so the two can't drift.
    public func options(matching filter: String, layout: KeyboardLayout = .qwerty) -> [ChoiceOption] {
        matchedOptions(matching: filter, layout: layout).map(\.option)
    }
}

/// One crumb in the breadcrumb as the UI renders it (issue #37): an Argument
/// shown from the start, carrying its committed `value` (`nil` until collected)
/// and whether the input is currently collecting it. The reusable view-model the
/// app maps to a glass crumb, so the pixels never reach into the engine's order.
public struct BreadcrumbStep: Identifiable, Equatable, Sendable {
    /// The Argument's position, and the crumb's stable identity.
    public let index: Int
    /// The Argument's display label — the crumb's caption / placeholder prompt.
    public let label: String
    /// The committed value, or `nil` while this step is still unfilled.
    public let value: ArgumentValue?
    /// Whether the cursor currently sits on this step (the highlighted crumb).
    public let isCurrent: Bool

    public var id: Int { index }

    public init(index: Int, label: String, value: ArgumentValue?, isCurrent: Bool) {
        self.index = index
        self.label = label
        self.value = value
        self.isCurrent = isCurrent
    }
}

/// What a breadcrumb transition produced (issue #37): the capture is still
/// `collecting` the next Argument, has `completed` with the Action's outcome (the
/// final-commit auto-create), or was `abandoned` back to normal search.
public enum CaptureStep: Equatable, Sendable {
    case collecting
    case completed(ActionOutcome)
    case abandoned
}
