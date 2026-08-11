// ============================================================================
// PROTOTYPE — THROWAWAY. Do not ship, do not review as production code.
//
// Question: what should the Custom Action **color picker** feel like? (The
// current one — a pushed grid of checkmark swatches — reads a bit flat.)
//
// Three structurally different variants of the editor's Color control, cycled
// by the floating ◀ ▶ pill at the bottom of the editor (DEBUG builds only):
//
//   A — Inline strip:  no navigation at all. The Color row expands in place
//       into a horizontally scrolling strip of circular swatches; pick without
//       leaving the form.
//   B — Live preview:  pushed page dominated by a large *composed badge*
//       preview (your chosen symbol on the candidate color). Tapping a swatch
//       restyles the big badge live; you leave via Back once it looks right.
//   C — Badge list:    pushed page of full-width rows, each showing the real
//       composed badge in that color beside its name — the iOS Settings idiom,
//       comparing actual results rather than bare chips.
//
// Wired into CustomActionEditorView behind #if DEBUG; the shipped picker
// (ActionColorPickerView) is untouched. When a variant wins, note it in
// PROTOTYPE-NOTES.md next to this file, fold the winner in properly, and
// delete this file.
// ============================================================================

#if DEBUG

import SwiftUI
import QuickieCore

/// Which variant the floating pill currently shows. Persisted so the choice
/// survives pushes and relaunches while flipping around.
enum ColorPickerPrototypeVariant: String, CaseIterable {
    case a, b, c

    var title: String {
        switch self {
        case .a: return "A — Inline strip"
        case .b: return "B — Live preview"
        case .c: return "C — Badge list"
        }
    }

    var next: Self { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    var previous: Self { Self.allCases[(Self.allCases.firstIndex(of: self)! + Self.allCases.count - 1) % Self.allCases.count] }
}

/// The floating variant switcher — obviously not part of the design under
/// evaluation: a high-contrast pill pinned bottom-centre, ◀ label ▶.
struct ColorPickerPrototypeSwitcher: View {
    @AppStorage("prototype-color-picker-variant") private var raw = ColorPickerPrototypeVariant.a.rawValue

    private var variant: ColorPickerPrototypeVariant {
        ColorPickerPrototypeVariant(rawValue: raw) ?? .a
    }

    var body: some View {
        HStack(spacing: 14) {
            Button { raw = variant.previous.rawValue } label: {
                Image(systemName: "chevron.left")
            }
            Text(variant.title)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 130)
            Button { raw = variant.next.rawValue } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .foregroundStyle(.white)
        .background(.black.opacity(0.82), in: Capsule())
        .shadow(radius: 6, y: 2)
        .padding(.bottom, 10)
    }
}

/// The editor's Color control, prototype edition: renders whichever variant the
/// pill selects. Replaces (in DEBUG) the shipped NavigationLink row.
struct PrototypeColorRow: View {
    @Binding var def: CustomActionDefinition
    let previewKind: ActionKind
    @AppStorage("prototype-color-picker-variant") private var raw = ColorPickerPrototypeVariant.a.rawValue

    var body: some View {
        switch ColorPickerPrototypeVariant(rawValue: raw) ?? .a {
        case .a:
            VariantAInlineStrip(selection: $def.color)
        case .b:
            NavigationLink {
                VariantBLivePreview(def: $def, kind: previewKind)
            } label: {
                labelRow
            }
        case .c:
            NavigationLink {
                VariantCBadgeList(def: $def, kind: previewKind)
            } label: {
                labelRow
            }
        }
    }

    private var labelRow: some View {
        HStack(spacing: 12) {
            ActionColorSwatchDot(color: def.color)
            Text("Color")
            Spacer(minLength: 8)
            Text(def.color?.label ?? "Default")
                .foregroundStyle(.secondary)
        }
    }
}

/// A small circular chip shared by the prototype rows (distinct from the shipped
/// square ActionColorSwatch so the variants are visually self-contained).
private struct ActionColorSwatchDot: View {
    let color: ActionColor?

    var body: some View {
        Circle()
            .fill(color?.swiftUIColor ?? Color.secondary.opacity(0.18))
            .frame(width: 28, height: 28)
            .overlay {
                if color == nil {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Variant A — inline strip (zero navigation)

/// The Color row *is* the picker: a label line plus a horizontally scrolling
/// strip of circular swatches directly in the form. Tapping selects in place —
/// no push, no dismissal, the badge preview in the row above updates live.
private struct VariantAInlineStrip: View {
    @Binding var selection: ActionColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Color")
                Spacer()
                Text(selection?.label ?? "Default")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    dot(nil)
                    ForEach(ActionColor.allCases, id: \.rawValue) { color in
                        dot(color)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func dot(_ color: ActionColor?) -> some View {
        Button {
            selection = color
        } label: {
            ZStack {
                Circle()
                    .fill(color?.swiftUIColor ?? Color.secondary.opacity(0.15))
                    .frame(width: 36, height: 36)
                if color == nil {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if selection == color {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                if selection == color {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: 44, height: 44)
                }
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color?.label ?? "Default")
    }
}

// MARK: - Variant B — live composed-badge preview

/// A pushed page whose hero is the *result*: a large composed badge (chosen
/// symbol on candidate color) that restyles live as you tap swatches below.
/// No auto-dismiss — you keep tapping until it looks right, then go Back.
private struct VariantBLivePreview: View {
    @Binding var def: CustomActionDefinition
    let kind: ActionKind

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // The hero: the badge exactly as rows will render it, at 3× scale.
                ProviderBadge(kind: kind, symbol: def.normalizedGlyph, color: def.color)
                    .scaleEffect(2.8)
                    .frame(width: 110, height: 110)
                    .animation(.snappy(duration: 0.18), value: def.color)

                Text(def.color?.label ?? "Default")
                    .font(.headline)
                    .contentTransition(.opacity)

                LazyVGrid(columns: columns, spacing: 14) {
                    circle(nil)
                    ForEach(ActionColor.allCases, id: \.rawValue) { color in
                        circle(color)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 24)
        }
        .navigationTitle("Color")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func circle(_ color: ActionColor?) -> some View {
        Button {
            def.color = color
        } label: {
            ZStack {
                Circle()
                    .fill(color?.swiftUIColor ?? Color.secondary.opacity(0.15))
                if color == nil {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .overlay {
                if def.color == color {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 3)
                        .frame(width: 58, height: 58)
                }
            }
            .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color?.label ?? "Default")
    }
}

// MARK: - Variant C — full-width badge list

/// The iOS Settings idiom: one full-width row per color, each showing the real
/// composed badge in that color beside its name, with a trailing checkmark on
/// the current choice. Tap selects and pops back.
private struct VariantCBadgeList: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var def: CustomActionDefinition
    let kind: ActionKind

    var body: some View {
        List {
            Section {
                row(nil)
            } footer: {
                Text("Default uses the tint this action's kind provides.")
            }
            Section {
                ForEach(ActionColor.allCases, id: \.rawValue) { color in
                    row(color)
                }
            }
        }
        .navigationTitle("Color")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ color: ActionColor?) -> some View {
        Button {
            def.color = color
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ProviderBadge(kind: kind, symbol: def.normalizedGlyph, color: color)
                Text(color?.label ?? "Default")
                    .foregroundStyle(.primary)
                Spacer()
                if def.color == color {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityLabel(color?.label ?? "Default")
    }
}

#endif
