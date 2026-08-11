import SwiftUI
import QuickieCore

/// The three-section **Fallbacks** page (CONTEXT.md → Fallback list, Shelf; issues
/// #114, #241) — the same shape as editing the app row of the native iOS share sheet.
/// It renders the promotion ladder top-down: the **Shelf** (the glass button row above
/// the input — drag-ordered, a red minus drops a member to the *top* of Active), then
/// the **Active section** (user-ordered, most-important-first, reorderable, a red minus
/// demotes to the pool), then the **Available pool** (every fallback-eligible Action on
/// neither rung, alphabetical by title, a green plus promotes to the *bottom* of
/// Active). Every row that isn't already shelved carries a shelf button, so a pool row
/// can climb straight to the Shelf without a forced two-step climb.
///
/// Rung membership is the fact the user sets here — the pool is derived, and **nothing
/// on this page deletes anything**: deletion lives on an action's home page (Custom
/// Actions / Shortcuts). Save for later and New Snippet are demotable but permanent.
/// There is deliberately no capture-vs-search category behind the Shelf (ADR 0037):
/// membership is purely the user's choice, seeded with four sensible defaults.
///
/// Pool rows also carry the action's **enable/disable** toggle — the same instance
/// switch its home page shows. Disabling an action hides it from every launcher surface
/// *and* demotes it off both tiers into the pool; re-enabling leaves it in the pool
/// until the user promotes it again. So the pool holds both enabled-but-not-active
/// actions (a green plus, ready to promote) and disabled ones (dimmed).
///
/// Reached as the typed "Fallbacks" command row and presented full-screen. It is fed
/// the live fallback-eligible Actions (text-first Custom Actions, accepts-input
/// Shortcuts, the built-in captures) so eligibility stays derived from shape.
struct FallbacksView: View {
    let store: FallbacksStore
    /// The per-action instance Disabled state (issue #68) — the same toggle the
    /// action's home page shows, surfaced here and coupled to demotion.
    let enablement: EnablementStore
    /// The live fallback-eligible Actions, from `RootView` — the union the three
    /// sections partition by the store's tiers and the disabled set.
    let eligible: [Action]

    /// The Shelf section, most-important-first (leading edge of the button row): the
    /// Shelf resolved to live Actions, minus any that are instance-disabled — a
    /// disabled action always sits in the pool, even for the frame before
    /// `demoteDisabled` prunes it from the lists.
    private var shelvedActions: [Action] {
        liveActions(store.resolvedShelf(for: eligible.map(\.id)))
    }

    /// The Active section, most-important-first: the enabled list resolved to live
    /// Actions, minus the instance-disabled ones (same reason as the Shelf).
    private var activeActions: [Action] {
        liveActions(store.resolvedEnabled(for: eligible.map(\.id)))
    }

