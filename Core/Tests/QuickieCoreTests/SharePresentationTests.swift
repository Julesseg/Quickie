import XCTest
@testable import QuickieCore

/// How the **Share** secondary action presents (CONTEXT.md → Secondary action; ADR
/// 0017; issue #264, audit finding F9): a popover pointing at the row that spawned it
/// on a regular-width window, the sheet it has always been on a compact one.
final class SharePresentationTests: XCTestCase {

    /// Room enough for the popover the launcher asks for.
    private let ample = SharePresentation.minimumPopoverRoom + 1

    /// The iPad-native shape for a transient action on a *specific* row: a popover
    /// anchored to it, so the sheet's "which row was that again?" question never
    /// comes up.
    func testRegularWidthAnchorsThePopoverToTheRow() {
        XCTAssertEqual(
            SharePresentation.style(for: .regular, roomFor: ample),
            .popoverAnchoredToRow
        )
    }

    /// Compact is unchanged — the iPhone (and a half-screen iPad) keeps the sheet
    /// that ships today. A popover on a phone-sized window is a sheet anyway, and
    /// saying so here is what keeps the App from sizing one like a popover.
    func testCompactWidthKeepsTheSheet() {
        XCTAssertEqual(SharePresentation.style(for: .compact, roomFor: ample), .sheet)
    }

    // MARK: - Room

    /// A regular-width window with no room for the popover takes the sheet instead.
    ///
    /// This is the landscape iPad with the keyboard up, and the short Stage Manager
    /// tile: the launcher's content area is a few hundred points tall, and a popover
    /// squeezed into it does not scroll — the iOS share sheet **drops** its action
    /// list rather than making it reachable, leaving a header and an app row. A sheet
    /// is always usable, and it is what shipped at regular width before the popover
    /// existed, so the fallback can only be an improvement on the cramped case.
    func testRegularWidthWithoutRoomFallsBackToTheSheet() {
        XCTAssertEqual(
            SharePresentation.style(for: .regular, roomFor: SharePresentation.minimumPopoverRoom - 1),
            .sheet
        )
    }

    /// Exactly enough room is enough — the threshold is inclusive, so the boundary
    /// case is stated rather than left to whichever comparison was typed.
    func testExactlyEnoughRoomStillGetsThePopover() {
        XCTAssertEqual(
            SharePresentation.style(for: .regular, roomFor: SharePresentation.minimumPopoverRoom),
            .popoverAnchoredToRow
        )
    }

    /// The room a popover needs is the height it asks for plus the margins the system
    /// keeps around it — never less than the popover itself, or the fallback would let
    /// through the very squeeze it exists to catch.
    func testTheRoomThresholdCoversTheWholePopover() {
        XCTAssertGreaterThan(
            SharePresentation.minimumPopoverRoom,
            SharePresentation.popoverSize.height
        )
    }

    /// An unmeasured window — the launcher has not laid out yet — takes the sheet, the
    /// presentation that is never wrong.
    func testAnUnmeasuredWindowTakesTheSheet() {
        XCTAssertEqual(SharePresentation.style(for: .regular, roomFor: 0), .sheet)
    }

    /// The popover carries an explicit content size because the thing inside it is a
    /// `UIActivityViewController` — a UIKit controller with no SwiftUI ideal size, so
    /// an unsized popover collapses. The number is pinned here rather than beside the
    /// view so a change to it is a deliberate edit.
    func testThePopoverHasAnExplicitContentSize() {
        XCTAssertEqual(SharePresentation.popoverSize.width, 375)
        XCTAssertEqual(SharePresentation.popoverSize.height, 480)
    }

    /// The popover fits inside the readable command column it is anchored into: a
    /// popover wider than the rows it points at would overhang the column on both
    /// sides and stop reading as *this* row's.
    func testThePopoverIsNarrowerThanTheColumnItPointsInto() {
        XCTAssertLessThan(SharePresentation.popoverSize.width, CommandColumn.readableWidth)
    }
}
