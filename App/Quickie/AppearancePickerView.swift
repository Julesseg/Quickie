import SwiftUI
import QuickieCore

/// The merged **Symbol & Color page** (CONTEXT.md → Custom Action, Action color;
/// issues #163, #243) — one pushed page for the whole appearance, shared by every
/// surface that lets a user customize an Action's badge. Originally the Custom
/// Action editor's own private view; pulled out so the Shortcuts page's own
/// appearance row (issues #163, #243) pushes the *same* page rather than a second
/// one that could drift from it — a symbol-and-colour picker is not specific to
/// how an action is authored, only to the fact that it wears a badge.
///
/// The hero is the **composed result**: the same `ProviderBadge` every surface draws,
/// at the same proportions, restyling live as you tap. That is the point of merging
/// them — a symbol and a colour are only ever seen together, so choosing them apart
/// meant judging each against an imagined version of the other. Here the answer to
/// "how will this look?" is on screen the whole time.
///
/// The hero and the colour row are **pinned**; only the glyph gallery scrolls. A hero
/// that scrolled away would be a preview you cannot see while making the choice it
/// previews. Back confirms — there is no auto-dismiss on tap, so a wrong tap is
/// corrected by tapping again rather than by re-opening the page.
struct AppearancePickerView: View {
    /// The stored glyph, bound straight to the caller's model — `CustomActionDefinition
    /// .glyph` from the editor, a `ShortcutsStore` write from the Shortcuts page. Only
    /// ever written here as `nil` or a catalog symbol name, never a blank string.
    @Binding var glyph: String?
    /// The stored colour token, bound the same way as `glyph`.
    @Binding var color: ActionColor?
    /// The kind the badge composes over — the shape-derived tint behind a Default
    /// colour, so the hero matches what the action will actually wear.
    let kind: ActionKind

    /// The glyph gallery's fuzzy query, ranked by the same `Matcher` furniture the
    /// choice input method uses, so the gallery reads best-match-first exactly as a
    /// breadcrumb choice step does.
    @State private var query = ""

    /// Whether the search field holds the keyboard — half of what puts the header into
    /// its compact form.
    @FocusState private var searchFocused: Bool

    /// Whether the header collapses to its compact form. Keyed to the **keyboard**, not
    /// to the query: the keyboard claims roughly half a small screen, and a full-height
    /// header above it left literally no gallery visible on an iPhone SE — you could
    /// type a query and never see, let alone tap, a result. While the keyboard is up the
    /// hero shrinks to an inline chip and the swatches step aside (the user is choosing a
    /// *symbol* at that moment; the preview only has to stay legible, not large).
    ///
    /// Deliberately not `|| !query.isEmpty`: that would keep the swatches hidden for as
    /// long as a filter was in play, so picking a symbol by search and then a colour
    /// would mean clearing the search first. Dismissing the keyboard — by picking a
    /// glyph, or by scrolling the gallery — brings the full header back with the filter
    /// intact.
    private var isCompact: Bool { searchFocused }

    private let colorColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
    private let glyphColumns = [GridItem(.adaptive(minimum: 52), spacing: 10)]

    /// The curated options ranked by the shared fuzzy matcher — best first.
    private var results: [GlyphOption] {
        CustomActionGlyphCatalog.search(query)
    }

    /// The bound glyph normalized to *set* vs *unset* — a blank or whitespace-only
    /// value reads as no symbol, mirroring `CustomActionDefinition.normalizedGlyph` /
    /// `ShortcutEntry.normalizedGlyph` so a legacy blank string previews correctly.
    private var normalizedGlyph: String? {
        guard let glyph, !glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return glyph
    }

