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
    /// requirement (a Quickie-stored Pile entry) is always `.ready`.
    var access: CaptureAccess { get }

    /// Requests access just-in-time after the user accepts the primer; returns
    /// whether it was granted. Never reached when `access` is `.ready` or `.denied`.
    func requestAccess() async -> Bool

    /// Builds the configured Core Action to drive, resolving any dynamic option
    /// sets (e.g. the user's reminder lists) once access is granted.
    func makeAction() async -> Action

    /// Performs a completed outcome at the platform edge and returns the
    /// confirmation to flash — the same defer-to-the-edge boundary as the rest of
    /// the app (the Core never touches EventKit or the pasteboard). Returns `nil`
    /// when the outcome carries its own feedback and needs no toast — the New Event
    /// editor mode, whose handoff to the system event editor *is* the confirmation.
    func perform(_ outcome: ActionOutcome) async -> CaptureConfirmation?

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

    /// A value to **seed-and-commit** as Argument 1 the instant the session begins
    /// (CONTEXT.md → Fallback Action): a fallback selection commits the typed query
    /// through the normal engine, so a one-Argument fallback completes in one tap and
    /// a multi-Argument one continues at step 2 with pill 1 sealed. `nil` for a
    /// verb-first start (an empty breadcrumb) and for the permission-gated captures.
    private var seed: String?

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

    /// Bumped each time a capture **runs to completion** — the final-slot commit, or a
    /// one-tap seed-and-commit that finishes inside `beginSession`. Running a capture's
    /// outcome resolves the query like any main action (CONTEXT.md → Main action), so
    /// the launcher clears the input off this signal. `isActive` alone can't carry it:
    /// a one-slot fallback (web search) flips `isActive` true→false in a single tick, so
    /// its completion nets no observable `isActive` change — the input, and the Pending
    /// query Live Activity mirroring it, would otherwise linger past the run.
    private(set) var completions = 0

    /// Whether a capture is in progress (the center area shows its control).
    var isCapturing: Bool { session != nil }
    /// Whether the capture owns the bottom region — an active session, the primer,
    /// or the denial affordance — so the launcher swaps its normal input for it.
    var isActive: Bool { session != nil || denied || priming }
    /// Whether the capture's bottom control is **keyboard-less** — the date step's
    /// picker + commit button, or the primer/denial affordances. The keyboard
    /// hiding under one of these is *structural* (the control replaced the text
    /// field for the whole step), not the transient context-menu resignation the
    /// launcher's held inset guards against (issue #58) — so the launcher releases
    /// the inset and the control takes the keyboard's space, instead of floating a
    /// keyboard-height above a dead band.
    var usesKeyboardlessControl: Bool {
        if priming || denied { return true }
        return currentArgument?.inputMethod == .datePicker
    }

    var actionTitle: String { session?.actionTitle ?? "" }
    var pills: [ArgumentValue] { session?.pills ?? [] }
    /// Every breadcrumb step, shown from the start (issue #37): the top bar renders
    /// each as a glass crumb with its value or label and highlights the current one.
    var steps: [BreadcrumbStep] { session?.steps ?? [] }
    var currentArgument: Argument? { session?.current }
    /// The glyph each choice option row shows for the current step (issue #38): the
    /// step's declared `optionSymbol` — a calendar for an event's calendars, a bullet
    /// for a reminder's lists — falling back to a list bullet when it declares none.
    var choiceSymbol: String { currentArgument?.optionSymbol ?? "list.bullet" }
    /// The Return-key label for the current step — `.done` on the final Argument
    /// (the auto-create), `.next` otherwise.
    var returnKey: UIReturnKeyType { (session?.isFinalStep ?? false) ? .done : .next }
    /// The keyboard the current text step raises — the number pad for a `number`
    /// Argument's numeric keyboard variant, the default alphanumeric layout otherwise
    /// (issue #96). Only the keyboard input method reaches the text field, so any
    /// non-numeric variant (and the date/choice steps, which don't use this) map to
    /// the default layout.
    var keyboardType: UIKeyboardType {
        currentArgument?.inputMethod == .keyboard(.number) ? .numberPad : .default
    }
    /// Whether the current date step collects a **time**. A Custom Action's date slot
    /// fixes this from its format's meaning (issue #96); a reminder/event leaves it to
    /// the user's toggle (`includeTime`).
    var dateStepIncludesTime: Bool { currentArgument?.dateIncludesTime ?? includeTime }
    /// Whether the date step offers its "Include a time" toggle — only when the current
    /// date Argument leaves the choice to the user (the format hasn't fixed it).
    var dateStepAllowsTimeToggle: Bool { currentArgument?.dateIncludesTime == nil }
    /// The current capture's affordance wording, for the primer/denial bars.
    var copy: CaptureCopy { capture?.copy ?? CaptureCopy() }

    /// Begins a capture (CONTEXT.md → Quick capture): resolves the recipe's
    /// permission *before* any data entry (ADR 0012). Already-granted starts the
    /// session straight away; already-refused shows the inline affordance; an
    /// undetermined status shows a one-line primer first, then `confirmPrimer`
    /// triggers the system dialog.
    ///
    /// `seed`, when non-nil, is committed as Argument 1 the moment the session
    /// begins — the fallback seed-and-commit (CONTEXT.md → Fallback Action). A
    /// verb-first start passes `nil` and the breadcrumb opens empty.
    func start(_ capture: any Capture, layout: KeyboardLayout, seed: String? = nil) {
        self.capture = capture
        self.layout = layout
        self.seed = seed
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
        seed = nil
        resetInputs()
    }

    private func beginSession() async {
        guard let capture else { return }
        let action = await capture.makeAction()
        resetInputs()
        session = MultiStepAction(action: action)
        // Seed-and-commit (CONTEXT.md → Fallback Action): a fallback selection
        // commits the typed query as Argument 1 through the same engine. A
        // one-Argument fallback completes here at once (the outcome performs and the
        // session clears); a multi-Argument one continues at step 2 with the seeded
        // first pill sealed and re-editable like any other.
        if let seed {
            self.seed = nil
            apply { $0.commit(.text(seed.trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
    }

    /// The current choice step's options, fuzzy-filtered by the typed text and
    /// ranked best-first (the app renders them reversed, best nearest the thumb),
    /// weighting typos for the active keyboard layout.
    func choiceOptions() -> [ChoiceOption] {
        session?.options(matching: stepText, layout: layout) ?? []
    }

    /// Commits the current text step. A **required** step ignores an empty value so
    /// the user can't skip it; an **optional** step (a Shortcut Action's input, issue
    /// #46) may be committed empty — the Action still runs, so the breadcrumb never
    /// traps someone with nothing to type. The Core maps the empty value to "no input".
    func commitText() {
        let trimmed = stepText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || (currentArgument?.isOptional ?? false) else { return }
        apply { $0.commit(.text(trimmed)) }
    }

    /// Commits the current date step with whether a time was included (the alarm
    /// signal).
    func commitDate() {
        apply { $0.commit(.date(pickedDate, hasTime: dateStepIncludesTime)) }
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

    /// Commits the current step the way Enter would — the highlighted choice, the
    /// picked date, or the typed text — so the keyboard Return and a tap on the next
    /// empty crumb advance identically. A required text step's empty-guard means an
    /// empty current step stays put, so tapping ahead never commits nothing.
    func submitCurrent() {
        switch currentArgument?.inputMethod {
        case .choice: commitHighlightedChoice()
        case .datePicker: commitDate()
        default: commitText()
        }
    }

    /// Backspace on an empty input steps back onto the previous pill to **re-edit**
    /// it — the input seeds with its value so it is corrected, not retyped — or
    /// abandons to search when the cursor is already on the first step.
    func backspaceOnEmpty() {
        guard var session else { return }
        switch session.backspaceOnEmpty() {
        case .abandoned:
            cancel()
        case .collecting:
            self.session = session
            seedInput(from: session.currentValue)
        case .completed:
            break // backspace never completes a capture
        }
    }

    /// Tapping a filled pill re-edits it: the cursor moves back and the input is
    /// seeded with the pill's current value.
    func editPill(at index: Int) {
        guard var session, session.pills.indices.contains(index) else { return }
        session.editPill(at: index)
        self.session = session
        seedInput(from: session.currentValue)
    }

    /// Seeds the per-step input controls from a committed value — what the cursor
    /// lands on when re-editing a pill (tapped, or backspaced onto). `nil` (an
    /// unfilled step) resets the controls to empty.
    private func seedInput(from value: ArgumentValue?) {
        switch value {
        case .text(let text): stepText = text
        case .choice(let option): stepText = option.label
        case .date(let date, let hasTime):
            pickedDate = date
            includeTime = hasTime
            stepText = ""
        case nil:
            resetInputs()
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
            // A pill sealed and the cursor advanced to the next step: the selection
            // tick the feedback budget declares for mid-capture progress (ADR 0034).
            // Only the *collecting* commit ticks — a commit that completes the
            // capture falls to `.completed` below, whose beat is the run's confirmation
            // success/error, so the final step never ticks and buzzes at once (#180).
            Haptics.play(.breadcrumbStep)
            resetInputs()
        case .completed(let outcome):
            // Grab the recipe before `cancel` clears the session: the outcome is
            // performed by the capture that produced it, even though the UI has
            // already returned to search.
            let capture = self.capture
            cancel()
            // Signal the completed run so the launcher resolves the query (clear the
            // input, end the Live Activity). Bumped even for a one-tap completion that
            // never nets an `isActive` change — the whole reason `isActive` can't carry
            // this. Set after `cancel` so any `isActive` observer runs first.
            completions += 1
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
    /// The height of the breadcrumb bar overlaying the top (issue #37): the choice
    /// list insets its scroll content by this much so a long option set can scroll
    /// fully clear of the breadcrumb instead of stranding its top rows behind it.
    var topInset: CGFloat = 0

    var body: some View {
        Group {
            switch model.currentArgument?.inputMethod {
            case .choice:
                ChoiceList(model: model, topInset: topInset)
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
    /// Top scroll-content inset that clears the breadcrumb overlay (issue #37).
    var topInset: CGFloat = 0

    var body: some View {
        let options = model.choiceOptions()
        let bestID = options.first?.id
        let symbol = model.choiceSymbol
        ScrollView {
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 6) {
                    ForEach(options.reversed()) { option in
                        Button {
                            model.commitChoice(option)
                        } label: {
                            ChoiceRow(label: option.label, symbol: symbol, isHighlighted: option.id == bestID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("choice-\(option.id)")
                    }
                }
                .frame(maxWidth: .infinity)
                // A scrollable top spacer the height of the breadcrumb, so the earliest
                // options (the top of the reversed list) can scroll out from behind the
                // breadcrumb overlay. Plain content padding — not a scroll safe-area
                // inset — so the bottom options stay clear of the input bar and hittable.
                .padding(.top, topInset)
            }
        }
        .defaultScrollAnchor(.bottom)
    }
}

/// One option row, mirroring `ActionRow`'s highlighted treatment so the best
/// match reads as the default.
private struct ChoiceRow: View {
    let label: String
    /// The leading glyph, declared by the choice step (a calendar, a list bullet…).
    let symbol: String
    var isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
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

    /// The settled heights of the picker, pinned with a hard constraint so it can
    /// never use its unstable taller intrinsic height: the month grid alone
    /// (constant across 5- and 6-row months), plus the native inline time row's
    /// band when the step collects a time (`.dateAndTime`).
    private static let dateHeight: CGFloat = 350
    private static let dateTimeHeight: CGFloat = 400

    private var pickerHeight: CGFloat {
        model.dateStepIncludesTime ? Self.dateTimeHeight : Self.dateHeight
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                InlineDatePicker(
                    date: $model.pickedDate,
                    includesTime: model.dateStepIncludesTime,
                    height: pickerHeight
                )
                .frame(height: pickerHeight)

                // The toggle appears only when the step leaves the date/time choice to
                // the user (reminders/events). A Custom Action date slot fixes it from
                // its format, so the toggle is hidden — the time row is already pinned
                // on or off.
                if model.dateStepAllowsTimeToggle {
                    Toggle("Include a time", isOn: $model.includeTime)
                        .font(.subheadline)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("capture-include-time")
                }
            }
            .padding(16)
            // Deliberately outside `QuickieRadius`: this is a full-width panel
            // wrapping a month grid, not one of the three recurring surfaces that
            // scale documents, and a step with a single caller would be a token
            // pretending to be a rule. It rounds a little softer than a card
            // because it is a lot bigger than one.
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

/// The in-place month-grid date picker, a `UIDatePicker` in `.inline` style with
/// a hard height constraint (CONTEXT.md → Input method). SwiftUI's
/// `DatePicker(.graphical)` over-reports its `intrinsicContentSize` until its first
/// selection change, so its calendar rows visibly tightened the first time you
/// tapped a day; pinning a `UIDatePicker` to its settled height with a required
/// constraint forces that layout from the start, so the grid never jumps.
///
/// A timed step uses the native `.dateAndTime` mode — the calendar with the
/// picker's own inline time row beneath it. That mode was banned for most of
/// #113/#115 because a picker built fresh in it (the breadcrumb backspacing
/// onto a committed datetime pill, a Custom Action datetime slot entered
/// forward) laid out broken: a blank band above the calendar, the time row
/// squashed. The ban treated the mode as the culprit; the diagnosis below
/// exonerated it — the phantom inset broke *every* fresh timed layout, and
/// with the inset cancelled, fresh `.dateAndTime` creation and live
/// `.date` ↔ `.dateAndTime` switches both lay out clean (simulator-measured:
/// identical row pitch forward and on re-entry).
///
/// The picker hangs inside the root view of an `InsetCancellingController`,
/// which **zeroes the real safe area** UIKit propagates into the subtree — the
/// actual fix for the blank band + compacted rows (#115); see that class for
/// the full mechanism (SwiftUI's step transition parks the container's *frame*
/// near the window top and slides it in with a transform, so UIKit hands the
/// subtree a phantom top inset that the calendar's internals bake into their
/// first layout). Everything that lied about or dodged the inset from inside
/// was disproven on device — a zero safe-area override alone, internal scroll
/// views pinned to `.never` inset adjustment, deferring creation one runloop
/// turn, isolating the picker in its own glass card, and `UICalendarView` all
/// still rendered the band — because the *propagated* value stayed nonzero.
/// Cancelling it at the hosting controller is the one public lever that
/// changes the value itself. The container root additionally keeps SwiftUI's
/// direct frame writes off the picker, so its geometry comes only from its
/// own constraints.
private struct InlineDatePicker: UIViewRepresentable {
    @Binding var date: Date
    /// Whether the step collects a time — the picker shows its native inline
    /// time row beneath the calendar in `.dateAndTime` mode.
    var includesTime: Bool
    /// The fixed height to pin the picker to — the settled month grid, plus the
    /// native time row when the step collects one.
    var height: CGFloat

    func makeUIView(context: Context) -> UIView {
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .inline
        picker.datePickerMode = includesTime ? .dateAndTime : .date
        picker.date = date
        picker.accessibilityIdentifier = "capture-calendar"
        picker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.changed(_:)),
            for: .valueChanged
        )

        // The container is the root view of an `InsetCancellingController`,
        // which zeroes the *real* safe area UIKit propagates into this subtree
        // (see that class — SwiftUI's step transition hands the container a
        // phantom top inset that the calendar's internals bake into their
        // first layout).
        let host = InsetCancellingController()
        let container = host.view!
        container.backgroundColor = .clear
        container.addSubview(picker)
        picker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: container.topAnchor),
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        let heightConstraint = picker.heightAnchor.constraint(equalToConstant: height)
        heightConstraint.isActive = true
        context.coordinator.picker = picker
        context.coordinator.heightConstraint = heightConstraint
        context.coordinator.host = host
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let picker = context.coordinator.picker else { return }
        // Resize the box before switching the mode and commit the new bounds
        // with an explicit layout pass — defensive ordering so a mode switch's
        // content rebuild (a first layout, which this picker bakes in
        // permanently, #115) can never run against stale bounds. Note the
        // `.dateAndTime` grid is naturally TIGHTER than date-only's (~0.87× row
        // pitch) and top-aligns at natural size rather than filling the box —
        // that is the mode's design, not a squeeze; see the geometry test.
        if let constraint = context.coordinator.heightConstraint, constraint.constant != height {
            constraint.constant = height
            container.layoutIfNeeded()
        }
        let mode: UIDatePicker.Mode = includesTime ? .dateAndTime : .date
        if picker.datePickerMode != mode { picker.datePickerMode = mode }
        if picker.date != date { picker.date = date }
        context.coordinator.onChange = { date = $0 }
    }

    func makeCoordinator() -> Coordinator { Coordinator { date = $0 } }

    final class Coordinator: NSObject {
        var onChange: (Date) -> Void
        weak var picker: UIDatePicker?
        weak var heightConstraint: NSLayoutConstraint?
        /// Retains the inset-cancelling controller whose root view hosts the
        /// picker — the controller must outlive the view to keep cancelling.
        var host: UIViewController?
        init(_ onChange: @escaping (Date) -> Void) { self.onChange = onChange }
        @objc func changed(_ picker: UIDatePicker) { onChange(picker.date) }
    }
}

/// Zeroes the **real** safe area UIKit propagates into its view's subtree, by
/// continuously setting `additionalSafeAreaInsets` to the negative of whatever
/// the system imposes — the one public lever that changes the propagated value
/// rather than one view's getter.
///
/// Why this exists (#115): during the capture's step transitions SwiftUI
/// positions the date step's UIKit container using a frame near the window's
/// top plus a translation transform. UIKit computes safe areas from *frames*,
/// ignoring transforms, so the container inherits a phantom top inset
/// (measured at 41–46pt mid-transition in the simulator, while sitting
/// visually mid-screen) — and the inline calendar's internals bake whatever
/// inset they see at first layout into their grid permanently: the blank band
/// above the month header and the compacted rows. Overriding `safeAreaInsets`
/// on the picker itself only lies to callers of that one getter; the children
/// inherit the real value. Cancelling it at the hosting controller makes the
/// subtree's truth zero — correct always, since this control renders inside
/// the capture's chrome, clear of every screen edge.
private final class InsetCancellingController: UIViewController {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cancelInheritedSafeArea()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        cancelInheritedSafeArea()
    }

    private func cancelInheritedSafeArea() {
        // What the system imposes = what the view reports minus what we last
        // subtracted; converge by subtracting exactly that.
        let reported = view.safeAreaInsets
        let system = UIEdgeInsets(
            top: reported.top - additionalSafeAreaInsets.top,
            left: reported.left - additionalSafeAreaInsets.left,
            bottom: reported.bottom - additionalSafeAreaInsets.bottom,
            right: reported.right - additionalSafeAreaInsets.right
        )
        let cancelling = UIEdgeInsets(
            top: -system.top, left: -system.left, bottom: -system.bottom, right: -system.right
        )
        if additionalSafeAreaInsets != cancelling {
            additionalSafeAreaInsets = cancelling
        }
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
                    keyboardType: model.keyboardType,
                    onSubmit: submitText,
                    onBackspaceWhenEmpty: { model.backspaceOnEmpty() }
                )
                .padding(.horizontal, 20)
                .frame(height: InputBar.barHeight)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
    }

    /// Enter commits the current step — the typed text, or the best-matching option
    /// on a choice step — the same path a tap on the next empty crumb takes.
    private func submitText() {
        model.submitCurrent()
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
        // The step the cursor sits on — the crumb we keep in view. When many steps
        // overflow the viewport, we scroll it toward the centre; `anchor: .center`
        // clamps at the content edges on its own, so the first step stays pinned to
        // the left and the last to the right rather than the row over-scrolling past
        // them.
        let currentIndex = steps.first(where: \.isCurrent)?.index
        ScrollViewReader { proxy in
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
                            onTap: tapHandler(for: step, currentIndex: currentIndex)
                        )
                        // The scroll target for auto-centring the active crumb.
                        .id(step.index)
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
            // Follow the cursor: when the active step changes (advancing, backspacing,
            // or tapping a pill to re-edit) glide it toward the centre so a long
            // breadcrumb never strands the step you're filling off-screen to the
            // right. Degrades to a snap under Reduce Motion (ADR 0010 motion budget).
            .onChange(of: currentIndex) { _, index in
                guard let index else { return }
                withAnimation(reduceMotion ? nil : .snappy) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            // A capture can open already past step 1 — a multi-slot fallback seeds its
            // first pill and lands on step 2 — so centre the active step on appear too,
            // not only on later changes.
            .onAppear {
                guard let currentIndex else { return }
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    /// A crumb's tap action, or `nil` when it isn't tappable. A filled pill that
    /// isn't the current step **re-edits** it. The immediate next (empty) step
    /// **advances** — the same as pressing Enter (its empty-guard means an empty
    /// current step stays put, so tapping ahead never commits nothing). Every other
    /// crumb — the current one, or a not-yet-reached empty step further ahead — is
    /// inert.
    private func tapHandler(for step: BreadcrumbStep, currentIndex: Int?) -> (() -> Void)? {
        if step.value != nil && !step.isCurrent {
            return { model.editPill(at: step.index) }
        }
        if let currentIndex, step.value == nil, step.index == currentIndex + 1 {
            return { model.submitCurrent() }
        }
        return nil
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
                return (pillText(.date(model.pickedDate, hasTime: model.dateStepIncludesTime)), false)
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
/// current step and tappable when it can be re-edited (a filled pill) or advanced
/// to (the next empty step).
private struct StepCrumb: View {
    let step: BreadcrumbStep
    let width: CGFloat
    /// The text to show — the live input, the committed value, or a placeholder.
    let displayText: String
    /// Whether `displayText` is a placeholder (dimmed) rather than a real value.
    let isPlaceholder: Bool
    /// The tap action, or `nil` when this crumb isn't tappable — re-edit a filled
    /// pill, or advance from the next empty step (the same as Enter).
    let onTap: (() -> Void)?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous) }

    /// The crumb's Liquid Glass. The current-step highlight *is* the glass tint —
    /// the accent crossfades out of the old crumb and into the new one as the
    /// cursor moves — rather than a separate layer. Tappable crumbs are interactive
    /// so a tap (to re-edit or advance) reads as pressable.
    private var glass: Glass {
        let base: Glass = step.isCurrent ? .regular.tint(.accentColor.opacity(0.4)) : .regular
        return onTap != nil ? base.interactive() : base
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                // A filled pill keeps its `pill-N` identity; a tappable empty step
                // keeps `step-N` so the next-empty advance target is addressable too.
                .accessibilityIdentifier(step.value != nil ? "pill-\(step.index)" : "step-\(step.index)")
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
