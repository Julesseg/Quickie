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
                    .padding(.vertical, 16)
                    // Leave room so the first Recent rows aren't born hidden
                    // beneath the pinned grid.
                    .padding(.top, gridFavorites.isEmpty ? 0 : 168)
                }
                .defaultScrollAnchor(.bottom)

                if !gridFavorites.isEmpty {
                    favoritesGrid
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
                    .favoriteContextMenu(isFavorite: true) { onToggleFavorite(action) }
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
    /// row that runs on tap and can be pinned via long-press.
    private var frecencySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Recent")
                .padding(.horizontal, 20)
            ForEach(content.frecent) { action in
                Button {
                    onRun(action)
                } label: {
                    ActionRow(action: action)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(action.id)
                .favoriteContextMenu(
                    isFavorite: isFavorite(action),
                    canPin: canFavorite(action)
                ) { onToggleFavorite(action) }
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
            ProviderBadge(kind: action.kind)
            Text(action.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            MainActionGlyph(mainAction: action.mainAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The minimal pre-anything Home: shown before the user has pinned a Favorite or
/// used any Action, its only job is to fill the space above the input.
struct HomePlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Start typing")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("home-placeholder")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
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