    /// The hue the page echoes: the chosen colour, else the kind's own tint. Resolved
    /// through the shared rule so the gallery's selection never disagrees with the hero.
    private var tint: Color {
        resolvedActionTint(kind: kind, color: color)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: glyphColumns, spacing: 10) {
                // The reset leads its group, as it did in the picker this replaces:
                // "back to the derived glyph" is never buried behind a scroll.
                glyphCell(nil, symbol: "slash.circle", label: "No symbol",
                          identifier: "glyph-option-none")
                ForEach(results) { option in
                    glyphCell(option.name, symbol: option.name, label: option.label,
                              identifier: "glyph-option.\(option.name)")
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 40)

            if results.isEmpty {
                Text("No symbols match “\(query)”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        // Scrolling the gallery dismisses the keyboard, which expands the header again —
        // the other way out of the compact state besides picking a symbol.
        .scrollDismissesKeyboard(.immediately)
        // Pinned, not scrolled: the preview has to stay put while the gallery moves
        // under it. A `safeAreaInset` (rather than a VStack + nested ScrollView) keeps
        // the gallery a real scroll view, so it still gets scroll-to-top, keyboard
        // dismissal, and correct safe-area insets.
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationTitle("Symbol & Color")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The pinned half: the live hero, its caption, the colour row, and the gallery's
    /// search field — full-height normally, compact while searching.
    private var header: some View {
        VStack(spacing: isCompact ? 10 : 14) {
            if isCompact {
                // Compact: the preview shrinks to an inline chip beside its caption, and
                // the swatches step aside so the keyboard leaves room for results.
                HStack(spacing: 10) {
                    ProviderBadge(kind: kind, symbol: normalizedGlyph, color: color)
                        .accessibilityIdentifier("appearance-hero")
                    Text(heroCaption)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
            } else {
                // The same badge every surface draws, *drawn* at hero size rather than
                // transformed up to it: `ProviderBadge` derives its corner radius and
                // glyph size from `size`, so the proportions are still stated once, and
                // the symbol stays vector all the way down instead of being a 14pt raster
                // stretched 2.6× — which is what left the more detailed glyphs soft here
                // while the simple ones looked fine.
                ProviderBadge(kind: kind, symbol: normalizedGlyph, color: color, size: 78)
                    .accessibilityIdentifier("appearance-hero")

                Text(heroCaption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                LazyVGrid(columns: colorColumns, spacing: 12) {
                    colorCircle(nil)
                    ForEach(ActionColor.allCases, id: \.rawValue) { color in
                        colorCircle(color)
                    }
                }
                .padding(.horizontal)
            }

            searchField
                .padding(.horizontal)
                .padding(.top, isCompact ? 0 : 2)
        }
        .animation(.snappy(duration: 0.2), value: isCompact)
        .animation(.snappy(duration: 0.18), value: color)
        .animation(.snappy(duration: 0.18), value: normalizedGlyph)
        .padding(.top, isCompact ? 8 : 12)
        .padding(.bottom, isCompact ? 10 : 14)
        .frame(maxWidth: .infinity)
        // An opaque backdrop so the gallery scrolls *under* the pinned header rather
        // than showing through it.
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// The gallery's filter, sitting at the **bottom** of the pinned header — directly
    /// above the thing it filters. An inline field rather than `.searchable`'s nav-bar
    /// drawer: the drawer would sit above the *hero*, detaching the control from the
    /// grid it acts on and pushing the preview down the screen.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search symbols", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .accessibilityIdentifier("glyph-search-field")
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("glyph-search-clear")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }

    /// What the hero is currently made of, spelled out — the colour's name, and the
    /// symbol's when one is chosen. The caption carries the names so the swatches and
    /// glyph cells don't each need a label crowding the grid.
    private var heroCaption: String {
        let colorLabel = color?.label ?? "Default"
        guard let glyph = normalizedGlyph,
              let option = CustomActionGlyphCatalog.all.first(where: { $0.name == glyph })
        else { return colorLabel }
        return "\(option.label) · \(colorLabel)"
    }

    private func colorCircle(_ option: ActionColor?) -> some View {
        Button {
            color = option
        } label: {
            ZStack {
                Circle()
                    .fill(option?.swiftUIColor ?? Color.secondary.opacity(0.15))
                if option == nil {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38, height: 38)
            .overlay {
                if color == option {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .frame(width: 46, height: 46)
                }
            }
            // A 48pt square around a 38pt circle: the ring needs the room, and the tap
            // target should not be the circle alone.
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(option.map { "action-color-option.\($0.rawValue)" } ?? "action-color-option-default")
        .accessibilityLabel(option?.label ?? "Default")
        .accessibilityAddTraits(color == option ? [.isButton, .isSelected] : .isButton)
    }

    /// One gallery cell. The selected one is tinted with the **current colour choice**,
    /// not the app accent, so the gallery echoes the hero instead of introducing a third
    /// colour that means nothing here.
    private func glyphCell(_ value: String?, symbol: String, label: String, identifier: String) -> some View {
        let isSelected = normalizedGlyph == value
        return Button {
            glyph = value
            // Picking a symbol ends the search interaction, so drop the keyboard: the
            // header expands and the colour swatches are reachable again without the
            // user having to clear their query first.
            searchFocused = false
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.22) : Color.secondary.opacity(0.10))
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isSelected ? tint : (value == nil ? Color.secondary : .primary))
            }
            .frame(height: 46)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
