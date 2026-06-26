import SwiftUI
import QuickieCore

/// The reversed, bottom-anchored Result list (ADR 0008): the best match sits
/// nearest the input and the thumb, with weaker matches stacking upward and
/// scrolling away. We reverse the ranked array so rank 0 renders last (lowest),
/// and anchor the scroll view to the bottom so it opens at the best match.
struct ResultListView: View {
    let results: [Action]
    let onRun: (Action) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(results.reversed()) { action in
                    Button {
                        onRun(action)
                    } label: {
                        ResultRow(action: action)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(action.id)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
    }
}

/// One row: the Action presented by its main action (title + optional subtitle).
private struct ResultRow: View {
    let action: Action

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
