import SwiftUI
import QuickieCore

/// A pending **Share** secondary action (CONTEXT.md → Secondary action; ADR 0017):
/// the resolved activity items handed to `UIActivityViewController`, plus a fresh
/// identity so each share drives a distinct presentation. A file share also carries
/// the live `FileAccess`, held open while sharing and released when the presentation
/// goes away; a text/url/Pile share leaves it `nil`.
struct ShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
    var fileAccess: FileAccess?
}

/// The launcher's pending Share presentation, and — the part a plain `@State` can't
/// hold — **which row it belongs to** (issue #264, audit finding F9).
///
/// Share is presented *by the row*, not by the launcher: a popover takes its anchor
/// from the view it is attached to, so the only way to point an arrow at the row the
/// user long-pressed is to hang the presentation off that row. The launcher still
/// resolves the content (only it knows the query and the stores), so the two halves
/// meet here: every row's long-press menu claims the anchor as it runs the verb, the
/// launcher deposits the resolved items, and exactly one row — the claimant — presents.
///
/// It rides the environment rather than a chain of bindings for the same reason the
/// provider-enablement store does: the rows that can spawn a share sit in three
/// different views (the [[Result list]], [[Home]]'s grid and Recents, the [[Shelf]]),
/// all of them reached through the one `resultContextMenu` seam, and threading a
/// binding through each view's parameter list would say nothing that this doesn't.
///
/// **Dismissal is two events, not one**, and keeping them apart is most of this type.
/// The binding SwiftUI drives flips as the dismissal *starts* — the surface is still on
/// screen, still animating out, still showing its content. Only afterwards has it
/// really gone. Collapsing the two costs both halves at once: torn down at the flip,
/// the share sheet **blanks mid-animation** (its items are read from here), and the
/// input's focus is re-armed *behind a live modal*, where UIKit silently drops it. So
/// `beginDismissal()` only stops the presentation, `finishDismissal()` clears it, and
/// the launcher waits for the latter.
@Observable
@MainActor
final class SharePresenter {
    /// The resolved share. It **outlives the dismissal**: the surface renders its items
    /// from here, so clearing it at the flip would empty the sheet while it is still
    /// visible. `finishDismissal()` is what clears it.
    private(set) var request: ShareRequest?

    /// The row whose long-press menu ran the verb — the popover's anchor. A row
    /// presents only while this is its own anchor id, so the same Action appearing
    /// twice on screen (a Favorite card and a Recent row) still presents once.
    private(set) var anchor: UUID?

    /// Whether the surface is on its way out: presented no longer, gone not yet.
    private var isDismissing = false

    /// How many shares have finished. The launcher's cue to release a file share's
    /// access and re-arm the input's focus — bumped once the surface has actually left.
    private(set) var dismissals = 0

    /// The security-scoped access of the share that just ended, parked here for the
    /// launcher to release. The presentation's own teardown can't do it — the access
    /// belongs to `IndexedFoldersStore`, which the row knows nothing about — and the
    /// request is gone by the time the launcher is notified, so it is set aside on the
    /// way out rather than read back off a cleared request.
    private var finishedFileAccess: FileAccess?

    /// Whether a share is being presented *right now* — false the moment one starts
    /// dismissing, which is what tells SwiftUI to take it away.
    var isPresenting: Bool { request != nil && !isDismissing }

    /// Whether the share being presented is `anchor`'s.
    func isPresenting(from anchor: UUID) -> Bool {
        isPresenting && self.anchor == anchor
    }

    /// Claims the anchor for a row that is about to run a secondary verb. Called for
    /// every verb, not just Share: the claim is "this is the row the user pressed",
    /// which is true whichever item the menu ended on, and cheaper than teaching the
    /// menu which verbs present something.
    func claimAnchor(_ anchor: UUID) {
        self.anchor = anchor
    }

    /// Deposits the resolved share. The anchor claimed a moment earlier decides which
    /// row presents it.
    func present(_ request: ShareRequest) {
        self.request = request
        isDismissing = false
    }

    /// The surface is going away — driven by the presentation binding, so this runs
    /// while it is still on screen. It stops the presentation and nothing else; the
    /// content stays intact so the surface has something to animate out.
    func beginDismissal() {
        guard request != nil else { return }
        isDismissing = true
    }

