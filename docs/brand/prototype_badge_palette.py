#!/usr/bin/env python3
"""Prototype an alternate provider-badge palette for issue #178 (PR #189).

This is a *design* tool, not part of CI. It lets you explore different badge
rings under the same constraint system the shipped palette was built to, so you
can see and check a candidate before pasting its literals into
`App/QuickieEntry/QuickieBrand.swift`.

It does three things:
  1. Builds a 15-hue ring from a handful of knobs (lightness, chroma, the arcs
     the ring is allowed to use, and the kind order around it).
  2. Renders the ring as squircle swatches on both a light and a dark backdrop,
     with the same top-to-bottom luminosity gradient `ProviderBadge` draws.
  3. Runs the *same* invariants `docs/brand/check-brand-assets.py` enforces, so a
     candidate that prints "READY" will pass CI once pasted in.

Pure stdlib except Pillow (`pip install pillow`) for the swatch PNGs; pass
`--no-render` to skip rendering and drop the dependency.

    python3 docs/brand/prototype_badge_palette.py
    python3 docs/brand/prototype_badge_palette.py --lightness 0.58 --chroma-cap 0.20

The design rationale — *why* these knobs and these arcs — is in
`docs/brand/badge-palette-methodology.md`. Read that first.
"""

import argparse
import math

# --- OKLCH <-> sRGB -------------------------------------------------------
# OKLCH is a perceptual space: equal steps look equal, and lightness/chroma/hue
# are independent. That is the whole reason the constraint system works — see
# the methodology doc. sRGB (0-255) is what SwiftUI's Color(red:green:blue:) wants.


