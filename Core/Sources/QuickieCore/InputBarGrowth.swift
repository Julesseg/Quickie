import Foundation

/// The single bottom search input's grow-and-wrap behaviour as a pure, testable
/// decision (issue #63). The bar starts as a one-line Liquid Glass Capsule anchored
/// just above the keyboard; as the typed text outgrows one line it wraps and grows
/// *upward* (the bottom edge stays put), and its glass surface squares off from a
/// Capsule into a RoundedRectangle whose ends stay as round as the capsule's. Growth
/// caps at `maxLines`, after which the field scrolls internally rather than eating
/// the screen. Only the main search input wraps; the capture breadcrumb stays
/// single-line.
///
/// SwiftUI types never reach Core, so this maps to a concrete shape at the App edge:
/// the App feeds the field's measured content height and the font's single-line
/// height, and reads back whether the surface is expanded and what radius to use.
public struct InputBarGrowth: Equatable, Sendable {
    /// The most lines the field grows to before it scrolls internally instead of
    /// growing further — the `lineLimit(1...maxLines)` cap.
    public static let maxLines = 5

    /// The fixed one-line bar height — the capsule's height, which the corner radius
    /// derives from so the box's ends match the capsule exactly.
    public let barHeight: CGFloat

    public init(barHeight: CGFloat) {
        self.barHeight = barHeight
    }

    /// The corner radius of the expanded multi-line box — half the one-line bar
    /// height, so its ends stay exactly as round as the single-line capsule's.
    public var cornerRadius: CGFloat { barHeight / 2 }

    /// Whether the field has wrapped past one line, given the text's natural
    /// (unclamped) content height and the font's single-line height. Expanded once
    /// the content clears 1.5 line-heights — safely between one line and two — so a
    /// hair of measurement slack never flips the shape while still on one line.
    public func isExpanded(contentHeight: CGFloat, lineHeight: CGFloat) -> Bool {
        contentHeight > lineHeight * 1.5
    }
}
