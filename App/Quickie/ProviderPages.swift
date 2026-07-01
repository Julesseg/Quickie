import SwiftUI
import QuickieCore

/// The **Options** section every provider page leads with (CONTEXT.md →
/// Management page; ADR 0019, issue #66). This slice is the page-*shape*
/// reframe, so the section carries only the provider's name as a placeholder —
/// the declared settings schema (toggles, choices, the Enabled switch) lands in
/// a later slice and will replace this row. Shared by every provider page so
/// the unified two-section shape reads the same everywhere.
struct ProviderOptionsSection: View {
    let provider: ProviderID

    var body: some View {
        Section {
            LabeledContent("Provider") {
                Text(provider.displayName)
            }
            .accessibilityIdentifier("provider-options-\(provider.rawValue)")
        } header: {
            Text("Options")
        }
    }
}

/// The unified page for a provider with **no enumerable instances** (CONTEXT.md
/// → Management page; ADR 0019): Calculator and the Reminders capture show only
/// the Options section — there is no content list to render beneath it. Content
/// providers (File Search included, whose content is its folder grants) instead
/// lead their own list pages with the same `ProviderOptionsSection`.
struct ProviderOptionsPage: View {
    let provider: ProviderID

    var body: some View {
        Form {
            ProviderOptionsSection(provider: provider)
        }
        .navigationTitle(provider.displayName)
    }
}

extension ProviderID {
    /// The SF Symbol the Settings hub's Providers list shows beside each row —
    /// the same vocabulary as the result rows' provider badges (`ActionIcons`),
    /// so a provider looks like itself on both surfaces.
    var symbol: String {
        switch self {
        case .quicklinks: return "link"
        case .fallbacks: return "magnifyingglass"
        case .snippets: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .shortcuts: return "square.stack.3d.up"
        case .reminders: return "checklist"
        case .events: return "calendar"
        case .calculator: return "function"
        case .fileSearch: return "doc.text.magnifyingglass"
        }
    }
}
