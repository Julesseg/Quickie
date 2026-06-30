import SwiftUI
import UIKit
import QuickieCore

// The app-side of the New Reminder quick capture (issue #37): the settings that
// gate its steps, the model that drives the pure `MultiStepAction` breadcrumb
// engine through just-in-time EventKit permission, and the views that morph the
// bottom input per the current Argument's input method. All capture *logic* is
// the Core engine and is unit-tested there; this layer is the pixels and the
// EventKit edge.

// MARK: - Settings

/// The New Reminder settings, read from `@AppStorage` with working defaults (ADR
/// 0012) so the capture is fully functional before any Settings UI exists. The
/// Settings → Actions registry that will host these lives elsewhere.
struct ReminderSettings {
    static let askDateKey = "reminder.askDate"
    static let askListKey = "reminder.askList"
    static let defaultListIDKey = "reminder.defaultListID"

    /// Ask for a due date (default ON); OFF skips the date step.
    var askDate: Bool = true
    /// Ask for the target list every capture (default ON → the list is the third
    /// breadcrumb step, fuzzy-found over the user's lists); OFF routes silently to
    /// `defaultListID` (empty → the system default reminders list).
    var askList: Bool = true
    /// The preset list's identifier; empty means the system default reminders list.
    var defaultListID: String = ""

    /// How the list step is routed (CONTEXT.md → Reminder): ask every capture, or
    /// a fixed default list — an empty id being the system default.
    var listSelection: ReminderListSelection {
        askList ? .ask : .fixed(id: defaultListID.isEmpty ? nil : defaultListID)
    }
}

// MARK: - Capture model

/// Drives one New Reminder capture: requests EventKit permission just-in-time,
/// builds the configured Action from the user's lists + settings, and steps the
/// pure `MultiStepAction` engine, performing the resulting `ReminderDraft` against
/// EventKit on completion.
@MainActor
@Observable
final class ReminderCaptureModel {
    /// The live breadcrumb session, or `nil` when not capturing.
    private(set) var session: MultiStepAction?
    /// Set when permission was refused: the Action becomes an inline "Enable in
    /// Settings" affordance and the capture does not proceed (ADR 0012).
    private(set) var denied = false
    /// Set when access is undetermined: a one-line custom primer shows before the
    /// system permission dialog, so an uninformed denial isn't wasted (ADR 0012).
    private(set) var priming = false
    private var pendingSettings: ReminderSettings?

    /// The active keyboard layout, so the list step's fuzzy matching weights
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
    private(set) var confirmation: Confirmation?

    private let service = RemindersService()

    struct Confirmation: Equatable {
        let id = UUID()
        let message: String
        /// A deep link to the created reminder, so the toast can tap through to it
        /// in the Reminders app; `nil` on failure (nothing to open).
        var openURL: URL?
    }

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

    /// Begins the capture (CONTEXT.md → Reminder): resolves permission *before*
    /// any data entry (ADR 0012). Already-granted starts the session straight away;
    /// already-refused shows the inline affordance; an undetermined status shows a
    /// one-line primer first, then `confirmPrimer` triggers the system dialog.
    func start(settings: ReminderSettings, layout: KeyboardLayout) {
        denied = false
        priming = false
        self.layout = layout
        if service.isDenied {
            denied = true
        } else if service.isAuthorized {
            Task { await beginSession(settings: settings) }
        } else {
            pendingSettings = settings
            priming = true
        }
    }

    /// The user accepted the primer: request access just-in-time, then start the
    /// session on grant or fall back to the inline affordance on refusal.
    func confirmPrimer() async {
        priming = false
        guard let settings = pendingSettings else { return }
        pendingSettings = nil
        guard await service.requestAccess() else {
            denied = true
            return
        }
        await beginSession(settings: settings)
    }

    /// Abandons the capture and returns to normal search.
    func cancel() {
        session = nil
        denied = false
        priming = false
        pendingSettings = nil
        resetInputs()
    }

    private func beginSession(settings: ReminderSettings) async {
        let lists = await service.reminderLists()
        let action = Action.newReminder(
            askDate: settings.askDate,
            list: settings.listSelection,
            lists: lists
        )
        resetInputs()
        session = MultiStepAction(action: action)
    }

