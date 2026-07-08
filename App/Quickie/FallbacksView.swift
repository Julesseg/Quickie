import SwiftUI
import QuickieCore

/// The two-section **Fallbacks** page (CONTEXT.md → Fallback list; issue #114) — the
/// same shape as editing the app row of the native iOS share sheet. An **Active
/// section** (user-ordered, most-important-first, reorderable, a red minus demotes to
/// the pool) sits above an **Available pool** (every fallback-eligible Action not
/// active, alphabetical by title, a green plus promotes to the *bottom* of Active).
/// Membership in the Active section is the fact the user sets here — the pool is
/// derived, and **nothing on this page deletes anything**: deletion lives on an
/// action's home page (Custom Actions / Shortcuts). Save for later and New Snippet are
/// demotable but permanent.
///
/// Each row also carries the action's **enable/disable** toggle — the same instance
/// switch its home page shows. Disabling an action hides it from every launcher surface
/// *and* demotes it from Active into the pool; re-enabling leaves it in the pool until
/// the user promotes it again. So the pool holds both enabled-but-not-active actions
/// (a green plus, ready to promote) and disabled ones (dimmed).
///
/// Reached as the typed "Fallbacks" command row and presented full-screen. It is fed
/// the live fallback-eligible Actions (text-first Custom Actions, accepts-input
/// Shortcuts, the two built-in captures) so eligibility stays derived from shape.
struct FallbacksView: View {
    let store: FallbacksStore
    /// The per-action instance Disabled state (issue #68) — the same toggle the
    /// action's home page shows, surfaced here and coupled to demotion.
    let enablement: EnablementStore
    /// The live fallback-eligible Actions, from `RootView` — the union the two
    /// sections partition by the store's enabled list and the disabled set.
    let eligible: [Action]

    /// The eligible Actions keyed by id, so an enabled/pooled id resolves to its row.
    private var byID: [String: Action] {
        Dictionary(eligible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The Active section, most-important-first: the enabled list resolved to live
    /// Actions, minus any that are instance-disabled (a disabled action always sits in
    /// the pool, even for the frame before `demoteDisabled` prunes it from the list).
    private var activeActions: [Action] {
        store.resolvedEnabled(for: eligible.map(\.id))
            .compactMap { byID[$0] }
            .filter { !enablement.isDisabled($0.id) }
    }

    /// The Available pool: every eligible Action not in the Active section — the ones
    /// not activated *plus* the disabled ones — alphabetical by title (id as the
    /// deterministic tie-break). Derived from `activeActions` so no Action shows twice.
    private var pooledActions: [Action] {
        let activeIDs = Set(activeActions.map(\.id))
        return eligible
            .filter { !activeIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    // Pushed onto the launcher's navigation stack — no own stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019): Options (the kind-level master
            // Enabled switch over the whole bottom region) lead the two sections.
            ProviderOptionsSection(provider: .fallbacks)

            Section {
                if activeActions.isEmpty {
                    Text("No active fallbacks. Add one from the list below.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fallbacks-enabled-empty")
                } else {
                    ForEach(activeActions) { action in
                        FallbackRow(
                            action: action,
                            style: .active,
                            isDisabled: enablement.isDisabled(action.id),
                            onPrimary: { store.demote(action.id) },
                            onToggleDisabled: { enablement.toggleDisabled(action.id) }
                        )
                    }
                    .onMove(perform: reorder)
                }
            } header: {
                Text("Active")
            } footer: {
                Text("Top is most important — nearest the input in results. Tap Edit to reorder. The red minus moves a fallback to the list below; the toggle disables the action everywhere and moves it there too. Nothing here deletes it.")
            }

            Section {
                if pooledActions.isEmpty {
                    Text("Every eligible fallback is active.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fallbacks-pool-empty")
                } else {
                    ForEach(pooledActions) { action in
                        FallbackRow(
                            action: action,
                            style: .pool,
                            isDisabled: enablement.isDisabled(action.id),
                            onPrimary: { promote(action) },
                            onToggleDisabled: { enablement.toggleDisabled(action.id) }
                        )
                    }
                }
            } header: {
                Text("Available")
            } footer: {
                Text("Fallback-eligible actions you haven't activated, plus any you've disabled. The green plus adds one to the bottom of the active list. A Custom Action or Shortcut becomes eligible when its first argument is free text.")
            }
        }
        .navigationTitle("Fallbacks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    /// Promotes a pooled Action to the bottom of Active. A disabled one is re-enabled
    /// first, so a promoted fallback is always live (an active-but-hidden row would be
    /// a contradiction) — the plus reads as "make this an active fallback".
    private func promote(_ action: Action) {
        if enablement.isDisabled(action.id) { enablement.toggleDisabled(action.id) }
        store.promote(action.id)
    }

    /// Persists a reorder of the Active section. The offsets index into
    /// `activeActions` (the resolved, loaded list), so the moved ids are the new
    /// visible order; `reorderEnabled` applies it while keeping any enabled id that
    /// hasn't resolved yet in place (the launch race) rather than dropping it.
    private func reorder(from offsets: IndexSet, to destination: Int) {
        var ids = activeActions.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        store.reorderEnabled(visibleOrder: ids)
    }
}

/// One Fallbacks-page row, shared by both sections: a leading activation control (red
/// minus to demote in **Active**, green plus to promote in **pool**), the action's
/// title + kind caption, and the instance enable/disable toggle. No delete affordance.
private struct FallbackRow: View {
    enum Style { case active, pool }

    let action: Action
    let style: Style
    let isDisabled: Bool
    /// Demote (Active) or promote (pool) — the section's activation verb.
    let onPrimary: () -> Void
    let onToggleDisabled: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrimary) {
                Image(systemName: style == .active ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(style == .active ? .red : .green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(style == .active ? "Remove from active fallbacks" : "Add to active fallbacks")
            .accessibilityIdentifier("\(style == .active ? "fallback-demote" : "fallback-promote").\(action.id)")

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                if let caption = kindCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)

            // The instance enable/disable toggle — disabling hides the action
            // everywhere and (via demoteDisabled) parks it in the pool.
            Toggle("Enabled", isOn: Binding(get: { !isDisabled }, set: { _ in onToggleDisabled() }))
                .labelsHidden()
                .accessibilityIdentifier("fallback-enabled.\(action.id)")
        }
    }

    /// A small caption naming what kind of fallback this is — so a permanent capture
    /// reads distinctly from a user's Custom Action or Shortcut.
    private var kindCaption: String? {
        switch action.kind {
        case .customAction: return "Custom Action"
        case .shortcut: return "Shortcut"
        case .saveForLater, .newSnippet: return "Built-in capture"
        default: return nil
        }
    }
}
