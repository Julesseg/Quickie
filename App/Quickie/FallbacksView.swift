import SwiftUI
import QuickieCore

/// The two-section **Fallbacks** page (CONTEXT.md → Fallback list; issue #114) — the
/// same shape as editing the app row of the native iOS share sheet. An **enabled
/// section** (user-ordered, most-important-first, reorderable, a red minus demotes to
/// the pool) sits above a **disabled pool** (every fallback-eligible Action not
/// enabled, alphabetical by title, not reorderable, a green plus promotes to the
/// *bottom* of the enabled section). Membership in the enabled section is the only
/// fact set here — the pool is derived, and **nothing on this page deletes anything**:
/// deletion lives on an action's home page (Custom Actions / Shortcuts). Save for
/// later and New Snippet are demotable but permanent.
///
/// Reached as the typed "Fallbacks" command row and presented full-screen. It is fed
/// the live fallback-eligible Actions (text-first Custom Actions, accepts-input
/// Shortcuts, the two built-in captures) so eligibility stays derived from shape.
struct FallbacksView: View {
    let store: FallbacksStore
    /// The live fallback-eligible Actions, from `RootView` — the union the two
    /// sections partition by the store's enabled list.
    let eligible: [Action]

    /// The eligible Actions keyed by id, so an enabled/pooled id resolves to its row.
    private var byID: [String: Action] {
        Dictionary(eligible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The enabled section, most-important-first: the store's enabled list resolved to
    /// live Actions (a stale id — one that lost eligibility — drops out).
    private var enabledActions: [Action] {
        store.resolvedEnabled(for: eligible.map(\.id)).compactMap { byID[$0] }
    }

    /// The derived disabled pool: eligible Actions not enabled, **alphabetical by
    /// title** (id as the deterministic tie-break) — a waiting room, not a ranking.
    private var pooledActions: [Action] {
        store.pool(from: eligible.map(\.id))
            .compactMap { byID[$0] }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedSame
                    ? lhs.id < rhs.id
                    : lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    // Pushed onto the launcher's navigation stack — no own stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019): Options (the kind-level master
            // Enabled switch over the whole bottom region) lead the two sections.
            ProviderOptionsSection(provider: .fallbacks)

            Section {
                if enabledActions.isEmpty {
                    Text("No active fallbacks. Add one from the list below.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fallbacks-enabled-empty")
                } else {
                    ForEach(enabledActions) { action in
                        FallbackActiveRow(action: action) { store.demote(action.id) }
                    }
                    .onMove(perform: reorder)
                }
            } header: {
                Text("Active")
            } footer: {
                Text("Top is most important — nearest the input in results. Tap Edit to reorder. The red minus moves a fallback to the list below; nothing here deletes it.")
            }

            Section {
                if pooledActions.isEmpty {
                    Text("Every eligible fallback is active.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fallbacks-pool-empty")
                } else {
                    ForEach(pooledActions) { action in
                        FallbackPoolRow(action: action) { store.promote(action.id) }
                    }
                }
            } header: {
                Text("Available")
            } footer: {
                Text("Fallback-eligible actions you haven't activated. The green plus adds one to the bottom of the active list. A Custom Action or Shortcut becomes eligible when its first argument is free text.")
            }
        }
        .navigationTitle("Fallbacks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    /// Persists a reorder of the Active section. The offsets index into
    /// `enabledActions` (the resolved, *loaded* list), so the moved ids are the new
    /// visible order; `reorderEnabled` applies it while keeping any enabled id that
    /// hasn't resolved yet in place (the launch race) rather than dropping it.
    private func reorder(from offsets: IndexSet, to destination: Int) {
        var ids = enabledActions.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        store.reorderEnabled(visibleOrder: ids)
    }
}

/// A row in the **Active** section: the fallback's title (+ a kind caption) and a red
/// minus that demotes it to the pool. No delete affordance — demotion is the only verb.
private struct FallbackActiveRow: View {
    let action: Action
    let onDemote: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDemote) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove from active fallbacks")
            .accessibilityIdentifier("fallback-demote.\(action.id)")

            FallbackRowLabel(action: action)
            Spacer(minLength: 8)
        }
        .accessibilityIdentifier("fallback-active-row.\(action.id)")
    }
}

/// A row in the **Available** pool: the fallback's title (+ a kind caption) and a
/// green plus that promotes it to the bottom of the active section.
private struct FallbackPoolRow: View {
    let action: Action
    let onPromote: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPromote) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add to active fallbacks")
            .accessibilityIdentifier("fallback-promote.\(action.id)")

            FallbackRowLabel(action: action)
            Spacer(minLength: 8)
        }
        .accessibilityIdentifier("fallback-pool-row.\(action.id)")
    }
}

/// The shared title + kind caption for a fallback row, so the two sections read alike.
private struct FallbackRowLabel: View {
    let action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(action.title)
                .font(.body)
            if let caption = kindCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
