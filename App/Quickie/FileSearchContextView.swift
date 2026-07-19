import SwiftUI
import QuickieCore

/// The **Search Files context** made visible (CONTEXT.md → Search Files context;
/// ADR 0014): the scoped, uncapped file-browsing surface entered by *selecting* the
/// "Search Files" command row — never a mode toggle. It borrows the capture
/// breadcrumb's presentation (a `[Search Files] ▸ …` crumb up top) but is its own
/// thing: a live scoped filter over the filename index, not an Argument slot that
/// commits a value. Every keystroke filters only filenames; the list is full-height
/// and uncapped, so weak matches the inline root list holds back appear here too.

// MARK: - Breadcrumb

/// The breadcrumb riding the top of the screen while the context is active: the
/// "Search Files" title over a `[Search Files] ▸ <filter>` crumb row, on the same
/// progressive-blur band the capture breadcrumb uses, with a × to dismiss back to
/// normal results.
struct FileSearchBreadcrumbBar: View {
    /// The live filter text, echoed into the crumb so the breadcrumb reads as the
    /// ongoing scoped query.
    let query: String
    var onDismiss: () -> Void

    private var filterText: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "All files" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Search Files")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Close Search Files")
                .accessibilityIdentifier("file-search-cancel")
            }
            HStack(spacing: 6) {
                crumb("Search Files", isScope: true)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                crumb(filterText, isScope: false)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .statusBarBleed(topPadding: 6) { FileSearchBlur() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("file-search-breadcrumb")
    }

    /// One crumb: the fixed `[Search Files]` scope pill (accent-tinted, like a
    /// current capture step) or the live filter value beside it.
    private func crumb(_ text: String, isScope: Bool) -> some View {
        Text(text)
            .font(.subheadline.weight(isScope ? .semibold : .regular))
            .foregroundStyle(isScope ? .primary : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(
                isScope ? .regular.tint(.accentColor.opacity(0.4)) : .regular,
                in: RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous)
            )
    }
}

/// The progressive blur the top breadcrumb floats on — solid near the crumb,
/// fading clear up under the status area so content scrolls cleanly beneath it.
/// A local twin of the capture bar's blur (kept private there) so the two surfaces
/// read identically without coupling.
private struct FileSearchBlur: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

// MARK: - Result list

/// The reversed, bottom-anchored list of file matches for the context — the same
/// shape as the root Result list (best match nearest the thumb) but scoped to file
/// rows and without the Favorite pin menu, since a dynamic file result isn't a
/// pinnable catalog entry. The highlighted row (`results[0]`) reads as the default
/// so Enter opens it.
struct FileSearchResultList: View {
    let results: [Action]
    let onRun: (Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rowMotion: MotionStyle {
        MotionPolicy(reduceMotion: reduceMotion).style(for: .rowInsert)
    }

    var body: some View {
        // Bottom-pinned exactly like the root Result list: the min-height frame
        // anchors every slot to the viewport's bottom edge, so a slot animating in
        // or out at the weak (top) end cannot shift the rows beneath it.
        GeometryReader { viewport in
            ScrollView {
                GlassEffectContainer(spacing: 6) {
                    VStack(spacing: 6) {
                        // Rank-keyed slots, exactly like the root Result list: a
                        // keystroke that re-filters swaps content in place, and only
                        // a change in count animates a slot in or out — via the
                        // transition's own animation, never the surrounding layout.
                        ForEach(results.indices.reversed(), id: \.self) { rank in
                            let action = results[rank]
                            Button {
                                onRun(action)
                            } label: {
                                ActionRow(action: action, isHighlighted: rank == 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(action.id)
                            .transition(rowMotion.insertionTransition)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .bottom)
            }
            .defaultScrollAnchor(.bottom)
        }
    }
}