def _linear(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _encode(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def srgb_to_oklab(rgb):
    r, g, b = (_linear(c) for c in rgb)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def _oklab_to_linear(L, a, b):
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (+4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def in_gamut(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    return all(-1e-4 <= v <= 1 + 1e-4 for v in _oklab_to_linear(L, a, b))


def oklch_to_rgb(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    return tuple(round(255 * _encode(v)) for v in _oklab_to_linear(L, a, b))


def oklab_hue(rgb):
    _, a, b = srgb_to_oklab(rgb)
    return math.degrees(math.atan2(b, a)) % 360


def max_chroma(L, h):
    """The most chroma this (lightness, hue) can carry before it leaves sRGB.

    sRGB is not a ball in OKLCH — a vivid teal at L=0.55 tops out far lower than a
    vivid magenta. Bisection finds each hue's ceiling so the ring can hug it.
    """
    lo, hi = 0.0, 0.5
    for _ in range(50):
        mid = (lo + hi) / 2
        if in_gamut(L, mid, h):
            lo = mid
        else:
            hi = mid
    return lo


# --- WCAG white-on-colour contrast ---------------------------------------
# Every badge carries a white glyph, so every badge owes it the same legibility.


def white_contrast(rgb):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(c) for c in rgb)
    return 1.05 / (0.2126 * r + 0.7152 * g + 0.0722 * b + 0.05)


# --- The invariants (mirror of check-brand-assets.py) ---------------------
# Keep these in sync with docs/brand/check-brand-assets.py. If a candidate passes
# here it will pass CI; if you loosen a bound here, loosen it there too (and say
# why in the methodology doc).
BADGE_LIGHTNESS = (0.53, 0.57)
BADGE_WHITE_CONTRAST = (4.4, 5.6)
BADGE_MIN_SEPARATION = 0.030
BADGE_ACCENT_CLEARANCE = 25.0
BADGE_GOLD_CLEARANCE = 20.0

# The brand's own hues, off-limits to badges (ADR 0033). Straight from
# QuickieBrand.swift's literals, re-derived here so this stays a standalone tool.
ACCENT_HUES = {"lightAccent": oklab_hue((88, 50, 180)), "lavender": oklab_hue((203, 184, 255))}
GOLD_HUE = oklab_hue((255, 201, 79))

# The 15 ActionKinds, in the ring order the shipped palette uses: the cool arc
# after the gold gap, then the warm arc after the accent gap. Reorder this list to
# move a kind to a different neighbourhood; the geometry does the rest.
KIND_ORDER = [
    "file", "searchFiles", "calculator", "newSnippet", "snippet", "system",
    "managementPage", "settings",                       # cool arc  (104 -> 255)
    "customAction", "quicklink", "shortcut", "saveForLater", "reminder", "event", "pile",  # warm arc (325 -> 424/64)
]


def _hue_gap(a, b):
    return min((a - b) % 360, (b - a) % 360)


def _arc_length(lo, hi, L, chroma, step=0.25):
    """Cumulative perceptual (OKLab a,b) path length along a hue arc."""
    hues = [lo + i * step for i in range(int((hi - lo) / step) + 1)]
    cum, total = [0.0], 0.0
    prev = srgb_to_oklab(oklch_to_rgb(L, chroma(hues[0]), hues[0] % 360))
    for h in hues[1:]:
        cur = srgb_to_oklab(oklch_to_rgb(L, chroma(h), h % 360))
        total += math.hypot(prev[1] - cur[1], prev[2] - cur[2])
        cum.append(total)
        prev = cur
    return hues, cum, total


def build_ring(lightness, chroma_cap, chroma_frac, arcs, kinds):
    """Place `len(kinds)` hues at equal *perceptual* spacing along `arcs`.

    Equal hue *degrees* would crowd the greens (where a 20-degree step is barely
    visible) and waste the magentas (where it is obvious). Spacing by OKLab arc
    length instead makes every neighbour-pair about as far apart as every other.
    """
    def chroma(h):
        return min(chroma_cap, chroma_frac * max_chroma(lightness, h % 360))

    measured = [(_arc_length(lo, hi, lightness, chroma), (lo, hi)) for lo, hi in arcs]
    total_len = sum(m[0][2] for m in measured)

    # Allocate kinds to arcs in proportion to each arc's perceptual length.
    counts = [round(len(kinds) * m[0][2] / total_len) for m in measured]
    counts[-1] += len(kinds) - sum(counts)  # absorb rounding into the last arc

    hues = []
    for (arc, _bounds), n in zip(measured, counts):
        hs, cum, tot = arc
        for k in range(n):
            target = tot * (k + 0.5) / n           # centred, so arc ends keep half-spacing
            i = min(range(len(cum)), key=lambda j: abs(cum[j] - target))
            hues.append(round(hs[i]) % 360)

    return [(kind, h, oklch_to_rgb(lightness, chroma(h), h)) for kind, h in zip(kinds, hues)], chroma


def check(ring, literals_lightness):
    """Return the list of invariant violations — empty means CI will pass."""
    problems = []
    seen = {}
    for kind, h, rgb in ring:
        L = srgb_to_oklab(rgb)[0]
        if not BADGE_LIGHTNESS[0] <= L <= BADGE_LIGHTNESS[1]:
            problems.append(f".{kind}: OKLCH lightness {L:.3f} outside {BADGE_LIGHTNESS}")
        contrast = white_contrast(rgb)
        if not BADGE_WHITE_CONTRAST[0] <= contrast <= BADGE_WHITE_CONTRAST[1]:
            problems.append(f".{kind}: white contrast {contrast:.2f}:1 outside {BADGE_WHITE_CONTRAST}")
        for name, ah in ACCENT_HUES.items():
            if _hue_gap(oklab_hue(rgb), ah) < BADGE_ACCENT_CLEARANCE:
                problems.append(f".{kind}: {_hue_gap(oklab_hue(rgb), ah):.1f}deg from accent ({name}), "
                                f"needs {BADGE_ACCENT_CLEARANCE}")
        if _hue_gap(oklab_hue(rgb), GOLD_HUE) < BADGE_GOLD_CLEARANCE:
            problems.append(f".{kind}: {_hue_gap(oklab_hue(rgb), GOLD_HUE):.1f}deg from gold, "
                            f"needs {BADGE_GOLD_CLEARANCE}")
        seen[kind] = rgb
    for a in seen:
        for b in seen:
            if a < b:
                _, a1, b1 = srgb_to_oklab(seen[a])
                _, a2, b2 = srgb_to_oklab(seen[b])
                d = math.hypot(a1 - a2, b1 - b2)
                if d < BADGE_MIN_SEPARATION:
                    problems.append(f".{a} vs .{b}: only {d:.4f} apart in OKLab (floor {BADGE_MIN_SEPARATION})")
    return problems


def swift_literals(ring):
    out = []
    for kind, h, (r, g, b) in ring:
        name = "badge" + kind[0].upper() + kind[1:]
        out.append(f"    static let {name} = Color(red: {r} / 255, green: {g} / 255, "
                   f"blue: {b} / 255)  // h={h} #{r:02X}{g:02X}{b:02X}")
    return "\n".join(out)


def render(ring, lightness, chroma):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("(Pillow not installed — skipping swatches; `pip install pillow` to enable)")
        return
    sz, pad, cols = 72, 12, 5
    rows = (len(ring) + cols - 1) // cols
    for bg, tag, txt in (((28, 28, 30), "dark", (200, 200, 200)),
                         ((242, 242, 247), "light", (60, 60, 60))):
        img = Image.new("RGB", (cols * (sz + pad) + pad, rows * (sz + pad + 16) + pad), bg)
        d = ImageDraw.Draw(img)
        for i, (kind, h, _rgb) in enumerate(ring):
            x = pad + (i % cols) * (sz + pad)
            y = pad + (i // cols) * (sz + pad + 16)
            top = oklch_to_rgb(lightness + 0.05, chroma(h), h)
            bot = oklch_to_rgb(lightness - 0.05, chroma(h), h)
            for row in range(sz):
                t = row / (sz - 1)
                d.line([(x, y + row), (x + sz, y + row)],
                       fill=tuple(round(top[k] + (bot[k] - top[k]) * t) for k in range(3)))
            d.rounded_rectangle([x, y, x + sz, y + sz], radius=19, outline=bg, width=6)
            d.ellipse([x + sz // 2 - 9, y + sz // 2 - 9, x + sz // 2 + 9, y + sz // 2 + 9], fill=(255, 255, 255))
            d.text((x, y + sz + 3), kind[:14], fill=txt)
        img.save(f"badge_palette_{tag}.png")
    print("wrote badge_palette_dark.png / badge_palette_light.png")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--lightness", type=float, default=0.55, help="OKLCH L for the whole set (shipped: 0.55)")
    p.add_argument("--chroma-cap", type=float, default=0.17, help="max chroma any badge may use (shipped: 0.17)")
    p.add_argument("--chroma-frac", type=float, default=0.95, help="fraction of each hue's gamut ceiling to use")
    p.add_argument("--no-render", action="store_true", help="skip the swatch PNGs (drops the Pillow dependency)")
    args = p.parse_args()

    # The two arcs the ring may use, in degrees. The gaps between them are the
    # reserved zones: 64->104 is gold's, 255->325 is the accent's. Widen a gap to
    # give the accent more room; the 424 wraps past 360 to 64.
    arcs = [(104.0, 255.0), (325.0, 424.0)]

    ring, chroma = build_ring(args.lightness, args.chroma_cap, args.chroma_frac, arcs, KIND_ORDER)

    print(f"L={args.lightness}  chroma-cap={args.chroma_cap}  chroma-frac={args.chroma_frac}\n")
    for kind, h, (r, g, b) in ring:
        print(f"  {kind:16} h={h:3}  #{r:02X}{g:02X}{b:02X}  white={white_contrast((r, g, b)):.2f}:1")

    print("\n--- Swift literals (paste into QuickieBrand.swift, replacing the badge block) ---\n")
    print(swift_literals(ring))

    problems = check(ring, args.lightness)
    print("\n--- Invariant check (same rules as check-brand-assets.py) ---")
    if problems:
        for pr in problems:
            print(f"  FAIL: {pr}")
        print(f"\n{len(problems)} problem(s) — this palette would NOT pass CI. Adjust the knobs.")
    else:
        print("  READY — every invariant holds; this palette will pass CI once pasted in.")

    if not args.no_render:
        print()
        render(ring, args.lightness, chroma)


if __name__ == "__main__":
    main()
