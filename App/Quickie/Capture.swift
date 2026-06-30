import SwiftUI
import UIKit
import QuickieCore

// The app-side of a multi-step quick capture (issue #37): the generic engine that
// drives the pure `MultiStepAction` breadcrumb through just-in-time permission and
// the views that morph the bottom input per the current Argument's input method.
//
// Nothing here knows about reminders. A *kind* of capture (New Reminder today, New
// Event next) is supplied as a `Capture` recipe — what permission it needs, the
// Action it builds, how it performs its outcome, and the wording of its
// affordances. The model and views are written once against that recipe, so a new
// capture is a new `Capture` conformance plus its Core Action, with no new pixels
// or animations. All capture *logic* is the Core engine and is unit-tested there;
// this layer is the pixels and the platform edge.

// MARK: - Capture recipe

/// A kind of quick capture, as the small set of decisions that differ between one
/// capture and the next (CONTEXT.md → Quick capture). The generic `CaptureModel`
/// and views are driven entirely through this, so adding "New Event" is a new
/// conformance — not a new screen.
///
/// `Sendable` so the model can carry it across the `Task`s that resolve permission
/// and perform the outcome.
protocol Capture: Sendable {
    /// The just-in-time access state, checked the instant the capture is activated
    /// and before any data entry (ADR 0012). A capture with no permission
    /// requirement (a Quickie-stored Note) is always `.ready`.
    var access: CaptureAccess { get }

    /// Requests access just-in-time after the user accepts the primer; returns
    /// whether it was granted. Never reached when `access` is `.ready` or `.denied`.
    func requestAccess() async -> Bool

    /// Builds the configured Core Action to drive, resolving any dynamic option
    /// sets (e.g. the user's reminder lists) once access is granted.
    func makeAction() async -> Action

    /// Performs a completed outcome at the platform edge and returns the
    /// confirmation to flash — the same defer-to-the-edge boundary as the rest of
    /// the app (the Core never touches EventKit or the pasteboard).
    func perform(_ outcome: ActionOutcome) async -> CaptureConfirmation

    /// The wording for the primer and denial affordances, so the generic bar can
    /// render them without knowing which permission it is gating.
    var copy: CaptureCopy { get }
}

/// What a capture needs before data entry can begin — its just-in-time permission
/// gate (ADR 0012). `.ready` proceeds straight to building the Action; `.needsPrimer`
/// shows the one-line primer first (so an uninformed denial isn't wasted); `.denied`
/// shows the inline "Enable in Settings" affordance.
enum CaptureAccess: Equatable, Sendable {
    case ready
    case needsPrimer
    case denied
}

/// The wording a capture supplies for its permission affordances (ADR 0012) — the
/// only capture-specific text the generic bar shows.
struct CaptureCopy: Equatable, Sendable {
    var primerIcon: String = "checklist"
    var primerText: String = ""
    var deniedIcon: String = "lock.fill"
    var deniedText: String = ""
}

/// A user-facing confirmation a capture reports once it has performed its outcome
/// (issue #37): a message to flash, an optional deep link to the created record
/// (so the toast can tap through to it), and whether it was a failure (the
/// error/success haptic). `isError` is explicit rather than inferred from a missing
/// link, so a capture that succeeds without one still reads as success.
struct CaptureConfirmation: Equatable {
    let id = UUID()
    let message: String
    var openURL: URL?
    var isError = false
}

// MARK: - Capture model

/// Drives one multi-step capture: resolves the supplied `Capture`'s permission
/// just-in-time, builds its Action, steps the pure `MultiStepAction` engine, and
/// hands the completed outcome back to the recipe to perform. Holds the per-step
/// input state (typed text, picked date) the morphing controls bind to.
@MainActor
@Observable
final class CaptureModel {
    /// The live breadcrumb session, or `nil` when not capturing.
    private(set) var session: MultiStepAction?
    /// Set when permission was refused: the bar becomes an inline "Enable in
    /// Settings" affordance and the capture does not proceed (ADR 0012).
    private(set) var denied = false
    /// Set when access is undetermined: a one-line primer shows before the system
    /// permission dialog, so an uninformed denial isn't wasted (ADR 0012).
    private(set) var priming = false
    /// The active capture recipe — the source of permission, the Action, and the
    /// outcome performer for the in-flight session.
    private var capture: (any Capture)?

