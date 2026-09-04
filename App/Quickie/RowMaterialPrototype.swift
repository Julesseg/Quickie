// PROTOTYPE (#286) — THROWAWAY. Lives on `prototype/row-material`, never on main.
//
// The question: what dresses a result row once it is no longer Liquid Glass
// (ADR 0042)? Two independent switches, viewable in any combination:
//
//   Row treatment   -proto-row  bare | flat | material
//   Hero treatment  -proto-hero fill | ring | strong
//
// Both are also cycled from the floating badge at the top of the launcher
// (hidden with `-proto-no-badge` for screenshots). `-proto-seed-query <text>`
// starts the launcher with a query already typed so `simctl launch` +
// `simctl io screenshot` can photograph a state without XCUITest, and
// `-proto-autotype <text>` types it one character at a time so the hero's
// swing-then-settle can be filmed.
//
// Geometry is frozen (ADR 0042): `QuickieRadius.row`, the 6pt gap, the 12pt
// inset and the pointer-hover shape are untouched. Only the material changes.
import SwiftUI
import UIKit
import QuickieCore

enum RowMaterialPrototype {
    enum Row: String, CaseIterable {
        case bare, flat, material

        var label: String {
            switch self {
            case .bare: return "a · Bare + hairline"
            case .flat: return "b · Flat adaptive fill"
            case .material: return "d · System material"
            }
        }
    }

    enum Hero: String, CaseIterable {
        case fill, ring, strong

        var label: String {
            switch self {
            case .fill: return "i · Gold fill + slide"
            case .ring: return "ii · Ring light"
            case .strong: return "iii · Strong fill, no shimmer"
            }
        }
    }

    @Observable @MainActor
    final class State {
        var row: Row
        var hero: Hero

        init(row: Row, hero: Hero) {
            self.row = row
            self.hero = hero
        }

        func cycleRow(_ step: Int) {
            row = Row.allCases[(Row.allCases.firstIndex(of: row)! + step + Row.allCases.count) % Row.allCases.count]
        }

        func cycleHero(_ step: Int) {
            hero = Hero.allCases[(Hero.allCases.firstIndex(of: hero)! + step + Hero.allCases.count) % Hero.allCases.count]
        }
    }

    private static let arguments = ProcessInfo.processInfo.arguments

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    @MainActor static let shared = State(
        row: value(after: "-proto-row").flatMap(Row.init(rawValue:)) ?? .flat,
        hero: value(after: "-proto-hero").flatMap(Hero.init(rawValue:)) ?? .fill
    )

    static let showsBadge = !arguments.contains("-proto-no-badge")
    static let plainMenu = arguments.contains("-proto-plain-menu")
    static let seededQuery = value(after: "-proto-seed-query")
    static let autotypeQuery = value(after: "-proto-autotype")

    // MARK: - Materials

    /// Option (b): an opaque-ish rounded rect on the brand's purple axis (ADR 0033),
    /// one step lighter than the mesh in dark, one step lighter than the wash in
    /// light — a card lifted off the backdrop, with no blur behind it.
    static let flatFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 40 / 255, green: 28 / 255, blue: 78 / 255, alpha: 0.94)
            : UIColor(red: 247 / 255, green: 244 / 255, blue: 255 / 255, alpha: 0.94)
    })

    /// ADR 0034's swing reach, as `HeroGlow` tuned it.
    static let swingAmplitude: CGFloat = 90

    /// Option (a)'s hairline between rows.
    static let hairline = Color.primary.opacity(0.14)
}

// MARK: - The row dress

/// Replaces `ActionRow`'s `.overlay { HeroGlow } .glassEffect(...)` pair: the base
/// material *under* the row's content, the hero light over the material and still
/// under the text (the composition glass used to provide for free), and for the
/// ring treatment a stroke over everything.
struct PrototypeRowDress: ViewModifier {
    let shape: RoundedRectangle
    let isHighlighted: Bool
    let heroID: String

    @Environment(\.displayScale) private var displayScale

    private var state: RowMaterialPrototype.State { RowMaterialPrototype.shared }