    /// The current choice step's options, fuzzy-filtered by the typed text and
    /// ranked best-first (the app renders them reversed, best nearest the thumb),
    /// weighting typos for the active keyboard layout.
    func choiceOptions() -> [ChoiceOption] {
        session?.options(matching: stepText, layout: layout) ?? []
    }

    /// Commits the current text step; ignores an empty title.
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
            cancel()
            Task { await perform(outcome) }
        case .abandoned:
            cancel()
        }
    }

    private func perform(_ outcome: ActionOutcome) async {
        guard case .createReminder(let draft) = outcome else { return }
        do {
            let link = try await service.create(draft)
            confirmation = Confirmation(message: "Reminder added", openURL: link)
        } catch {
            confirmation = Confirmation(message: "Couldn't add reminder")
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
struct ReminderCaptureContent: View {
    @Bindable var model: ReminderCaptureModel

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
    @Bindable var model: ReminderCaptureModel

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
/// toggle that decides whether the reminder gets an alarm.
private struct DateStep: View {
    @Bindable var model: ReminderCaptureModel

    /// The settled height of the graphical month grid (measured the same in
    /// date-only and date+time modes), pinned so the picker can't shrink on the
    /// first tap.
    private static let calendarHeight: CGFloat = 350

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                DatePicker(
                    "Due date",
                    selection: $model.pickedDate,
                    displayedComponents: model.includeTime ? [.date, .hourAndMinute] : [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                // Pin the month grid to its settled height. Left to size itself the
                // graphical picker over-estimates its height on first layout and then
                // snaps ~25pt shorter the first time you tap a day — the calendar
                // "lines" visibly shrinking. A fixed height keeps the surrounding card
                // and the commit button from moving; the no-op re-publish below makes
                // the grid itself commit that compact layout up front.
                .frame(height: Self.calendarHeight)
                .onAppear {
                    // The graphical picker reports a too-tall `intrinsicContentSize`
                    // until its first selection *change*, so the calendar rows visibly
                    // tighten the first time you tap a day. Nudge the selection by a
                    // single second on the next runloop: that counts as a change and
                    // triggers the relayout up front, yet keeps the same calendar day
                    // and the same date-only breadcrumb, so nothing visibly moves.
                    DispatchQueue.main.async {
                        model.pickedDate = model.pickedDate.addingTimeInterval(1)
                    }
                }

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

// MARK: - Bottom capture bar (the morph control)

/// The bottom region while capturing: the control for the current step — the
/// keyboard for text/choice, a commit button for the date, or the inline "Enable
/// in Settings" affordance on denial. The breadcrumb itself rides up top now
/// (`ReminderBreadcrumbBar`), so this bar is purely the morphing input.
struct ReminderCaptureBar: View {
    @Bindable var model: ReminderCaptureModel

    var body: some View {
        control
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private var control: some View {
        if model.priming {
            PrimerAffordance(
                onContinue: { Task { await model.confirmPrimer() } },
                onCancel: { model.cancel() }
            )
        } else if model.denied {
            DeniedAffordance(onDismiss: { model.cancel() })
        } else {
            switch model.currentArgument?.inputMethod {
            case .datePicker:
                Button {
                    model.commitDate()
                } label: {
                    Label("Set due date", systemImage: "calendar.badge.plus")
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
struct ReminderBreadcrumbBar: View {
    @Bindable var model: ReminderCaptureModel

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
    @Bindable var model: ReminderCaptureModel
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
/// the system request; the × abandons back to search.
private struct PrimerAffordance: View {
    var onContinue: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
            Text("Quickie saves this to your Reminders.")
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
        .accessibilityIdentifier("reminder-permission-primer")
    }
}

/// The inline "Enable in Settings" affordance shown when Reminders access was
/// refused (ADR 0012): graceful degradation, never a nag — a tap opens Settings,
/// the × returns to search.
private struct DeniedAffordance: View {
    var onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("Enable Reminders access to capture reminders.")
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
        .accessibilityIdentifier("reminder-permission-denied")
    }
}