    /// The surface has gone. Clears the share, sets its file access aside for the
    /// launcher, and rings the bell the launcher re-arms the input's focus on.
    ///
    /// It is also the *only* teardown, which covers the case where the binding never
    /// flipped at all: a row removed under a live popover (a foreground re-index
    /// re-ranking the list) takes the presentation with it, and without this the
    /// request would be stranded — the launcher believing something is still presented,
    /// and a file share's access never released.
    func finishDismissal() {
        guard request != nil else { return }
        finishedFileAccess = request?.fileAccess
        request = nil
        anchor = nil
        isDismissing = false
        dismissals += 1
    }

    /// The file access of the share that just ended, handed over exactly once so a
    /// second read can't double-release the start/stop bracket (ADR 0015).
    func takeFinishedFileAccess() -> FileAccess? {
        defer { finishedFileAccess = nil }
        return finishedFileAccess
    }
}

extension View {
    /// Presents the launcher's pending **Share** on this row, when this row is the one
    /// that spawned it: a popover with its arrow in the row at regular width, the sheet
    /// that ships today at compact (`SharePresentation`).
    ///
    /// Applied inside `resultContextMenu`, so every surface whose rows carry the
    /// long-press menu gets it without knowing it exists.
    func sharePresentation(anchoredTo anchor: UUID) -> some View {
        modifier(RowSharePresentation(anchor: anchor))
    }
}

/// The row-side half of the Share presentation: the two surfaces a row can raise, each
/// live only while the pending share is this row's *and* its own shape is the one the
/// window calls for.
private struct RowSharePresentation: ViewModifier {
    let anchor: UUID

    @Environment(SharePresenter.self) private var presenter
    /// The window's width class, mapped through the launcher's single mapping so this
    /// and the readable command column can never disagree about the same window.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var style: SharePresentation.Style {
        SharePresentation.style(for: .init(horizontalSizeClass))
    }

    func body(content: Content) -> some View {
        content
            // `.rect(.bounds)` is the whole point: the arrow lands on *this* row's
            // frame, wherever the row currently is, with no coordinate space to keep in
            // step and nothing to recompute while the list scrolls under it.
            .popover(
                isPresented: presented(as: .popoverAnchoredToRow),
                attachmentAnchor: .rect(.bounds)
            ) {
                shareSurface
                    // A `UIActivityViewController` has no SwiftUI ideal size, so an
                    // unsized popover collapses to nothing.
                    .frame(
                        width: SharePresentation.popoverSize.width,
                        height: SharePresentation.popoverSize.height
                    )
                    // A popover has no `onDismiss`; its content leaving the hierarchy
                    // is the nearest thing to one — and it *is* the right moment,
                    // because the content outlives the binding's flip.
                    .onDisappear { presenter.finishDismissal() }
            }
            // Compact keeps the presentation that ships today, down to the modifier:
            // letting the popover adapt into a sheet would look the same and behave
            // differently, because the adapted sheet carries no `onDismiss` — the one
            // hook that fires after the sheet has left, which is the only moment the
            // input's focus can be re-armed and stick.
            //
            // Both surfaces are attached unconditionally, and each binding tests the
            // window's shape itself. Branching in `body` instead would make the row a
            // `_ConditionalContent`, so a Split View drag across the compact/regular
            // boundary would tear the row's whole subtree down and rebuild it — the one
            // thing ADR 0039 asks not happen while a window is being resized.
            .sheet(
                isPresented: presented(as: .sheet),
                onDismiss: { presenter.finishDismissal() }
            ) {
                shareSurface
                    .ignoresSafeArea()
            }
    }

    /// Presented when the pending share is this row's *and* `wanted` is the shape this
    /// window takes — so exactly one of the two surfaces can ever be up. The setter is
    /// the flip, not the departure, so it only stops the presentation.
    private func presented(as wanted: SharePresentation.Style) -> Binding<Bool> {
        Binding(
            get: { style == wanted && presenter.isPresenting(from: anchor) },
            set: { presented in if !presented { presenter.beginDismissal() } }
        )
    }

    /// The share sheet itself, rendered from the request the presenter holds open
    /// across the dismissal so the surface never animates out empty.
    @ViewBuilder
    private var shareSurface: some View {
        if let request = presenter.request {
            ShareSheet(items: request.items)
        }
    }
}

/// Presents the iOS share sheet (`UIActivityViewController`) for a **Share**
/// secondary action — the App edge that performs the verb Core only declared
/// eligible (ADR 0017).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
