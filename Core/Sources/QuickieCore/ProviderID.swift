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
        case .calculator: return "Calculator"
        case .fileSearch: return "File Search"
        }
    }
}
