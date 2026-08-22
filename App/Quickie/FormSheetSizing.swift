import SwiftUI

extension View {
    /// Presents this editor as a **form sheet** (issue #264, audit finding F11): on an
    /// iPad a centered card, on an iPhone the full-height sheet it has always been.
    ///
    /// Both editors already rendered that way on an iPad — by default, not by decision.
    /// Saying it here is the point: the shape is now stated, so a change to SwiftUI's
    /// defaults is a change to how the app looks *and* a change to this line, rather
    /// than only the first.
    ///
    /// There is deliberately **no size-class check**. A sheet's own environment reads
    /// compact on both devices — an iPad form sheet is ~540pt wide — so a check made
    /// here would answer "compact" on an iPad and undo itself. `.presentationSizing`
    /// is resolved by the *presentation*, against the window, which is the only place
    /// that question has a right answer; compact windows ignore form sizing and keep
    /// the full-height sheet.
    ///
    /// F11 also asked that the editors' backgrounds be audited against the Liquid Glass
    /// sheet insets. There is nothing to reconcile: neither editor sets a background,
    /// so the card is the system's own and it insets itself (ADR 0010 — depth is the
    /// glass's job, not an outline's).
    func formSheetSizing() -> some View {
        presentationSizing(.form)
    }
}