    /// The active keyboard layout, so a choice step's fuzzy matching weights
    /// adjacent-key typos for the user's real layout — consistent with the Result
    /// list (the Core defaults to QWERTY when this isn't threaded through).
    private var layout: KeyboardLayout = .qwerty

    /// The current text/choice step's typed text.
    var stepText = ""
    /// The current date step's picked values.
    var pickedDate = Date()
    var includeTime = false

    /// A user-facing confirmation to flash once a capture completes; carries a
    /// fresh id so repeats still register as a change.
    private(set) var confirmation: CaptureConfirmation?

    /// Whether a capture is in progress (the center area shows its control).
    var isCapturing: Bool { session != nil }
    /// Whether the capture owns the bottom region — an active session, the primer,
    /// or the denial affordance — so the launcher swaps its normal input for it.
    var isActive: Bool { session != nil || denied || priming }

    var actionTitle: String { session?.actionTitle ?? "" }
    var pills: [ArgumentValue] { session?.pills ?? [] }
    /// Every breadcrumb step, shown from the start (issue #37): the top bar renders
    /// each as a glass crumb with its value or label and highlights the current one.
    var steps: [BreadcrumbStep] { session?.steps ?? [] }
    var currentArgument: Argument? { session?.current }
    /// The Return-key label for the current step — `.done` on the final Argument
    /// (the auto-create), `.next` otherwise.
    var returnKey: UIReturnKeyType { (session?.isFinalStep ?? false) ? .done : .next }
    /// The current capture's affordance wording, for the primer/denial bars.
    var copy: CaptureCopy { capture?.copy ?? CaptureCopy() }

    /// Begins a capture (CONTEXT.md → Quick capture): resolves the recipe's
    /// permission *before* any data entry (ADR 0012). Already-granted starts the
    /// session straight away; already-refused shows the inline affordance; an
    /// undetermined status shows a one-line primer first, then `confirmPrimer`
    /// triggers the system dialog.
    func start(_ capture: any Capture, layout: KeyboardLayout) {
        self.capture = capture
        self.layout = layout
        denied = false
        priming = false
        switch capture.access {
        case .ready:
            Task { await beginSession() }
        case .denied:
            denied = true
        case .needsPrimer:
            priming = true
        }
    }

    /// The user accepted the primer: request access just-in-time, then start the
    /// session on grant or fall back to the inline affordance on refusal.
    func confirmPrimer() async {
        priming = false
        guard let capture else { return }
        guard await capture.requestAccess() else {
            denied = true
            return
        }
        await beginSession()
    }

    /// Abandons the capture and returns to normal search.
    func cancel() {
        session = nil
        denied = false
        priming = false
        resetInputs()
    }

    private func beginSession() async {
        guard let capture else { return }
        let action = await capture.makeAction()
        resetInputs()
        session = MultiStepAction(action: action)
    }

    /// The current choice step's options, fuzzy-filtered by the typed text and
    /// ranked best-first (the app renders them reversed, best nearest the thumb),
    /// weighting typos for the active keyboard layout.
    func choiceOptions() -> [ChoiceOption] {
        session?.options(matching: stepText, layout: layout) ?? []
    }

    /// Commits the current text step; ignores an empty value.
    func commitText() {
        let trimmed = stepText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apply { $0.commit(.text(trimmed)) }
    }

    /// Commits the current date step with whether a time was included (the alarm
    /// signal).
    func commitDate() {
        apply { $0.commit(.date(pickedDate, hasTime: includeTime)) }
    }

    /// Commits a chosen option for the current choice step.
    func commitChoice(_ option: ChoiceOption) {
        apply { $0.commit(.choice(option)) }
    }

    /// Enter on a choice step commits the best (highlighted) option.
    func commitHighlightedChoice() {
        guard let best = choiceOptions().first else { return }
        commitChoice(best)
    }

    /// Backspace on an empty input pops the last pill, or abandons to search when
    /// there are none left.
    func backspaceOnEmpty() {
        apply { $0.backspaceOnEmpty() }
    }

    /// Tapping a filled pill re-edits it: the cursor moves back and the input is
    /// seeded with the pill's current value.
    func editPill(at index: Int) {
        guard var session, session.pills.indices.contains(index) else { return }
        let existing = session.pills[index]
        session.editPill(at: index)
        self.session = session
        switch existing {
        case .text(let text): stepText = text
        case .choice(let option): stepText = option.label
        case .date(let date, let hasTime):
            pickedDate = date
            includeTime = hasTime
            stepText = ""
        }
    }

