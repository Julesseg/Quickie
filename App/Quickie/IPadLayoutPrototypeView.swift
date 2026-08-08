import SwiftUI

// PROTOTYPE — THROWAWAY. iPad-native layout explorations for the launcher.
//
// Three variants of the launcher's iPad layout, switchable via the floating
// bottom-trailing pill (or seeded with `-ipad-prototype A|B|C`). Mock data,
// no engine, no persistence — the question is "what should the launcher look
// like on iPad?", nothing else. Delete this file once a direction is picked.
//
//  A — Centered column: today's phone layout constrained to a comfortable
//      column width, everything else unchanged.
//  B — Split panes: persistent two-pane layout — input + results live in a
//      left rail, Favorites/recents become a browsable right-side canvas.
//  C — Command palette: Spotlight/Raycast-style floating card over a dimmed
//      backdrop, input on TOP of the card, results below it.
struct IPadLayoutPrototypeView: View {
    enum Variant: String, CaseIterable {
        case a = "A", b = "B", c = "C"
        var title: String {
            switch self {
            case .a: "Centered column"
            case .b: "Split panes"
            case .c: "Command palette"
            }
        }
    }

    @State private var variant: Variant
    @State private var query = ""

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-ipad-prototype"), i + 1 < args.count,
           let seeded = Variant(rawValue: args[i + 1].uppercased()) {
            _variant = State(initialValue: seeded)
        } else {
            _variant = State(initialValue: .a)
        }
    }

    var body: some View {
        ZStack {
            backdrop
            switch variant {
            case .a: CenteredColumnVariant(query: $query)
            case .b: SplitPanesVariant(query: $query)
            case .c: CommandPaletteVariant(query: $query)
            }
            switcher
        }
    }

    private var backdrop: some View {
        RadialGradient(
            colors: [Color(red: 0.72, green: 0.66, blue: 0.92), Color(red: 0.82, green: 0.78, blue: 0.95)],
            center: .center, startRadius: 80, endRadius: 900
        )
        .ignoresSafeArea()
    }

    private var switcher: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
                    Text("\(variant.rawValue) — \(variant.title)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                    Button { cycle(1) } label: { Image(systemName: "chevron.right") }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.8), in: Capsule())
                .foregroundStyle(.white)
                .padding(20)
            }
        }
    }

    private func cycle(_ delta: Int) {
        let all = Variant.allCases
        let i = all.firstIndex(of: variant)!
        variant = all[(i + delta + all.count) % all.count]
    }
}

// MARK: - Mock data

private struct MockRow: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
}

private let mockFavorites: [MockRow] = [
    MockRow(icon: "magnifyingglass", title: "Web search", subtitle: "Custom Action", tint: .purple),
    MockRow(icon: "checklist", title: "New Reminder", subtitle: "Quick capture", tint: .orange),
    MockRow(icon: "calendar.badge.plus", title: "New Event", subtitle: "Quick capture", tint: .red),
    MockRow(icon: "tray.and.arrow.down", title: "Save for later", subtitle: "Pile", tint: .indigo),
]

private let mockRecents: [MockRow] = [
    MockRow(icon: "doc.text", title: "Q3-planning.md", subtitle: "Indexed Folder · Notes", tint: .gray),
    MockRow(icon: "scissors", title: "Standup summary", subtitle: "Snippet", tint: .teal),
    MockRow(icon: "bolt.fill", title: "Log water", subtitle: "Shortcut", tint: .yellow),
    MockRow(icon: "link", title: "Open dashboard", subtitle: "Custom Action · Link", tint: .blue),
    MockRow(icon: "tray.full", title: "Call the dentist about…", subtitle: "Pile · 2 days ago", tint: .indigo),
    MockRow(icon: "doc.text", title: "invoice-2026-07.pdf", subtitle: "Indexed Folder · Documents", tint: .gray),
]

// MARK: - Shared pieces

private struct MockResultRow: View {
    let row: MockRow
    var highlighted = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.icon)
                .font(.body.weight(.medium))
                .foregroundStyle(row.tint)
                .frame(width: 34, height: 34)
                .background(row.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(.body, design: .rounded).weight(.medium))
                Text(row.subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if highlighted {
                Image(systemName: "return")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            highlighted ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

private struct MockFavoriteCard: View {
    let row: MockRow
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 14 : 8) {
            Image(systemName: row.icon)
                .font(large ? .title2.weight(.medium) : .body.weight(.medium))
                .foregroundStyle(row.tint)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(large ? .title3 : .subheadline, design: .rounded).weight(.semibold))
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(large ? 18 : 14)
        .frame(maxWidth: .infinity, minHeight: large ? 130 : 92, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MockInputCapsule: View {
    @Binding var query: String
    var placeholder = "Type to search…"

    var body: some View {
        TextField(placeholder, text: $query)
            .textFieldStyle(.plain)
            .font(.system(.title3, design: .rounded))
            .padding(.horizontal, 20)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}

private func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 4)
}

// MARK: - Variant A — Centered column

/// Today's phone layout, constrained to a ~620pt centered column. The cheapest
/// possible iPad adaptation: nothing moves, the content just stops stretching.
private struct CenteredColumnVariant: View {
    @Binding var query: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Favorites")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(mockFavorites) { MockFavoriteCard(row: $0) }
                }
            }
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("Recent")
                ForEach(mockRecents.prefix(5)) { MockResultRow(row: $0) }
            }
            .padding(.bottom, 12)

            MockInputCapsule(query: $query)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Variant B — Split panes

/// A persistent two-pane layout: the loop (input → results) lives in a fixed
/// left rail, and the freed right side becomes a browsable canvas — big
/// Favorites cards and the Pile at a glance, no typing needed to reach them.
private struct SplitPanesVariant: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Recent")
                    ForEach(mockRecents.prefix(5).reversed().enumerated().map { $0 }, id: \.element.id) { index, row in
                        MockResultRow(row: row, highlighted: index == 4)
                    }
                }
                .padding(.bottom, 12)
                MockInputCapsule(query: $query)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .frame(width: 420)
            .background(.ultraThinMaterial)

            Divider().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Favorites")
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                            spacing: 14
                        ) {
                            ForEach(mockFavorites) { MockFavoriteCard(row: $0, large: true) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Pile")
                        VStack(spacing: 2) {
                            ForEach(mockRecents.suffix(3)) { MockResultRow(row: $0) }
                        }
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(28)
            }
        }
    }
}

// MARK: - Variant C — Command palette

/// Spotlight/Raycast-style: the launcher is a floating card in the upper third
/// of a dimmed screen. Input moves to the TOP of the card (macOS reading order,
/// natural with a hardware keyboard), results drop below it inside the card.
private struct CommandPaletteVariant: View {
    @Binding var query: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 0) {
                MockInputCapsule(query: $query, placeholder: "Quickie — type to search…")
                    .padding(14)
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Favorites")
                        .padding(.top, 10)
                    ForEach(mockFavorites.prefix(2)) { MockResultRow(row: $0) }
                    sectionLabel("Recent")
                        .padding(.top, 10)
                    ForEach(Array(mockRecents.prefix(4).enumerated()), id: \.element.id) { index, row in
                        MockResultRow(row: row, highlighted: index == 0)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .frame(width: 660)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 120)
        }
    }
}
