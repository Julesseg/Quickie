#!/usr/bin/env python3
"""PROTOTYPE — throwaway. Explore *variants* of the provider-badge ring (#178/#189).

`prototype_badge_palette.py` renders one candidate at a time. This sits next to it
and answers the design question directly: **which ring do we actually want?** It
holds a handful of deliberately-different rings — the shipped one plus five that
each push a single knob to an extreme — renders them all as labeled rows on both a
light and a dark backdrop, and marks each PASS/FAIL against the *same* invariants
CI enforces (via `check()` in the sibling tool). So you compare them side by side,
pick, then paste that variant's knobs back into `prototype_badge_palette.py` to
emit the Swift literals.

It is a comparison harness, not production and not CI:
  - It imports every scrap of color math and every invariant from
    `prototype_badge_palette.py` — nothing here re-derives OKLCH or the rules.
  - Out-of-band variants are shown on purpose (that's the point — you see *why* a
    knob is pinned), flagged rather than hidden.

    python3 docs/brand/prototype_badge_variants.py            # writes the two sheets
    python3 docs/brand/prototype_badge_variants.py --no-render # just the console table

Verdict once picked → jot it in NOTES beside this file, then delete both prototypes.
Design rationale for the knobs and arcs: docs/brand/badge-palette-methodology.md.
"""

import argparse
import importlib.util
import os

# Import the sibling single-palette tool as a module (hyphen-free filename, but it
# lives in a non-package dir) — this is the whole point: one source of color math.
_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("badge_palette", os.path.join(_HERE, "prototype_badge_palette.py"))
bp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bp)

# The reserved-zone arcs the shipped ring uses (gold gap 64->104, accent gap 255->325).
SHIPPED_ARCS = [(104.0, 255.0), (325.0, 424.0)]
# A ring that gives the purple accent noticeably more room: the cool arc stops short
# of 255 and the warm arc starts later, so no badge crowds the accent's hue.
WIDE_ACCENT_ARCS = [(104.0, 243.0), (337.0, 424.0)]

# Each variant is one deliberate move away from shipped, so a difference you see is
# attributable to a single knob. (lightness, chroma_cap, chroma_frac, arcs).
VARIANTS = [
    ("shipped",     0.55, 0.17, 0.95, SHIPPED_ARCS,      "the ring in the PR — the point of comparison"),
    ("muted",       0.55, 0.11, 0.70, SHIPPED_ARCS,      "low chroma: does a calmer set read more as one family?"),
    ("vivid",       0.55, 0.24, 1.00, SHIPPED_ARCS,      "each hue to its gamut ceiling: how loud can badges get?"),
    ("lighter",     0.62, 0.15, 0.92, SHIPPED_ARCS,      "L up: white glyph should start losing contrast (why L is pinned)"),
    ("deeper",      0.48, 0.19, 1.00, SHIPPED_ARCS,      "L down: moodier, darker chips"),
    ("wide-accent", 0.55, 0.17, 0.95, WIDE_ACCENT_ARCS,  "same look, arcs pull further off the purple accent"),
]


def build_variant(lightness, cap, frac, arcs):
    ring, chroma = bp.build_ring(lightness, cap, frac, arcs, bp.KIND_ORDER)
    problems = bp.check(ring, lightness)
    return ring, chroma, problems


def print_table(built):
    for (name, L, cap, frac, _arcs, why), (ring, _chroma, problems) in built:
        status = "PASS" if not problems else f"FAIL ({len(problems)})"
        cmin = min(bp.white_contrast(rgb) for _, _, rgb in ring)
        cmax = max(bp.white_contrast(rgb) for _, _, rgb in ring)
        print(f"  {name:12} L={L:.2f} cap={cap:.2f} frac={frac:.2f}  "
              f"white {cmin:.2f}-{cmax:.2f}:1  {status}")
        print(f"               {why}")
        for pr in problems[:3]:
            print(f"                 - {pr}")
        if len(problems) > 3:
            print(f"                 - (+{len(problems) - 3} more)")
    print()


def render_sheet(built, tag, bg, txt):
    from PIL import Image, ImageDraw
    sz, gap, label_w = 46, 8, 132
    rows = len(built)
    cols = len(bp.KIND_ORDER)
    row_h = sz + 22
    W = label_w + cols * (sz + gap) + gap
    H = gap + rows * (row_h + gap)
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    for r, ((name, L, cap, frac, _a, _why), (ring, chroma, problems)) in enumerate(built):
        y = gap + r * (row_h + gap)
        mark = "OK" if not problems else "X"
        d.text((gap, y + 4), f"{name}", fill=txt)
        d.text((gap, y + 18), f"L{L:.2f} c{cap:.2f}", fill=txt)
        d.text((gap, y + 32), f"[{mark}]", fill=(90, 200, 120) if not problems else (220, 90, 90))
        for i, (_kind, h, _rgb) in enumerate(ring):
            x = label_w + i * (sz + gap)
            top = bp.oklch_to_rgb(L + 0.05, chroma(h), h)
            bot = bp.oklch_to_rgb(L - 0.05, chroma(h), h)
            for line in range(sz):
                t = line / (sz - 1)
                d.line([(x, y + line), (x + sz, y + line)],
                       fill=tuple(round(top[k] + (bot[k] - top[k]) * t) for k in range(3)))
            d.rounded_rectangle([x, y, x + sz, y + sz], radius=12, outline=bg, width=4)
            gr = sz // 2
            d.ellipse([x + gr - 6, y + gr - 6, x + gr + 6, y + gr + 6], fill=(255, 255, 255))
    out = os.path.join(_HERE, f"badge_variants_{tag}.png")
    img.save(out)
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--no-render", action="store_true", help="skip the comparison sheets (drops Pillow)")
    args = p.parse_args()

    built = [(v, build_variant(v[1], v[2], v[3], v[4])) for v in VARIANTS]

    print("Provider-badge variants — 15 kinds each, same order as the shipped ring.\n")
    print_table(built)

    if args.no_render:
        return
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        print("(Pillow not installed — `pip install pillow` for the sheets, or use --no-render)")
        return
    for tag, bg, txt in (("dark", (28, 28, 30), (205, 205, 210)),
                         ("light", (242, 242, 247), (55, 55, 60))):
        out = render_sheet(built, tag, bg, txt)
        print(f"  wrote {os.path.relpath(out, os.getcwd())}")
    print("\nEach row is a full 15-kind ring; compare rows, pick one, then feed its knobs to\n"
          "prototype_badge_palette.py to emit Swift literals.")


if __name__ == "__main__":
    main()