    func body(content: Content) -> some View {
        let row = state.row
        let hero = state.hero
        content
            .background {
                ZStack {
                    base(row)
                    if isHighlighted {
                        heroUnderlay(hero)
                    }
                }
                .clipShape(shape)
            }
            .overlay {
                if isHighlighted && hero == .ring {
                    HeroSwing(heroID: heroID) { swing, peak in
                        ringLight(swing: swing, peak: peak)
                    }
                } else if row == .bare && !isHighlighted {
                    // Option (a): no fill, a hairline separator under each row, text
                    // straight on the Living backdrop. Inside the row's own frame so
                    // the 6pt gap and the 12pt inset are exactly what ship today.
                    Rectangle()
                        .fill(RowMaterialPrototype.hairline)
                        .frame(height: 1 / displayScale)
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private func base(_ row: RowMaterialPrototype.Row) -> some View {
        switch row {
        case .bare:
            EmptyView()
        case .flat:
            shape.fill(RowMaterialPrototype.flatFill)
        case .material:
            shape.fill(.regularMaterial)
        }
    }

    @ViewBuilder
    private func heroUnderlay(_ hero: RowMaterialPrototype.Hero) -> some View {
        switch hero {
        case .fill:
            // (i) a gold-tinted fill, with ADR 0034's swing-then-settle kept as a
            // gradient moving *within* the fill.
            shape.fill(QuickieBrand.gold.opacity(0.14))
            HeroSwing(heroID: heroID) { swing, peak in
                RadialGradient(
                    colors: [QuickieBrand.gold.opacity(peak), .clear],
                    center: .center, startRadius: 0, endRadius: 150
                )
                .padding(.horizontal, -RowMaterialPrototype.swingAmplitude)
                .offset(x: swing)
            }
        case .ring:
            // (ii) the light is the ring itself (drawn as an overlay); the fill
            // stays whatever the row treatment gives every other row.
            EmptyView()
        case .strong:
            // (iii) a stronger, static fill and the ⏎ hint the row already wears;
            // nothing moves.
            shape.fill(QuickieBrand.gold.opacity(0.26))
        }
    }

    /// (ii): a gold edge light whose bright point rides the swing.
    private func ringLight(swing: CGFloat, peak: CGFloat) -> some View {
        let bright = QuickieBrand.gold.opacity(min(1, peak * 3))
        let dim = QuickieBrand.gold.opacity(0.35)
        return ZStack {
            // A soft halo just outside the edge, so the ring reads as *light*.
            shape.stroke(QuickieBrand.gold.opacity(peak * 1.5), lineWidth: 5)
                .blur(radius: 5)
            LinearGradient(colors: [dim, bright, dim], startPoint: .leading, endPoint: .trailing)
                .padding(.horizontal, -RowMaterialPrototype.swingAmplitude)
                .offset(x: swing)
                .mask { shape.strokeBorder(lineWidth: 1.5) }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The swing driver

/// `HeroGlow`'s announce cycle (ADR 0034: glide to an extreme, swing across, ease
/// back to centre about a second in), lifted out of the glow so each hero
/// treatment can render the same timing its own way. Degrades exactly as before:
/// static and centred under Reduce Motion and UI test.
struct HeroSwing<Content: View>: View {
    let heroID: String
    let content: (_ swing: CGFloat, _ peak: CGFloat) -> Content

    init(heroID: String, @ViewBuilder content: @escaping (_ swing: CGFloat, _ peak: CGFloat) -> Content) {
        self.heroID = heroID
        self.content = content
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swing: CGFloat = 0
    @State private var peak: CGFloat = 0.2
    @State private var settleTask: Task<Void, Never>?
    @State private var startTask: Task<Void, Never>?

    private var animates: Bool { !reduceMotion && !MotionStyle.isInstantForUITesting }

    var body: some View {
        content(swing, peak)
            .allowsHitTesting(false)
            .onAppear { stir() }
            .onChange(of: heroID) { _, _ in restart() }
            .onDisappear { settleTask?.cancel(); startTask?.cancel() }
    }

    private func restart() {
        guard animates else { return }
        startTask?.cancel()
        settleTask?.cancel()
        stir()
    }

    private func stir() {
        guard animates else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            swing = -RowMaterialPrototype.swingAmplitude
            peak = 0.32
        }
        startTask?.cancel()
        startTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                swing = RowMaterialPrototype.swingAmplitude
            }
        }
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 1.0)) {
                swing = 0
                peak = 0.2
            }
        }
    }
}

// MARK: - The badge and the autotyper

/// The floating switcher: two rows of ◀ label ▶, one per axis. Deliberately
/// *not* part of the design under evaluation — a high-contrast pill that could
/// never be mistaken for chrome.
struct RowMaterialPrototypeDriver: View {
    @Binding var query: String

    private var state: RowMaterialPrototype.State { RowMaterialPrototype.shared }

    var body: some View {
        VStack(spacing: 6) {
            if RowMaterialPrototype.showsBadge {
                axis("Row", state.row.label, back: { state.cycleRow(-1) }, forward: { state.cycleRow(1) })
                    .accessibilityIdentifier("proto-row")
                axis("Hero", state.hero.label, back: { state.cycleHero(-1) }, forward: { state.cycleHero(1) })
                    .accessibilityIdentifier("proto-hero")
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            guard let text = RowMaterialPrototype.autotypeQuery else { return }
            try? await Task.sleep(for: .seconds(2))
            for end in text.indices {
                query = String(text[...end])
                try? await Task.sleep(for: .milliseconds(220))
            }
        }
    }

    private func axis(_ name: String, _ label: String, back: @escaping () -> Void, forward: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.caption2.weight(.bold)).foregroundStyle(.yellow)
            Button(action: back) { Image(systemName: "chevron.left") }
            Text(label).font(.caption.monospaced()).lineLimit(1)
            Button(action: forward) { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.85)))
    }
}
