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

    /// Moves the cursor back to a filled pill so the next commit re-edits it
    /// (CONTEXT.md → Argument: "tapping a filled pill re-edits it"). Out-of-range
    /// indices are ignored.
    public mutating func editPill(at index: Int) {
        guard pills.indices.contains(index) else { return }
        self.index = index
    }

    /// Backspace pressed on an empty input (CONTEXT.md → Argument): pops the last
    /// pill and returns to that step, or — with no pills left — `.abandoned`, the
    /// signal to clear the breadcrumb and return to normal search.
    public mutating func backspaceOnEmpty() -> CaptureStep {
        guard !pills.isEmpty else { return .abandoned }
        pills.removeLast()
        index = pills.count
        return .collecting
    }

    /// The current choice Argument's options filtered by `filter`, ranked
    /// best-first by the same `Matcher` the Result list uses (CONTEXT.md → Input
    /// method) — the app renders them in the reversed list so the best match sits
    /// nearest the thumb. An empty filter shows every option in its supplied order;
    /// outside a choice step there are no options.
    public func options(matching filter: String, layout: KeyboardLayout = .qwerty) -> [ChoiceOption] {
        guard case .choice(let options)? = current?.inputMethod else { return [] }

        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return options }

        return options
            .compactMap { option -> (option: ChoiceOption, score: Double)? in
                guard let score = Matcher.score(query: trimmed, candidate: option.label, layout: layout)
                else { return nil }
                return (option, score)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.option.label < $1.option.label }
            .map(\.option)
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
