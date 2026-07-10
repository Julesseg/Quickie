import Foundation

/// The stable identity of a Provider as a *configurable thing* (ADR 0019;
/// issue #66): what the Settings hub's Providers section lists, what a
/// `.openPage(.settings(panel:))` deeplink targets, and what future kind-level
/// enablement persists against. The raw value is that persisted identity —
/// renaming a case must never re-key stored state — and `displayName` is the
/// user-facing name the Providers list and each page title show.
///
/// Settings itself is deliberately **not** a ProviderID: it is the hub, not a
/// provider inside it, which is what makes it non-disableable by construction
/// (there is no identity for a disable switch to key off).
public enum ProviderID: String, CaseIterable, Equatable, Hashable, Sendable {
    case quicklinks
    /// User-authored **Custom Actions** (CONTEXT.md → Custom Action; ADR 0021):
    /// URL-template Actions whose `{name}` slots the breadcrumb fills. Its own
    /// configurable kind — the authoring surface is the Custom Actions Management
    /// page (issue #94); the Fallbacks page stays the fallback-region ordering surface.
    case customActions = "custom-actions"
    case fallbacks
    case snippets
    /// The Pile (CONTEXT.md → Pile; ADR 0018): the saved-for-later queries,
    /// replacing the former Notes provider wholesale.
    case pile
    case shortcuts
    case reminders
    case events
    /// The **System** umbrella provider (CONTEXT.md → System provider; ADR 0029):
    /// groups Quickie's OS-integration actions and links to the Reminders and
    /// Events pages beneath it. Its Enabled toggle **cascades** — off short-circuits
    /// every member kind (see `umbrellaParent`, `isEffectivelyEnabled`).
    case system
    case calculator
    case fileSearch = "file-search"

    /// The user-facing name: the Providers list row and the page title.
    public var displayName: String {
        switch self {
        case .quicklinks: return "Quicklinks"
        case .customActions: return "Custom Actions"
        case .fallbacks: return "Fallbacks"
        case .snippets: return "Snippets"
        case .pile: return "Pile"
        case .shortcuts: return "Shortcuts"
        case .reminders: return "Reminders"
        case .events: return "Events"
        case .system: return "System"
        case .calculator: return "Calculator"
        case .fileSearch: return "File Search"
        }
    }

    /// The **umbrella parent** governing this provider (CONTEXT.md → System
    /// provider; ADR 0029), or `nil` for a top-level provider. Reminders and Events
    /// live under the System umbrella: its Enabled toggle off short-circuits them
    /// (the member's own toggle keeps working underneath — see
    /// `ProviderEnablement.isEffectivelyEnabled`). The one grouping level above kind.
    public var umbrellaParent: ProviderID? {
        switch self {
        case .reminders, .events: return .system
        default: return nil
        }
    }

    /// The providers the top-level Settings **Providers** list shows, in order
    /// (CONTEXT.md → Settings; ADR 0029). The umbrella members (Reminders, Events)
    /// are folded under the single **System** row — reachable through it, or by
    /// typing their names — so they do not appear here directly.
    public static let topLevelProviders: [ProviderID] = allCases.filter { $0.umbrellaParent == nil }
}
