import XCTest
@testable import QuickieCore

/// How the **Share** secondary action presents (CONTEXT.md → Secondary action; ADR
/// 0017; issue #264, audit finding F9): a popover pointing at the row that spawned it
/// on a regular-width window, the sheet it has always been on a compact one.
final class SharePresentationTests: XCTestCase {

    /// The iPad-native shape for a transient action on a *specific* row: a popover
    /// anchored to it, so the sheet's "which row was that again?" question never
    /// comes up.
    func testRegularWidthAnchorsThePopoverToTheRow() {
        XCTAssertEqual(SharePresentation.style(for: .regular), .popoverAnchoredToRow)
    }

    /// Compact is unchanged — the iPhone (and a half-screen iPad) keeps the sheet
    /// that ships today. A popover on a phone-sized window is a sheet anyway, and
    /// saying so here is what keeps the App from sizing one like a popover.
    func testCompactWidthKeepsTheSheet() {
        XCTAssertEqual(SharePresentation.style(for: .compact), .sheet)
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
