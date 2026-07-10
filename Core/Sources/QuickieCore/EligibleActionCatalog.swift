import Foundation

/// The **eligible-action catalog** codec (ADR 0027): how the app-written snapshot of
/// every eligible Action (every enabled Action except a [[Pile]] entry) is
/// serialized into its App Group key and read back out of process by the
/// [[Actions widget]]'s picker + timeline and the [[Action control]]'s picker +
/// value provider.
///
/// A second snapshot beside the Favorites one (`FavoritesWidgetSnapshot`), in the
/// **same** denormalized `WidgetAction` shape — id, title, glyph, kind, classified
/// `WidgetExecution` — so both surfaces render one cell language. The membership
/// (the chosen ids) lives in each placed instance's `AppIntentConfiguration`, *not*
/// here: this catalog is only the data the picker enumerates and the render joins
/// configured ids against. The configuration stores ids only; the widget process
/// never opens SwiftData (ADR 0027).
///
/// Unlike the Favorites snapshot there is **no capacity cap** — the catalog is the
/// whole eligible set (the picker offers all of it; the widget's own four-cell cap
/// applies to the *chosen* list, not the catalog). Pure and `swift test`-covered so
/// the write, the read, and the id-join can never drift. Tolerant on read: absent or
/// unreadable data decodes to `[]`, so a corrupt key can never wedge the widget —
/// every configured id simply fails the join and its cell degrades to the dashed
/// empty slot, never an error.
public enum EligibleActionCatalog {
    /// Encodes the catalog as JSON, in the app-provided order (the picker presents
    /// it as given). Encoding a value of plain `Codable` structs can't realistically
    /// fail; `nil` only keeps the signature honest.
    public static func encode(_ actions: [WidgetAction]) -> Data? {
        try? JSONEncoder().encode(actions)
    }

    /// Decodes the catalog; `nil` or garbage reads as empty — every join then
    /// misses and the surface degrades, never an error.
    public static func decode(_ data: Data?) -> [WidgetAction] {
        guard let data,
              let decoded = try? JSONDecoder().decode([WidgetAction].self, from: data)
        else { return [] }
        return decoded
    }

    /// **Joins** a configured list of ids against the catalog — the one operation
    /// the timeline provider and the control's value provider both run to turn the
    /// ids a configuration stores into the `WidgetAction`s it renders and executes.
    ///
    /// Preserves the **configured order** (the user's chosen order fills the grid),
    /// and **drops** any id the catalog no longer resolves — a deleted or [[Disabled]]
    /// action leaves the catalog, so its id falls out here and its cell degrades to
    /// the dashed empty slot / the control falls back to a clean-Home open (ADR
    /// 0027). **Duplicates are kept**: the widget's slots are independent, so a user
    /// who binds the same action to two slots means it — both cells render it (each
    /// runs identically). The control resolves a single id, so duplication never
    /// arises there.
    public static func resolve(ids: [String], in catalog: [WidgetAction]) -> [WidgetAction] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
}
