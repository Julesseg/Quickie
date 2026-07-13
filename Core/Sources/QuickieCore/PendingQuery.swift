import Foundation

/// A **Pending query** (CONTEXT.md → Pending query; issue #152; ADR 0031):
/// unresolved input the user left in the root launcher when the app
/// backgrounded, snapshotted as `(text?, timestamp)` and resolved at the next
/// activation by how and when they come back. No path silently destroys typed
/// text while the feature is on:
///
/// - a **plain open** (icon / switcher / Live Activity tap) within the window
///   restores it — still mid-thought;
/// - a plain open at or past the window commits it to the Pile — moved on;
/// - an **Entry surface** (widget, control, bridged run, `quickie://entry`)
///   commits it immediately at any age — "something new *now*".
///
/// Only a plain root-launcher query carries text: a half-filled breadcrumb and
/// the Search Files context still snapshot (their state resets after the
/// window) but save nothing — the Pile holds raw query texts only. The
/// mechanism is timestamp comparison at activation, never a background timer,
/// so termination loses nothing and a never-reopened app commits on next open.
public struct PendingQuery: Equatable, Codable, Sendable {
    /// The qualifying plain query, or `nil` when the backgrounded state was a
    /// scoped context (breadcrumb, Search Files) or an empty input — the window
    /// still resets it, but nothing is written to the Pile.
    public var text: String?
    /// When the app backgrounded — what the next activation compares against.
    public var backgroundedAt: Date

    public init(text: String?, backgroundedAt: Date) {
        self.text = text
        self.backgroundedAt = backgroundedAt
    }

    /// The window inside which a plain return restores the query — a fixed
    /// constant (the Pile toggle's copy states it; there is no stepper).
    public static let lifetime: TimeInterval = 30

    /// The snapshot to persist at background time, or `nil` when the feature is
    /// off (today's behavior exactly: state preserved indefinitely, nothing
    /// saved, no Live Activity). Text rides along only for a plain, non-empty
    /// root query — the qualification the Live Activity shares, so "Quickie
    /// keeps your unfinished query" stays one mental model.
    public static func snapshot(
        query: String,
        isCapturing: Bool,
        inFileSearch: Bool,
        autoSaveEnabled: Bool,
        at date: Date = Date()
    ) -> PendingQuery? {
        guard autoSaveEnabled else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualifies = !trimmed.isEmpty && !isCapturing && !inFileSearch
        return PendingQuery(text: qualifies ? query : nil, backgroundedAt: date)
    }

    /// Decides the snapshot's fate at the next activation. A backwards-moving
    /// clock reads as within the window: restoring on a skewed clock is
    /// harmless, destroying typed text is not.
    public func resolution(at now: Date, via path: PendingQueryReturn) -> PendingQueryResolution {
        switch path {
        case .entrySurface:
            return .reset(commit: text)
        case .plainOpen:
            return now.timeIntervalSince(backgroundedAt) < Self.lifetime
                ? .keep
                : .reset(commit: text)
        }
    }

    /// The confirmation flash for an auto-save — the existing flash-confirmation
    /// idiom with a truncated preview of the saved text: quotes the first line,
    /// capped, so a multi-line or pasted blob still reads as one short toast.
    public static func savedConfirmation(for text: String) -> String {
        let cap = 24
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        // Ellipsis only when content was actually dropped — a truncation or a
        // further line — so a trailing space alone never fakes one.
        let truncated = firstLine.count > cap
            || firstLine != text.trimmingCharacters(in: .whitespacesAndNewlines)
            ? String(firstLine.prefix(cap)) + "…"
            : firstLine
        return "Saved “\(truncated)” for later"
    }

    // MARK: App Group codec

    /// Encodes the snapshot for the App Group defaults blob the app writes at
    /// background time and reads back at activation.
    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Decodes a persisted snapshot; `nil` for a missing or unreadable blob —
    /// which reads as "nothing pending", never an error.
    public static func decode(_ data: Data?) -> PendingQuery? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PendingQuery.self, from: data)
    }
}

/// How the user came back to the app — what resolves a Pending query.
public enum PendingQueryReturn: Sendable {
    /// The app icon, the app switcher, or a Live Activity tap: icon-equivalent,
    /// so the window decides between restore and commit.
    case plainOpen
    /// Any Entry surface (CONTEXT.md → Entry surface) — `quickie://entry`, a
    /// widget or control button, a Bridged Action run: "something new *now*",
    /// committing the pending text at any age.
    case entrySurface
}

/// What the activation does with the snapshot.
public enum PendingQueryResolution: Equatable, Sendable {
    /// Within the window via a plain open: leave warm state untouched, restore
    /// the text into a cold launch's input.
    case keep
    /// Reset the scoped state back to a clean Home, committing `commit` to the
    /// Pile when non-nil (with the confirmation flash, no Frecency credit, no
    /// dedupe).
    case reset(commit: String?)
}
