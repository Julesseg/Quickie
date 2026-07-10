import SwiftUI
import QuickieCore

/// A quick-capture provider page (Reminders, Events) under the Settings hub: the
/// declared Options (Enabled, the default list/calendar picker, and — for Events —
/// the editor toggle) lead, then the capture's **reorderable step double-list**
/// (issue #145 follow-up). Same two-section shape as the Fallbacks page: an **On**
/// section (user-ordered, reorderable, a red minus turns a step off) above an **Off**
/// pool (every step not on, a green plus turns it on). Title is always the first
/// breadcrumb step, so it is pinned out of the list — only the steps after it arrange.
///
/// The whole list sits in constant edit mode (like the Fallbacks page) so the reorder
/// grips show without a separate Edit step; the Options rows above stay interactive.
struct CaptureStepsPage<Step: CaptureStepKind>: View {
    let provider: ProviderID
    let store: CaptureStepsStore
    /// The explanatory footer under the On section — what the steps mean for this kind.
    let stepsFooter: String

    var body: some View {
        List {
            ProviderOptionsSection(provider: provider)
            CaptureStepsSection<Step>(store: store, footer: stepsFooter)
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(provider.displayName)
    }
}

/// The On/Off step double-list (issue #145 follow-up), generic over the capture's
/// step type so one view serves reminders and events. Reads the enabled/pool raw ids
/// off the store and resolves them to typed steps for their labels and icons.
struct CaptureStepsSection<Step: CaptureStepKind>: View {
    let store: CaptureStepsStore
    let footer: String

    /// The enabled steps, in order — the store's raw ids resolved to typed steps.
    private var enabled: [Step] { store.enabledRaw.compactMap { Step(rawValue: $0) } }
    /// The disabled pool — the derived off steps, in canonical order.
    private var pool: [Step] { store.poolRaw.compactMap { Step(rawValue: $0) } }

    var body: some View {
        Section {
            if enabled.isEmpty {
                Text("No extra steps. This capture asks only for a title. Add a step below.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("capture-steps-on-empty")
            } else {
                ForEach(enabled, id: \.self) { step in
                    CaptureStepRow(step: step, style: .on) {
                        withAnimation { store.demote(step.rawValue) }
                    }
                }
                .onMove(perform: reorder)
            }
        } header: {
            Text("Steps")
        } footer: {
            Text(footer)
        }

        Section {
            if pool.isEmpty {
                Text("Every step is on.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("capture-steps-off-empty")
            } else {
                ForEach(pool, id: \.self) { step in
                    CaptureStepRow(step: step, style: .off) {
                        withAnimation { store.promote(step.rawValue) }
                    }
                }
            }
        } header: {
            Text("Off")
        } footer: {
            Text("Steps you've turned off. The green plus adds one to the bottom of the list above; drag the grip there to reorder. Title always comes first.")
        }
    }

    /// Persists a drag-reorder of the On section: apply the move to the enabled steps
    /// and hand the new raw order to the store.
    private func reorder(from offsets: IndexSet, to destination: Int) {
        var steps = enabled
        steps.move(fromOffsets: offsets, toOffset: destination)
        store.reorder(steps.map(\.rawValue))
    }
}

/// One step row. In **On** it is a red minus (turn off) + icon + title, with the drag
/// grip trailing (edit mode) to reorder. In **Off** it is a green plus (turn on) +
/// icon + title. No delete affordance — a step is never destroyed, only turned off.
private struct CaptureStepRow<Step: CaptureStepKind>: View {
    enum Style { case on, off }

    let step: Step
    let style: Style
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrimary) {
                Image(systemName: style == .on ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(style == .on ? .red : .green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(style == .on ? "Turn off \(step.title) step" : "Turn on \(step.title) step")
            .accessibilityIdentifier("\(style == .on ? "capture-step-off" : "capture-step-on").\(step.rawValue)")

            Label(step.title, systemImage: step.symbol)

            Spacer(minLength: 8)
        }
    }
}
