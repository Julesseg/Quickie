import Foundation

/// The Favorites widget **snapshot codec** (ADR 0025; issue #126): how the
/// app-written Favorites projection is serialized into its App Group key and read
/// back by the widget. Pure and `swift test`-covered so the write and read sides
/// can never drift. Tolerant on read — absent or unreadable data decodes to `[]`,
/// which the widget renders as the pin-invitation placeholder: never blank, never
/// an error.
///
/// The denormalized item and its execution classification are the shared
/// `WidgetAction` / `WidgetExecution` (see `WidgetAction.swift`) — the same shape
/// the eligible-action catalog uses (ADR 0027), so the Favorites and Actions
/// widgets render one cell language.
public enum FavoritesWidgetSnapshot {
    /// The grid's cap (CONTEXT.md → Favorites grid): at most four Favorites, so
    /// the codec clamps both sides and a malformed over-long snapshot can never
    /// draw a fifth cell.
    public static let capacity = 4

    /// Encodes the snapshot as JSON, clamped to the grid's four in pin order.
    public static func encode(_ favorites: [WidgetAction]) -> Data? {
        try? JSONEncoder().encode(Array(favorites.prefix(capacity)))
    }

    /// Decodes a snapshot, clamped to the grid's four; `nil` or garbage reads as
    /// empty — the widget's placeholder state, never an error.
    public static func decode(_ data: Data?) -> [WidgetAction] {
        guard let data,
              let decoded = try? JSONDecoder().decode([WidgetAction].self, from: data)
        else { return [] }
        return Array(decoded.prefix(capacity))
    }
}
