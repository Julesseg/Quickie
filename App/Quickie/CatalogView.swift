import SwiftUI
import SwiftData
import QuickieCore
import QuickieStoreKit

/// The **Catalog** Browse page (CONTEXT.md → Catalog; ADR 0028; issue #143): a
/// read-only, sectioned gallery of ready-made Custom Action templates, pushed from
/// the "Browse catalog" row on the Custom Actions page. Each row shows the entry's
/// default-glyph badge, the template's name, its URL, an optional "Requires <app>"
/// note, and a per-entry **Install** button.
///
/// Install stamps out an *ordinary* Custom Action under a fresh id (`make(from:)`
/// mints a UUID) and flashes a momentary "Added" confirmation — there is no
/// installed-state, so every entry always offers Install and tapping twice yields two
/// rows, exactly like hand-creating two identical Custom Actions.
struct CatalogView: View {
    @Environment(\.modelContext) private var modelContext

    /// The entry ids currently showing their momentary "Added" confirmation. An id is
    /// added on Install and removed after a short delay — the only transient UI state;
    /// no installed-state is tracked (ADR 0028).
    @State private var justAdded: Set<String> = []

    // Pushed onto the launcher's navigation stack — the back chevron handles
    // dismissal, so this view adds no stack or Done button.
    var body: some View {
        List {
            ForEach(CatalogCategory.allCases, id: \.self) { category in
                let entries = Catalog.entries(in: category)
                if !entries.isEmpty {
                    Section {
                        ForEach(entries) { entry in
                            CatalogEntryRow(
                                entry: entry,
                                justAdded: justAdded.contains(entry.id),
                                onInstall: { install(entry) }
                            )
                        }
                    } header: {
                        Text(category.title)
                    }
                }
            }
        }
        .navigationTitle("Browse catalog")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Installs an entry: inserts a fresh-id ordinary Custom Action and flashes the
    /// "Added" confirmation for it. Never checks for an existing copy (ADR 0028).
    private func install(_ entry: CatalogEntry) {
        modelContext.insert(StoredCustomAction.make(from: entry.definition))
        try? modelContext.save()

        justAdded.insert(entry.id)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            justAdded.remove(entry.id)
        }
    }
}

/// One Catalog entry row: the entry's default-glyph badge, name, URL template,
/// optional "Requires <app>" note, and the Install button (which morphs to a
/// momentary "Added" confirmation).
private struct CatalogEntryRow: View {
    let entry: CatalogEntry
    let justAdded: Bool
    let onInstall: () -> Void

    /// The badge's tint follows the entry's shape via the shared Core rule (a slotted
    /// template installs a Custom Action, a slot-less one a static link) — the same
    /// badge the installed action's management-page row and result rows will wear.
    private var badgeKind: ActionKind {
        CustomActionDefinition.derivedKind(forTemplate: entry.template)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let glyph = CustomActionDefinition.normalizedGlyph(entry.glyph) {
                ProviderBadge(kind: badgeKind, symbol: glyph)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                Text(entry.template)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let requiresApp = entry.requiresApp {
                    Text("Requires \(requiresApp)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onInstall) {
                if justAdded {
                    Label("Added", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                } else {
                    Text("Install")
                }
            }
            .buttonStyle(.bordered)
            .disabled(justAdded)
            .accessibilityIdentifier("install-catalog-entry.\(entry.id)")
        }
    }
}
