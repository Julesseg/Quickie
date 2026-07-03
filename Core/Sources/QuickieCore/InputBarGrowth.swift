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
    /// (unclamped) content height, the font's single-line height, and whether the
    /// surface is *currently* expanded.
    ///
    /// The decision is **hysteretic** — two thresholds, not one (issue #80). A
    /// `TextField(axis: .vertical)` reports jittery, transient content heights while
    /// its text reflows under rapid typing/backspace; a single threshold lets a
    /// height hovering right at the wrap boundary flip the glass surface
    /// Capsule↔box on *every* measurement, and each flip fires an expensive Liquid
    /// Glass morph. That burst of morphs stalls the main runloop — the intermittent
    /// hang-then-kill when a ~30-char staged Pile query is backspaced down past
    /// empty ("Unable to monitor event loop"). The dead band between the two
    /// thresholds absorbs the wobble:
    ///
    /// - A collapsed capsule expands only once the content clears **1.5**
    ///   line-heights — safely between one line and two, so a hair of measurement
    ///   slack never squares it off while still on one line.
    /// - An expanded box collapses only once the content drops back below **1.25**
    ///   line-heights — clearly a single line again. In between it holds its shape.
    ///
    /// The shape still tracks reality (two full lines expand, one full line
    /// collapses); it just refuses to flip on boundary noise.
    public func isExpanded(contentHeight: CGFloat, lineHeight: CGFloat, wasExpanded: Bool) -> Bool {
        let threshold = wasExpanded ? lineHeight * 1.25 : lineHeight * 1.5
        return contentHeight > threshold
    }
}
