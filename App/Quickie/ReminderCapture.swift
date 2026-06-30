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
    /// Ask for the target list every capture; OFF routes to `defaultListID`
    /// (default OFF → the system default reminders list).
    var askList: Bool = false
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
    }

    /// Whether a capture is in progress (the center area shows its control).
    var isCapturing: Bool { session != nil }
    /// Whether the capture owns the bottom region — an active session, the primer,
    /// or the denial affordance — so the launcher swaps its normal input for it.
    var isActive: Bool { session != nil || denied || priming }

    var actionTitle: String { session?.actionTitle ?? "" }
    var pills: [ArgumentValue] { session?.pills ?? [] }
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
            try await service.create(draft)
            confirmation = Confirmation(message: "Reminder added")
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

// MARK: - Bottom capture bar (breadcrumb + morph control)

/// The bottom region while capturing: the breadcrumb of filled pills above the
/// control for the current step — the keyboard for text/choice, a commit button
/// for the date, or the inline "Enable in Settings" affordance on denial.
struct ReminderCaptureBar: View {
    @Bindable var model: ReminderCaptureModel

    var body: some View {
        VStack(spacing: 10) {
            if model.isCapturing {
                Breadcrumb(model: model)
            }
            control
        }
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

/// The horizontal breadcrumb: the Action title, the filled pills (tap to
/// re-edit), and a dashed placeholder for the step being collected.
private struct Breadcrumb: View {
    @Bindable var model: ReminderCaptureModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                crumb(model.actionTitle, weight: .semibold)

                ForEach(Array(model.pills.enumerated()), id: \.offset) { index, value in
                    Button {
                        model.editPill(at: index)
                    } label: {
                        crumb(pillText(value), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pill-\(index)")
                }

                if let label = model.currentArgument?.label {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay {
                            Capsule().strokeBorder(
                                .secondary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 1, dash: [4])
                            )
                        }
                }
            }
            .padding(.horizontal, 4)
        }
        .defaultScrollAnchor(.trailing)
    }

    private func crumb(_ text: String, weight: Font.Weight = .regular, interactive: Bool = false) -> some View {
        Text(text)
            .font(.subheadline.weight(weight))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
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
