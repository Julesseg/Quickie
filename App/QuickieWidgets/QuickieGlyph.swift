/// The single glyph every widget-extension [[Entry surface]] renders for "open
/// Quickie" — a magnifying glass, the launcher's search identity (Quickie ships no
/// standalone brand mark), matching the focused input the entry route lands the user
/// on. Shared by the deep-link widget (`EntryWidget`, #124) and the Control Center
/// control (`QuickCaptureControl`, #125) so the two entry surfaces can never drift
/// onto different symbols.
enum QuickieGlyph {
    static let app = "magnifyingglass"
}
