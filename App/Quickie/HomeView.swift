import SwiftUI
import UIKit
import QuickieCore

/// The empty-query Home state (CONTEXT.md → Home): a 2×2 **Favorites grid** (at
/// most four) pinned at the top over a progressive-blur band, with the **Recent**
/// (Frecency) list scrolling *under* that band. Before the user has pinned or
/// used anything it falls back to the minimal "start typing" placeholder.
struct HomeView: View {
    let content: SearchEngine.HomeContent
    let onRun: (Action) -> Void
    let isFavorite: (Action) -> Bool
    var canFavorite: (Action) -> Bool = { _ in true }
    let onToggleFavorite: (Action) -> Void
    /// Runs a one-shot secondary action on a Home row's content (Copy / Share /
    /// Reveal in Files) — the same long-press menu the Result list uses (ADR 0017).
    var onSecondaryAction: (Action, SecondaryActionKind) -> Void = { _, _ in }
    /// Reports whether the Recent list is mid-drag, so the launcher tells a
    /// swipe-dismiss (issue #64) from a context-menu dismissal (issue #58).
    var onScrollActive: (Bool) -> Void = { _ in }

    /// At most four Favorites fill the 2×2 grid (CONTEXT.md → Favorites grid);
    /// extras (which the cap should already prevent) are never shown.
    private var gridFavorites: [Action] { Array(content.favorites.prefix(4)) }

    private var isEmpty: Bool {
        content.favorites.isEmpty && content.frecent.isEmpty
    }