    /// The Available pool: every eligible Action on neither rung — the ones not
    /// activated *plus* the disabled ones — alphabetical by title (id as the
    /// deterministic tie-break). Derived from the two sections above so no Action
    /// shows twice.
    private var pooledActions: [Action] {
        let claimed = Set(shelvedActions.map(\.id)).union(activeActions.map(\.id))
        return eligible
            .filter { !claimed.contains($0.id) }
            .sorted { lhs, rhs in
                let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    /// Resolves an ordered id list to Actions, dropping the instance-disabled ones —
    /// Core's rule, shared with the Shelf row above the input (`RootView
    /// .shelfMembers`), so a rung means the same thing on the page and in the launcher.
    private func liveActions(_ ids: [String]) -> [Action] {
        FallbackTiers.liveMembers(of: ids, in: eligible, hiding: enablement.disabled)
    }

    // Pushed onto the launcher's navigation stack — no own stack or Done button.
    var body: some View {
        List {
            // The unified page shape (ADR 0019): Options (the kind-level master
            // Enabled switch over the whole bottom region) lead the sections.
            ProviderOptionsSection(provider: .fallbacks)

            Section {
                if shelvedActions.isEmpty {
                    Text("No shelved fallbacks. The shelf above the input stays hidden.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fallbacks-shelf-empty")
                } else {
                    ForEach(shelvedActions) { action in
                        // Shelf rows: a red minus that drops the member to the *top*
                        // of Active, plus the drag grip. No shelf button — it's here.
                        FallbackRow(
                            action: action,
                            style: .shelf,
                            onPrimary: { withAnimation { store.move(action.id, to: .enabled) } },
                            onShelve: nil
                        )
                    }
                    .onMove { offsets, destination in
                        store.reorderShelf(visibleOrder: moved(shelvedActions, from: offsets, to: destination))
                    }
                }
            } header: {
                Text("Shelf")
            } footer: {
                Text("The round buttons above the input while you're typing — leading edge first. Drag the grip to reorder; the red minus moves one down to the top of the active list. A shelved fallback leaves the bottom of the result list.")
            }

            Section {
                if activeActions.isEmpty {
                    Text("No active fallbacks. Add one from the list below.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fallbacks-enabled-empty")
                } else {
                    ForEach(activeActions) { action in
                        // Active rows: a red minus to demote, the shelf button to
                        // promote a rung up, and the drag grip to reorder — no
                        // enable/disable toggle (it lives on the pool).
                        FallbackRow(
                            action: action,
                            style: .active,
                            onPrimary: { withAnimation { store.move(action.id, to: .pool) } },
                            onShelve: { withAnimation { store.move(action.id, to: .shelf) } }
                        )
                    }
                    .onMove { offsets, destination in
                        store.reorderEnabled(visibleOrder: moved(activeActions, from: offsets, to: destination))
                    }
                }
            } header: {
                Text("Active")
            } footer: {
                Text("Top is most important — nearest the input in results. Drag the grip to reorder; the red minus moves a fallback down to the list below, the up arrow onto the shelf. Nothing here deletes it.")
            }

            Section {
                if pooledActions.isEmpty {
                    Text("Every eligible fallback is shelved or active.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fallbacks-pool-empty")
                } else {
                    ForEach(pooledActions) { action in
                        // Pool rows: a green plus to promote to Active, the shelf
                        // button to climb straight to the Shelf, and the action's
                        // enable/disable toggle — the toggle only appears here.
                        FallbackRow(
                            action: action,
                            style: .pool(
                                isDisabled: enablement.isDisabled(action.id),
                                onToggleDisabled: { withAnimation { enablement.toggleDisabled(action.id) } }
                            ),
                            onPrimary: { promote(action, to: .enabled) },
                            onShelve: { promote(action, to: .shelf) }
                        )
                    }
                }
            } header: {
                Text("Available")
            } footer: {
                Text("Fallback-eligible actions you haven't activated, plus any you've disabled. The green plus adds one to the bottom of the active list and the up arrow puts it straight on the shelf; the toggle disables the action everywhere. A Custom Action or Shortcut becomes eligible when its first argument is free text.")
            }
        }
        // Always in edit mode so the reorder grips show on the Shelf and Active rows
        // without a separate Edit step — the same always-editable shape as the iOS
        // share sheet's app row. The custom minus/plus/shelf buttons and the pool
        // toggles stay interactive (they carry explicit button/toggle styles, not
        // row-selection taps).
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Fallbacks")
    }

    /// Promotes a pooled Action a rung up — to the bottom of Active or onto the Shelf.
    /// A disabled one is re-enabled first, so a promoted fallback is always live (an
    /// active-but-hidden row would be a contradiction) — the plus reads as "make this
    /// an active fallback", the up arrow as "put this on the shelf".
    private func promote(_ action: Action, to tier: FallbackTier) {
        withAnimation {
            if enablement.isDisabled(action.id) { enablement.toggleDisabled(action.id) }
            store.move(action.id, to: tier)
        }
    }

    /// The new **visible** id order after a drag in one section. The offsets index
    /// into that section's resolved, loaded rows; the store applies the result while
    /// keeping any stored id that hasn't resolved yet in place (the launch race)
    /// rather than dropping it.
    private func moved(_ rows: [Action], from offsets: IndexSet, to destination: Int) -> [String] {
        var ids = rows.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        return ids
    }
}

/// One Fallbacks-page row. Both activation verbs sit together on the **leading** edge,
/// ahead of the title: In the **Shelf** it is a red minus (drop to the top of Active) +
/// title, with the system drag grip trailing (edit mode). In **Active** it is a red
/// minus (demote to the pool) + a shelf button + title, also with the grip. In the
/// **pool** it is a green plus (promote to Active) + a shelf button + title, with the
/// action's instance enable/disable toggle trailing. No delete affordance in any of them.
private struct FallbackRow: View {
    /// Which section the row is rendering in — and, for the pool, the instance
    /// Disabled state and switch that only *it* carries, so the two ordered tiers
    /// don't pass placeholders for a control they never show.
    enum Style {
        case shelf
        case active
        case pool(isDisabled: Bool, onToggleDisabled: () -> Void)

        /// The pool's dimming/toggle state; the ordered tiers never hold a disabled
        /// action (`demoteDisabled` drops it to the pool), so they read as enabled.
        var isDisabled: Bool {
            if case .pool(let isDisabled, _) = self { return isDisabled }
            return false
        }

        var isPool: Bool {
            if case .pool = self { return true }
            return false
        }
    }

    let action: Action
    let style: Style
    /// Demote (Shelf, Active) or promote (pool) — the section's primary activation verb.
    let onPrimary: () -> Void
    /// Promote onto the Shelf. `nil` on Shelf rows, which are already there.
    let onShelve: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrimary) {
                Image(systemName: style.isPool ? "plus.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(style.isPool ? .green : .red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(primaryLabel)
            .accessibilityIdentifier("\(style.isPool ? "fallback-promote" : "fallback-demote").\(action.id)")

            // The shelf button — one rung up, from Active *or* straight from the pool
            // (no forced two-step climb). Absent on Shelf rows, which are already there.
            if let onShelve {
                Button(action: onShelve) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Move to the shelf")
                .accessibilityIdentifier("fallback-shelve.\(action.id)")
            }

            // The same leading provider badge every other surface renders (result
            // rows, Favorites, the Custom Actions/Shortcuts management rows) — an
            // eligible fallback is always a real Action with a kind (and, for a
            // customized Custom Action or Shortcut, its own glyph/color), so the
            // page that governs *which* fallbacks run should say *what* each one is
            // at a glance, the same way its home page already does.
            ProviderBadge(kind: action.kind, symbol: action.glyph, color: action.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .foregroundStyle(style.isDisabled ? .secondary : .primary)
                if let caption = kindCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)

            // The instance enable/disable toggle lives only on the pool rows —
            // disabling hides the action everywhere; a shelved or active fallback is
            // demoted here first (or disabled from its home page) before it can be
            // switched off.
            if case .pool(let isDisabled, let onToggleDisabled) = style {
                Toggle("Enabled", isOn: Binding(get: { !isDisabled }, set: { _ in onToggleDisabled() }))
                    .labelsHidden()
                    .accessibilityIdentifier("fallback-enabled.\(action.id)")
            }
        }
    }

    /// What the leading circle does, spelled out for VoiceOver — the same verb the
    /// section's footer uses.
    private var primaryLabel: String {
        switch style {
        case .shelf: return "Remove from the shelf"
        case .active: return "Remove from active fallbacks"
        case .pool: return "Add to active fallbacks"
        }
    }

    /// A small caption naming what kind of fallback this is — so a permanent capture
    /// reads distinctly from a user's Custom Action or Shortcut.
    private var kindCaption: String? {
        switch action.kind {
        case .customAction: return "Custom Action"
        case .shortcut: return "Shortcut"
        case .saveForLater, .newSnippet, .reminder, .event: return "Built-in capture"
        case .system: return "System built-in"
        default: return nil
        }
    }
}
