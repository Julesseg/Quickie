import SwiftUI
import QuickieCore

/// The **Options** section every provider page leads with (CONTEXT.md →
/// Management page; ADR 0019, issue #66), led by the provider-level **Enabled**
/// toggle — the kind-level disable switch (CONTEXT.md → Disabled; issue #67).
/// Off reversibly hides the whole provider from typed results, the Recent list,
/// and the Favorites grid while its data and configuration are retained; the
/// declared settings schema (ADR 0020) joins it beneath in a later slice.
/// Shared by every provider page so the unified two-section shape reads the
/// same everywhere. Settings itself has no `ProviderID`, so no page can even
/// render a toggle for it — non-disableable by construction.
struct ProviderOptionsSection: View {
    let provider: ProviderID

    /// The persisted kind-level switches, injected at the root so every
    /// provider page — however it is reached — reads and writes the same state
    /// the engine filters by.
    @Environment(ProviderEnablementStore.self) private var enablement

    var body: some View {
        Section {
            Toggle("Enabled", isOn: Binding(
                get: { enablement.isEnabled(provider) },
                set: { enablement.setEnabled($0, for: provider) }
            ))
            .accessibilityIdentifier("provider-enabled-\(provider.rawValue)")
        } header: {
            Text("Options")
        } footer: {
            Text("Off hides \(provider.displayName) from results, Recents, and Favorites until you turn it back on. Its data is kept, and you can always reach this page by typing its name.")
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
        case .pile: return "tray.full"
        case .shortcuts: return "square.stack.3d.up"
        case .reminders: return "checklist"
        case .events: return "calendar"
        case .calculator: return "function"
        case .fileSearch: return "doc.text.magnifyingglass"
        }
    }
}