    var body: some View {
        if isEmpty {
            HomePlaceholder()
        } else {
            ZStack(alignment: .top) {
                // The Recent list fills the screen and is bottom-anchored so the
                // most relevant rows sit nearest the thumb; its top rows scroll
                // up under the blurred Favorites band.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if !content.frecent.isEmpty {
                            frecencySection
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Top padding only — the bottom edge stays flush with the
                    // scroll view, exactly like the Result list, so the lowest
                    // Recent row sits the same distance above the input bar as
                    // the highlighted result does.
                    .padding(.top, 16)
                    // Leave room so the first Recent rows aren't born hidden
                    // beneath the pinned grid.
                    .padding(.top, gridFavorites.isEmpty ? 0 : 168)
                }
                .defaultScrollAnchor(.bottom)
                // Swiping down the Recent list dismisses the keyboard interactively
                // (issue #64), the same native scroll-dismiss as the Result list —
                // the bar drops and nothing clears.
                .scrollDismissesKeyboard(.interactively)
                // Report drag state so a swipe-dismiss (drop the bar) is told apart
                // from a context-menu dismissal (hold the layout). Only an active
                // drag counts, not `.tracking` (a long-press's finger-down state).
                .onScrollPhaseChange { _, phase in
                    onScrollActive(phase == .interacting || phase == .decelerating)
                }

                if !gridFavorites.isEmpty {
                    favoritesGrid
                } else {
                    // No grid to carry the blur band, but the Recent list still
                    // scrolls under the status bar — the bare band keeps the
                    // status bar readable over it.
                    StatusBarBlurBand()
                }
            }
        }
    }

    /// The 2×2 Favorites grid, pinned at the top over a progressive-blur band so
    /// the Recent list refracts through it as it scrolls under (ADR 0010).
    private var favoritesGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Favorites")
                .padding(.horizontal, 20)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(gridFavorites) { action in
                    Button {
                        onRun(action)
                    } label: {
                        FavoriteCard(action: action)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("favorite.\(action.id)")
                    .resultContextMenu(
                        secondaryActions: secondaryActions(for: action.content, includeDeeplink: !action.isSilentQueryCapture),
                        onSecondaryAction: { onSecondaryAction(action, $0) },
                        isFavorite: true,
                        toggle: { onToggleFavorite(action) }
                    ) {
                        // Lift a copy of the pressed Favorite card as the detached
                        // preview.
                        FavoriteCard(action: action)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        // The progressive-blur band: a soft material that fades out at its lower
        // edge so the Recent list dissolves under it rather than meeting a hard
        // line (CONTEXT.md → Home; ADR 0010). It bleeds into the status bar as one
        // cohesive frame (`statusBarBleed`) so it slides as a single block with the
        // rest of Home rather than leaving its status-bar band anchored behind.
        .statusBarBleed(topPadding: 12) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.72),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
    }

    /// The Frecency list: recently/often-used Actions, best-first, each a full
    /// row that runs on tap and can be pinned via long-press. The rows render
    /// exactly like the Result list's — the same `GlassEffectContainer` blending
    /// and the same 6pt spacing — so a remembered Action looks identical whether
    /// it appears here or as a ranked result.
    private var frecencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recent")
                .padding(.horizontal, 20)
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 6) {
                    ForEach(content.frecent) { action in
                        Button {
                            onRun(action)
                        } label: {
                            ActionRow(action: action)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(action.id)
                        .resultContextMenu(
                            secondaryActions: secondaryActions(for: action.content, includeDeeplink: !action.isSilentQueryCapture),
                            onSecondaryAction: { onSecondaryAction(action, $0) },
                            isFavorite: isFavorite(action),
                            pinnable: action.isFavoriteEligible,
                            canPin: canFavorite(action),
                            toggle: { onToggleFavorite(action) }
                        ) {
                            // Lift a copy of the pressed Recent row as the detached
                            // preview.
                            ActionRow(action: action)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// One small Favorite card in the 2×2 grid: a glass tile with the Action's
/// provider badge, title, and main-action glyph — the launch-time, tap-without-
/// typing surface.
struct FavoriteCard: View {
    let action: Action

    var body: some View {
        HStack(spacing: 8) {
            // A Custom Action's chosen glyph (issue #163) overrides the derived one;
            // `nil` keeps the derived glyph, so an unset Favorite is unchanged.
            ProviderBadge(kind: action.kind, symbol: action.glyph)
            Text(action.title)
                // Rounded launcher chrome (ADR 0033), same face as the result-row
                // titles so a pinned Action reads identically to its ranked row.
                .font(.system(.callout, design: .rounded).weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            MainActionGlyph(mainAction: action.mainAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: QuickieRadius.card, style: .continuous))
    }
}

/// The minimal pre-anything Home: shown before the user has pinned a Favorite or
/// used any Action. It used to have one job — fill the space above the input —
/// and grew two more, because it is the only screen in the app that is *empty by
/// definition* and therefore the only place with room to say what Quickie is: the
/// **brand mark** above (drawn in the brand ramp, ADR 0033), and the rotating
/// [[Hint line]] below (ADR 0034's enumerated moment).
///
/// Read top to bottom it says who (the mark), what to do ("Start typing"), and
/// what is worth typing (the hint). The three stay separate elements on purpose —
/// the placeholder is the instruction and never changes; only the hint rotates.
struct HomePlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                brandMark
                VStack(spacing: 8) {
                    Text("Start typing")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("home-placeholder")
                    HintLineView()
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// The app icon's orbital Q, in the brand's trail ramp — the same symbol the
    /// widgets and controls render (`QuickieGlyph`), so the mark a user taps on
    /// the Home Screen is the mark that greets them inside.
    ///
    /// A fixed point size rather than a Dynamic Type text style: it is the one
    /// thing here that isn't reading matter, and at accessibility sizes a scaling
    /// mark would push the line it exists to introduce off the screen.
    private var brandMark: some View {
        QuickieGlyph.image
            .font(.system(size: 56))
            .foregroundStyle(QuickieBrand.adaptiveMarkGradient)
            .accessibilityIdentifier("home-brand-mark")
            .accessibilityLabel("Quickie")
    }
}

/// The Home **Hint line** (ADR 0034): one of Core's hints at a time, dissolving
/// slowly into the next so the empty Home teaches Quickie's breadth by suggestion.
///
/// Every timing here is `MotionPolicy`'s (the dwell, the crossfade, and whether the
/// line rotates at all); this view only renders what Core decides and never invents
/// a cadence of its own.
private struct HintLineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let policy = MotionPolicy(reduceMotion: reduceMotion)
        if let dwell = policy.hintDwellUnlessFrozen {
            RotatingHint(dwell: dwell, animation: policy.style(for: .hintRotation).animation)
        } else {
            // Frozen: one hint, held. Deliberately the *same* rendering as the
            // rotating line rather than a stand-in — a Reduce Motion user should
            // see the Hint line, just not the rotation.
            hintText(HintLine().current)
        }
    }
}

/// The rotating form: advances the line on Core's dwell and crossfades between
/// hints.
private struct RotatingHint: View {
    let dwell: Double
    let animation: Animation?
    @State private var line = HintLine()

    var body: some View {
        hintText(line.current)
            // `.task` rather than a `Timer` publisher: it is tied to this view's
            // identity, so a parent re-render can't quietly restart the dwell (a
            // publisher rebuilt in `init` resubscribes and does exactly that), and
            // it cancels itself when Home gives way to the Result list on the first
            // keystroke — the rotation must never outlive the screen that shows it.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(dwell))
                    if Task.isCancelled { return }
                    withAnimation(animation) { line.advance() }
                }
            }
    }
}

/// The Hint line's one rendering, shared by both forms.
///
/// Quieter than the placeholder above it — smaller, same tertiary weight. The
/// hint is a suggestion, not a second instruction, and if it ever competed with
/// "Start typing" for the eye it would be doing the opposite of its job.
///
/// `contentTransition(.opacity)` is what makes the swap a crossfade *in place*:
/// the two hints dissolve through each other on one line, where a transition on
/// an `.id`-keyed `Text` would briefly lay both out and nudge the layout.
@ViewBuilder
private func hintText(_ hint: String) -> some View {
    Text(hint)
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .contentTransition(.opacity)
        // Stable across the rotation: the identifier names the *line*, not the
        // hint currently in it, so a test can wait on the element without racing
        // the copy (the frozen rendering is what lets it assert the text).
        .accessibilityIdentifier("home-hint")
}

// MARK: - Status-bar bleed

extension View {
    /// Lets a top-anchored bar span the status bar as **one cohesive frame**: it
    /// reserves the top safe-area height as the bar's own top padding (so its
    /// content still sits clear of the status bar), paints `background` behind the
    /// whole bar, then ignores the top safe area. Because the bar's frame now spans
    /// from the screen edge down, a `.move(edge: .top)` / `.move(edge: .bottom)`
    /// transition slides it as a single block — rather than bleeding only the
    /// background and leaving that status-bar band anchored behind while the rest
    /// of the content moves (which reads as a half-clip, or a band that won't move).
    func statusBarBleed<Background: View>(
        topPadding: CGFloat,
        @ViewBuilder background: () -> Background
    ) -> some View {
        modifier(StatusBarBleed(topPadding: topPadding, background: background()))
    }
}

private struct StatusBarBleed<Background: View>: ViewModifier {
    var topPadding: CGFloat
    var background: Background

    func body(content: Content) -> some View {
        content
            .padding(.top, topInset + topPadding)
            .background(background)
            .ignoresSafeArea(edges: .top)
    }

    /// The window's top safe-area inset. Read from UIKit because the bar ignores
    /// the top safe area to span the full height — so its own geometry would report
    /// zero — yet must still reserve that height to clear the status bar. Static per
    /// orientation, and `body` re-evaluates on rotation.
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.top ?? 0
    }
}