    /// Runs a breadcrumb transition and reacts to its result: keep collecting,
    /// finish (perform the outcome + confirm), or abandon back to search.
    private func apply(_ transition: (inout MultiStepAction) -> CaptureStep) {
        guard var session else { return }
        let step = transition(&session)
        self.session = session

        switch step {
        case .collecting:
            resetInputs()
        case .completed(let outcome):
            // Grab the recipe before `cancel` clears the session: the outcome is
            // performed by the capture that produced it, even though the UI has
            // already returned to search.
            let capture = self.capture
            cancel()
            if let capture {
                Task { confirmation = await capture.perform(outcome) }
            }
        case .abandoned:
            cancel()
        }
    }

    private func resetInputs() {
        stepText = ""
        pickedDate = Date()
        includeTime = false
    }
}

// MARK: - Pill display

/// The breadcrumb text for a committed value (CONTEXT.md → Argument): the raw
/// text, the chosen option's label, or a formatted date (with the time only when
/// the user included one).
private func pillText(_ value: ArgumentValue) -> String {
    switch value {
    case .text(let text):
        return text
    case .choice(let option):
        return option.label
    case .date(let date, let hasTime):
        return date.formatted(
            hasTime
                ? .dateTime.month().day().hour().minute()
                : .dateTime.month().day()
        )
    }
}

// MARK: - Center content (the morphing control)

/// The center area during a capture: the in-place control for the current step —
/// a fuzzy choice list or a graphical date picker. Text steps show nothing here;
/// their control is the keyboard at the bottom.
struct CaptureContent: View {
    @Bindable var model: CaptureModel

    var body: some View {
        Group {
            switch model.currentArgument?.inputMethod {
            case .choice:
                ChoiceList(model: model)
            case .datePicker:
                DateStep(model: model)
            default:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The reversed, fuzzy-filtered option list for a choice step — the same reversed
/// Result-list shape, best match nearest the thumb (CONTEXT.md → Input method).
private struct ChoiceList: View {
    @Bindable var model: CaptureModel

    var body: some View {
        let options = model.choiceOptions()
        let bestID = options.first?.id
        ScrollView {
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 6) {
                    ForEach(options.reversed()) { option in
                        Button {
                            model.commitChoice(option)
                        } label: {
                            ChoiceRow(label: option.label, isHighlighted: option.id == bestID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("choice-\(option.id)")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .defaultScrollAnchor(.bottom)
    }
}

/// One option row, mirroring `ActionRow`'s highlighted treatment so the best
/// match reads as the default.
private struct ChoiceRow: View {
    let label: String
    var isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .foregroundStyle(.secondary)
            Text(label)
                .font(.body)
            Spacer(minLength: 8)
            if isHighlighted {
                Image(systemName: "return")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay {
            if isHighlighted {
                Capsule()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay { Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1) }
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .contentShape(Capsule())
    }
}

/// The in-place graphical date picker for a date step (ADR 0013), with a time
/// toggle that decides whether a timed value carries an alarm.
private struct DateStep: View {
    @Bindable var model: CaptureModel

    /// The settled height of the month grid, pinned with a hard constraint so the
    /// picker can never use its unstable taller intrinsic height. Date-only is just
    /// the calendar (constant across 5- and 6-row months); date+time adds the inline
    /// time row beneath it, so that mode needs the extra band.
    private static let dateHeight: CGFloat = 350
    private static let dateTimeHeight: CGFloat = 400

    private var pickerHeight: CGFloat { model.includeTime ? Self.dateTimeHeight : Self.dateHeight }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                // A `UIDatePicker` pinned to a fixed height rather than SwiftUI's
                // `DatePicker(.graphical)`. The SwiftUI picker over-reports its
                // height until its first selection change, so the calendar rows
                // visibly shrank the first time you tapped a day — and any later
                // relayout (the capture's slide-in settling) could bounce it back,
                // making it jump again on a subsequent tap. A hard UIKit height
                // constraint forces the settled layout from the first frame, so the
                // grid never moves. The height steps up when a time is included (an
                // explicit toggle, so its resize reads as intentional).
                InlineDatePicker(
                    date: $model.pickedDate,
                    includeTime: model.includeTime,
                    height: pickerHeight
                )
                .frame(height: pickerHeight)

                Toggle("Include a time", isOn: $model.includeTime)
                    .font(.subheadline)
                    .padding(.horizontal, 4)
            }
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

/// The in-place month-grid date picker, a `UIDatePicker` in `.inline` style with a
/// hard height constraint (CONTEXT.md → Input method). SwiftUI's
/// `DatePicker(.graphical)` over-reports its `intrinsicContentSize` until its first
/// selection change, so its calendar rows visibly tightened the first time you
/// tapped a day; pinning a `UIDatePicker` to its settled height with a required
/// constraint forces that layout from the start, so the grid never jumps. The
/// pinned height tracks the mode — date-only vs the taller date+time — and the
/// constraint is updated in place when it changes.
private struct InlineDatePicker: UIViewRepresentable {
    @Binding var date: Date
    var includeTime: Bool
    /// The fixed height to pin the picker to — its settled height for the current
    /// mode (date-only, or the taller date+time with its inline time row).
    var height: CGFloat

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .inline
        picker.datePickerMode = includeTime ? .dateAndTime : .date
        picker.date = date
        picker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.changed(_:)),
            for: .valueChanged
        )
        // The hard constraint that overrides the unstable intrinsic height; its
        // constant is updated in `updateUIView` when the mode (and so the height)
        // changes.
        let pinned = picker.heightAnchor.constraint(equalToConstant: height)
        pinned.priority = .required
        pinned.isActive = true
        context.coordinator.heightConstraint = pinned
        picker.setContentHuggingPriority(.required, for: .vertical)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        let mode: UIDatePicker.Mode = includeTime ? .dateAndTime : .date
        if picker.datePickerMode != mode { picker.datePickerMode = mode }
        if picker.date != date { picker.date = date }
        if context.coordinator.heightConstraint?.constant != height {
            context.coordinator.heightConstraint?.constant = height
        }
        context.coordinator.onChange = { date = $0 }
    }

    func makeCoordinator() -> Coordinator { Coordinator { date = $0 } }

    final class Coordinator: NSObject {
        var onChange: (Date) -> Void
        var heightConstraint: NSLayoutConstraint?
        init(_ onChange: @escaping (Date) -> Void) { self.onChange = onChange }
        @objc func changed(_ picker: UIDatePicker) { onChange(picker.date) }
    }
}

// MARK: - Bottom capture bar (the morph control)

/// The bottom region while capturing: the control for the current step — the
/// keyboard for text/choice, a commit button for the date, or the inline "Enable
/// in Settings" affordance on denial. The breadcrumb itself rides up top
/// (`CaptureBreadcrumbBar`), so this bar is purely the morphing input.
struct CaptureBar: View {
    @Bindable var model: CaptureModel

    var body: some View {
        control
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private var control: some View {
        if model.priming {
            PrimerAffordance(
                copy: model.copy,
                onContinue: { Task { await model.confirmPrimer() } },
                onCancel: { model.cancel() }
            )
        } else if model.denied {
            DeniedAffordance(copy: model.copy, onDismiss: { model.cancel() })
        } else {
            switch model.currentArgument?.inputMethod {
            case .datePicker:
                Button {
                    model.commitDate()
                } label: {
                    // The current Argument names the date it is collecting ("Due
                    // Date", "Start"), so the commit label reads right for any
                    // capture without the bar knowing which one it is.
                    Label("Set \(model.currentArgument?.label ?? "date")", systemImage: "calendar.badge.plus")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .frame(height: InputBar.barHeight)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("capture-set-date")
            default:
                BackspaceTextField(
                    text: $model.stepText,
                    placeholder: model.currentArgument?.label ?? "",
                    returnKey: model.returnKey,
                    onSubmit: submitText,
                    onBackspaceWhenEmpty: { model.backspaceOnEmpty() }
                )
                .padding(.horizontal, 20)
                .frame(height: InputBar.barHeight)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
    }

    /// Enter on a text step commits the typed text; on a choice step it commits
    /// the best-matching option (the highlighted row).
    private func submitText() {
        if case .choice = model.currentArgument?.inputMethod {
            model.commitHighlightedChoice()
        } else {
            model.commitText()
        }
    }
}

// MARK: - Top breadcrumb bar

/// The breadcrumb that rides the top of the screen while capturing: the Action
/// name above a full-width row of glass crumbs — one per step, all shown from the
/// start. Its background is a progressive blur that fades downward, so the content
/// (the choice list / date picker) slides under it.
struct CaptureBreadcrumbBar: View {
    @Bindable var model: CaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.actionTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                CancelButton { model.cancel() }
            }
            BreadcrumbSteps(model: model)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        // Span the status bar as one cohesive frame so the bar slides in and out
        // as a single block; bleeding only the background left the status-bar band
        // anchored behind during the slide, reading as a half-clip (`statusBarBleed`).
        .statusBarBleed(topPadding: 6) { ProgressiveBlur() }
    }
}

/// The × that abandons the whole capture and returns to the main search input
/// (issue #37): the single get-me-out affordance for an in-flight session, where
/// backspace only pops one pill at a time. A glass circle that mirrors the
/// paste button's footprint so the top chrome reads as one Liquid Glass family.
private struct CancelButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Cancel")
        .accessibilityIdentifier("capture-cancel")
    }
}

/// The scrolling flex row of step crumbs. Each step takes an equal share of the
/// width — the current one a little more — and the whole row scrolls once that
/// share would dip below `minStepWidth`, so every crumb stays legible no matter
/// how many steps an Action declares.
private struct BreadcrumbSteps: View {
    @Bindable var model: CaptureModel
    /// Honour the system Reduce Motion setting (ADR 0010 motion budget): the width
    /// change between steps snaps instead of gliding.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Measured width of the scroll viewport, which the equal-share maths divides up.
    @State private var containerWidth: CGFloat = 0

    private let rowSpacing: CGFloat = 6
    private let chevronWidth: CGFloat = 12
    private let minStepWidth: CGFloat = 92
    /// The current crumb's share, weighted a touch above the others so it reads as
    /// selected without dominating.
    private let currentWeight: CGFloat = 1.35

    var body: some View {
        let steps = model.steps
        ScrollView(.horizontal, showsIndicators: false) {
            // No GlassEffectContainer: its fluid morph resizes the glass on its
            // own slower curve, so the step width visibly lagged the chevron (which
            // is plain layout). Standalone glass redraws at its frame each tick, so
            // the width tracks the chevron exactly.
            HStack(spacing: rowSpacing) {
                ForEach(steps) { step in
                    let display = displayValue(for: step)
                    StepCrumb(
                        step: step,
                        width: width(for: step, in: steps),
                        displayText: display.text,
                        isPlaceholder: display.isPlaceholder,
                        onEdit: { model.editPill(at: step.index) }
                    )
                    if step.index < steps.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: chevronWidth)
                    }
                }
            }
            // Breathing room around the crumbs so their glass shadows have space to
            // fall rather than crowding the title above and the content below.
            .padding(.vertical, 10)
            // Glide the crumbs between their old and new widths as the cursor
            // advances (degraded to no animation under Reduce Motion).
            .animation(reduceMotion ? nil : .snappy, value: steps)
        }
        // A ScrollView clips to its viewport, which sheared off the crumbs' glass
        // shadows (most visibly along the bottom edge). The steps fit without
        // scrolling in practice, so disabling the clip lets the shadows render in
        // full; only a genuine overflow would scroll, and then off-screen crumbs
        // simply aren't clipped — an acceptable trade for un-clipped shadows.
        .scrollClipDisabled()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
    }

    /// What a crumb shows: the **live** input for the current step — the typed
    /// text, the picked date, or the choice Enter would commit, updating as the
    /// user works — the committed value for a sealed step, or a placeholder dash
    /// while a later step waits its turn.
    private func displayValue(for step: BreadcrumbStep) -> (text: String, isPlaceholder: Bool) {
        if step.isCurrent {
            switch model.currentArgument?.inputMethod {
            case .datePicker:
                // A date always has a value (defaults to now), so it shows straight
                // away and changes live as the picker moves.
                return (pillText(.date(model.pickedDate, hasTime: model.includeTime)), false)
            case .choice:
                // Preview the option Enter will commit — the best (highlighted)
                // match — rather than the raw filter text, so the crumb always
                // reads as the value about to be sealed. Empty only when nothing
                // matches the filter.
                if let best = model.choiceOptions().first {
                    return (best.label, false)
                }
                return ("—", true)
            default:
                let typed = model.stepText.trimmingCharacters(in: .whitespacesAndNewlines)
                return typed.isEmpty ? ("—", true) : (typed, false)
            }
        }
        if let value = step.value {
            return (pillText(value), false)
        }
        return ("—", true)
    }

    /// Each step's width. When the steps fit, every crumb gets its weighted share
    /// of the space left after the chevrons — equal, but the current one a little
    /// wider — so the shares sum to the full width and the row fills it edge to
    /// edge. Once that share would dip below `minStepWidth` (too many steps), every
    /// crumb falls back to its minimum and the row overflows into a scroll instead.
    private func width(for step: BreadcrumbStep, in steps: [BreadcrumbStep]) -> CGFloat {
        let weight = step.isCurrent ? currentWeight : 1
        guard containerWidth > 0, !steps.isEmpty else { return minStepWidth * weight }
        let chevrons = CGFloat(steps.count - 1) * (chevronWidth + rowSpacing * 2)
        let available = max(0, containerWidth - chevrons)
        let totalWeight = steps.reduce(CGFloat(0)) { $0 + ($1.isCurrent ? currentWeight : 1) }
        let unit = available / totalWeight
        // The narrowest crumb is a non-current one (weight 1); if even that clears
        // the floor the whole row fits, so honour the exact shares.
        return unit >= minStepWidth ? unit * weight : minStepWidth * weight
    }
}

/// One breadcrumb crumb: a Liquid Glass rounded rectangle showing the step's
/// label and its committed value (word-wrapped), highlighted when it is the
/// current step and tappable to re-edit once it carries a value.
private struct StepCrumb: View {
    let step: BreadcrumbStep
    let width: CGFloat
    /// The text to show — the live input, the committed value, or a placeholder.
    let displayText: String
    /// Whether `displayText` is a placeholder (dimmed) rather than a real value.
    let isPlaceholder: Bool
    var onEdit: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    /// The crumb's Liquid Glass. The current-step highlight *is* the glass tint —
    /// the accent crossfades out of the old crumb and into the new one as the
    /// cursor moves — rather than a separate layer. Filled crumbs are interactive
    /// so a tap to re-edit reads as pressable.
    private var glass: Glass {
        let base: Glass = step.isCurrent ? .regular.tint(.accentColor.opacity(0.4)) : .regular
        return step.value != nil ? base.interactive() : base
    }

    var body: some View {
        if step.value != nil {
            Button(action: onEdit) { content }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pill-\(step.index)")
        } else {
            content
                .accessibilityIdentifier("step-\(step.index)")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(step.label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(displayText)
                .font(.subheadline.weight(step.isCurrent ? .semibold : .regular))
                .foregroundStyle(isPlaceholder ? .tertiary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .glassEffect(glass, in: shape)
        .contentShape(shape)
    }
}

/// A material that fades from solid at the top to clear at the bottom — the
/// progressive blur the top breadcrumb floats on, so content reads through it
/// near the row and is cleanly blurred up under the status area.
private struct ProgressiveBlur: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// The one-line custom primer shown before the system permission dialog (ADR
/// 0012), so the dialog isn't wasted on an uninformed denial. Continue triggers
/// the system request; the × abandons back to search. Its wording is supplied by
/// the active capture so the same affordance serves any permission.
private struct PrimerAffordance: View {
    let copy: CaptureCopy
    var onContinue: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: copy.primerIcon)
                .foregroundStyle(.secondary)
            Text(copy.primerText)
                .font(.subheadline)
            Spacer(minLength: 8)
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: InputBar.barHeight)
        .glassEffect(.regular, in: Capsule())
        .accessibilityIdentifier("capture-permission-primer")
    }
}

/// The inline "Enable in Settings" affordance shown when access was refused (ADR
/// 0012): graceful degradation, never a nag — a tap opens Settings, the × returns
/// to search. Its wording is supplied by the active capture.
private struct DeniedAffordance: View {
    let copy: CaptureCopy
    var onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: copy.deniedIcon)
                .foregroundStyle(.secondary)
            Text(copy.deniedText)
                .font(.subheadline)
            Spacer(minLength: 8)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderless)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: InputBar.barHeight)
        .glassEffect(.regular, in: Capsule())
        .accessibilityIdentifier("capture-permission-denied")
    }
}
