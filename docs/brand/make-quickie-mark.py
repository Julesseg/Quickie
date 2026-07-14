#!/usr/bin/env python3
"""Generate the Quickie mark custom SF Symbol template.

Rebuilds App/QuickieWidgets/Assets.xcassets/QuickieMark.symbolset/quickie-mark.svg
from the same geometry as docs/brand/app-icon.svg ("Orbital Q (glide)"), emitted
into a canonical SF Symbols template (v.7.0) skeleton: the exact Notes/Guides/
style structure the SF Symbols app exports, including the symbol layer classes
(`monochrome-N multicolor-N:tintColor hierarchical-N:primary`) that Control
Center's out-of-process symbol renderer needs — a bare path with no layer
annotations renders in-process (widgets) but comes up empty in a control.

The icon trail's along-the-trajectory alpha ramp survives here as a **baked-in
layer fade**, built as a seamless base plus increments: layer 0 is the whole
orbit ring, one unbroken path at the TRAIL_ALPHA floor, and on top of it the
ring is cut into TRAIL_SEGMENTS annular sectors, one symbol layer each, whose
per-layer `opacity` (a plain CSS property on the layer's classes in the
template's style block — the encoding Apple documents for custom-symbol layer
opacity) carries only the ramp's *increment above the floor*, easing to opaque
at the head, exactly like the icon. The base-plus-increment split is seam
control, not decoration: abutting translucent fills antialias a hairline at
every shared edge, and with a seamless ring underneath, the faint tail has no
seams at all and every remaining hairline dips only toward the base's opacity
instead of all the way to the background. Sectors whose increment rounds
below 0.01 (the template's 2-decimal opacity precision — the resolution that
also bounds how fine a useful segment count can get) are omitted: the base
already renders them. Baking all this into the symbol is the point: layer
opacity is the one styling channel that travels with a symbol everywhere it
is rendered — including Control Center, which resolves only the symbol
*reference* and tints it itself, so view-level gradients and tints never
arrive there. A color gradient cannot ride along (a symbol template is solid
fills only); the widget views layer the brand color ramp on top via
`foregroundStyle`, where SwiftUI styling does apply. The dot and the glide
arrow sit above the ring in one final opaque layer.

The glide arrow is drawn exactly as the icon draws it — the same geometry, as
the outline of a round-capped stroked line plus a round-capped, round-joined
stroked chevron, so the arrowhead is the icon's soft rounded tip, not a hard
filled triangle. (While the mark was a *flat* single-opacity glyph, the arrow
had to be extended past the orbit's silhouette or it vanished into the ring;
the baked fade retired that departure — the arrow leaves across the trail's
faintest stretch, 0.3 against opaque, and reads on its own.)

Pure stdlib; deterministic. Run from the repo root:

    python3 docs/brand/make-quickie-mark.py
"""

import math
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "App/QuickieWidgets/Assets.xcassets/QuickieMark.symbolset/quickie-mark.svg"

# ---------------------------------------------------------------------------
# Geometry, in the app icon's 100x100 frame (docs/brand/app-icon.svg), in the
# pre-rotation coordinate system: everything is drawn axis-aligned around the
# orbit center (50, 45), then rotated 14 degrees about that center, exactly like
# the icon's `rotate(14 50 45)` group.
# ---------------------------------------------------------------------------
CX, CY = 50.0, 45.0
ROT_DEG = 14.0

# Orbit ring: the icon's rx=27/ry=17 ellipse stroked at ~6.5 -> outer edge
# rx 30.25 / ry 20.25, inner (hole) edge rx 23.75 / ry 13.75. A seamless base
# ring at the TRAIL_ALPHA floor, then TRAIL_SEGMENTS annular sectors along the
# travel direction carrying the ramp's increment above it (the icon's ease, a
# higher floor: a tail at the icon's 0.12 would vanish at symbol point sizes).
# 64 sectors is the finest useful cut: the largest neighbor step lands at the
# template's own 2-decimal opacity resolution (~0.01-0.02), where the icon
# needed 240 quads at 1024px.
OUTER_RX, OUTER_RY = 30.25, 20.25
INNER_RX, INNER_RY = 23.75, 13.75
DOT_R = 6.5
TRAIL_SEGMENTS = 64
TRAIL_ALPHA = (0.3, 1.0)     # fade-in floor -> release (icon: 0.12 -> 0.95)
TRAIL_ALPHA_EASE = 2.2       # icon's ramp: stays faint long, brightens late

# Glide arrow along y = 62 (the orbit's bottom tangent), the outline of the
# icon's stroke-width-6.5 round-capped arrow, at the icon's exact geometry:
# shaft `x1=50 x2=77`, head the chevron `M75 66.5 L82 62 L75 57.5` — legs from
# the tip back (-7, +/-4.5) — outlined with round caps and a round tip join,
# matching the icon's softness. It crosses the ring's faintest stretch (the
# tail just past the release), where opaque-over-0.3 keeps it legible; only
# the retired flat (unfaded) mark needed a longer arrow to clear the orbit.
ARROW_R = 3.25               # half of the icon's 6.5 stroke width
SHAFT_P0 = (50.0, 62.0)
SHAFT_P1 = (77.0, 62.0)
HEAD_TIP = (82.0, 62.0)
HEAD_BACK_DX, HEAD_BACK_DY = 7.0, 4.5

# ---------------------------------------------------------------------------
# Template metrics (canonical SF Symbols template, 3300x2200 canvas).
# ---------------------------------------------------------------------------
CAP_HEIGHT = 70.459          # Capline-to-baseline distance in every row
GLYPH_HEIGHT_S = 71.6        # Small-scale glyph height: cap height + overshoot
M_SCALE = 1.25               # Medium-scale glyph size relative to Small
BASELINE = {"S": 696.0, "M": 1126.0}
MARGIN_Y = {"S": (600.785, 720.121), "M": (1030.79, 1150.12)}
COLUMN_CENTER = {"Ultralight": 559.711, "Regular": 1449.845, "Black": 2933.4}

# Layer 0's -sfsymbols-layer-tags value, from a real SF Symbols app export;
# each subsequent layer counts up from it so every layer's tag stays unique.
LAYER_TAG_BASE = 0x564789760D3A318D


def rotated(p):
    """Rotate an icon-frame point 14 degrees about the orbit center."""
    c, s = math.cos(math.radians(ROT_DEG)), math.sin(math.radians(ROT_DEG))
    dx, dy = p[0] - CX, p[1] - CY
    return (CX + dx * c - dy * s, CY + dx * s + dy * c)


def ellipse_arc_ops(rx, ry, t0, t1):
    """Elliptical arc about the orbit center, parameter t0 -> t1 (radians).

    Cubic approximation of the parametric arc in <=90-degree chunks, signed by
    direction (t1 < t0 traces the other way). A point at parameter t is
    center + (rx*cos t, ry*sin t); yields only the ("C", ...) ops — the caller
    is already at the arc's start point.
    """
    def pt(t):
        return (CX + rx * math.cos(t), CY + ry * math.sin(t))

    def deriv(t):
        return (-rx * math.sin(t), ry * math.cos(t))

    ops = []
    steps = max(1, math.ceil(abs(t1 - t0) / (math.pi / 2)))
    for i in range(steps):
        a0 = t0 + (t1 - t0) * i / steps
        a1 = t0 + (t1 - t0) * (i + 1) / steps
        k = (4.0 / 3.0) * math.tan((a1 - a0) / 4.0)
        p0, p1 = pt(a0), pt(a1)
        d0, d1 = deriv(a0), deriv(a1)
        ops.append(("C", (p0[0] + k * d0[0], p0[1] + k * d0[1]),
                    (p1[0] - k * d1[0], p1[1] - k * d1[1]), p1))
    return ops


def ellipse_ops(rx, ry, ccw=False):
    """Axis-aligned full ellipse about the orbit center, as one subpath.

    Clockwise (screen coords, y down) unless `ccw`; the base ring's hole is
    wound counterclockwise so nonzero winding cuts it out of the outer fill.
    """
    sweep = -2.0 * math.pi if ccw else 2.0 * math.pi
    return [("M", (CX + rx, CY))] + ellipse_arc_ops(rx, ry, 0.0, sweep)


def ring_sector_ops(u0, u1):
    """One annular sector of the orbit ring, travel parameter [u0, u1].

    u runs 0 -> 1 counterclockwise (screen coords) around the full orbit, both
    ends at the bottom tangent point, exactly like the icon's trail: the faint
    tail-start and the opaque head meet where the arrow departs, so the seam
    reads as the release. Ellipse parameter t = 90 degrees is the bottom;
    counterclockwise travel is t decreasing from 450 to 90. Neighboring
    sectors share their radial-edge endpoints exactly, so the butt joints
    render seamlessly — overlapped semi-opaque fills would double-blend.
    """
    t0, t1 = (math.radians(450.0 - 360.0 * u) for u in (u0, u1))
    ops = [("M", (CX + OUTER_RX * math.cos(t0), CY + OUTER_RY * math.sin(t0)))]
    ops += ellipse_arc_ops(OUTER_RX, OUTER_RY, t0, t1)
    ops += [("L", (CX + INNER_RX * math.cos(t1), CY + INNER_RY * math.sin(t1)))]
    ops += ellipse_arc_ops(INNER_RX, INNER_RY, t1, t0)
    return ops  # the emitter's Z closes the trailing radial edge


def arc_ops(center, r, deg0, deg1):
    """Circular arc as cubic segments, clockwise (deg increasing, y down).

    Angles in degrees; a point at angle a is center + r*(cos a, sin a). Yields
    only the ("C", ...) ops — the caller is already at the arc's start point.
    """
    ops = []
    steps = max(1, math.ceil(abs(deg1 - deg0) / 90.0))
    for i in range(steps):
        a0 = math.radians(deg0 + (deg1 - deg0) * i / steps)
        a1 = math.radians(deg0 + (deg1 - deg0) * (i + 1) / steps)
        k = (4.0 / 3.0) * math.tan((a1 - a0) / 4.0) * r
        p0 = (center[0] + r * math.cos(a0), center[1] + r * math.sin(a0))
        p1 = (center[0] + r * math.cos(a1), center[1] + r * math.sin(a1))
        c1 = (p0[0] - k * math.sin(a0), p0[1] + k * math.cos(a0))
        c2 = (p1[0] + k * math.sin(a1), p1[1] - k * math.cos(a1))
        ops.append(("C", c1, c2, p1))
    return ops


def shaft_ops():
    """The arrow shaft: a round-capped capsule from SHAFT_P0 to SHAFT_P1, CW."""
    (x0, y), (x1, _) = SHAFT_P0, SHAFT_P1
    r = ARROW_R
    ops = [("M", (x0, y - r)), ("L", (x1, y - r))]
    ops += arc_ops(SHAFT_P1, r, -90.0, 90.0)     # right cap, through the tip
    ops += [("L", (x0, y + r))]
    ops += arc_ops(SHAFT_P0, r, 90.0, 270.0)     # left cap, back to the start
    return ops


def head_ops():
    """The arrowhead: the icon's round-capped, round-joined chevron, outlined.

    Legs run from the back points (tip - (HEAD_BACK_DX, +/-HEAD_BACK_DY)) to
    the tip, offset by ARROW_R: round caps at both back ends, a round join at
    the tip (the icon's soft point), and a plain vertex at the concave notch —
    which the shaft's round cap overlaps anyway, exactly like the icon.
    """
    r = ARROW_R
    tip = HEAD_TIP
    lower = (tip[0] - HEAD_BACK_DX, tip[1] + HEAD_BACK_DY)
    upper = (tip[0] - HEAD_BACK_DX, tip[1] - HEAD_BACK_DY)
    length = math.hypot(HEAD_BACK_DX, HEAD_BACK_DY)
    ux, uy = HEAD_BACK_DX / length, -HEAD_BACK_DY / length   # lower -> tip
    n_low = (-uy, ux)                                        # lower leg, outer
    n_up = (-uy, -ux)                                        # upper leg, outer
    half = math.degrees(math.atan2(n_low[1], n_low[0]))      # tip join half-angle

    def off(p, n):
        return (p[0] + n[0] * r, p[1] + n[1] * r)

    # Concave notch: the two inner offset edges meet on the symmetry axis,
    # r/cos(half) back from the tip (the legs meet the axis at 90 - half).
    notch = (tip[0] - r / math.cos(math.radians(half)), tip[1])

    ops = [("M", off(upper, n_up)), ("L", off(tip, n_up))]
    ops += arc_ops(tip, r, -half, half)                      # round tip join
    ops += [("L", off(lower, n_low))]
    ops += arc_ops(lower, r, half, half + 180.0)             # lower back cap
    ops += [("L", notch), ("L", off(upper, (-n_up[0], -n_up[1])))]
    ops += arc_ops(upper, r, 180.0 - half, 360.0 - half)     # upper back cap
    return ops


def glyph_layers():
    """The mark as symbol layers, back to front: (opacity, subpaths) pairs.

    The seamless base ring at the fade's floor, then the ring sectors carrying
    the ramp's increment above it, then the dot and the glide arrow as one
    opaque layer on top. Source-over stacking makes the composite exact:
    1 - (1-floor)(1-increment) equals the target ramp when the increment is
    the eased travel parameter itself, so `u ** EASE` *is* each sector's
    opacity. The ramp is sampled at each sector's leading edge, so the head
    sector lands at exactly 1.0 and the trail melts into the arrow with no
    step at the release. Increments are rounded to the template's 2-decimal
    opacity precision, and sectors rounding below 0.01 are omitted — the base
    ring already renders them, seamlessly.
    """
    floor, peak = TRAIL_ALPHA
    assert peak == 1.0, "increment math assumes the ramp peaks fully opaque"
    layers = [(floor, [ellipse_ops(OUTER_RX, OUTER_RY),
                       ellipse_ops(INNER_RX, INNER_RY, ccw=True)])]
    for i in range(TRAIL_SEGMENTS):
        u0, u1 = i / TRAIL_SEGMENTS, (i + 1) / TRAIL_SEGMENTS
        increment = round(u1 ** TRAIL_ALPHA_EASE, 2)
        if increment >= 0.01:
            layers.append((increment, [ring_sector_ops(u0, u1)]))
    layers.append((1.0, [ellipse_ops(DOT_R, DOT_R), shaft_ops(), head_ops()]))
    return layers


def glyph_bbox():
    """Rotated-frame bounding box of the whole mark, from dense curve samples.

    Rotation is linear, so cubics can be sampled in icon coords and the samples
    rotated; 32 samples per segment bounds the true extremum to well under a
    thousandth of an icon unit at these curvatures.
    """
    xs, ys = [], []

    def add(p):
        rp = rotated(p)
        xs.append(rp[0])
        ys.append(rp[1])

    for _, subpaths in glyph_layers():
        for ops in subpaths:
            pos = None
            for op in ops:
                if op[0] in ("M", "L"):
                    pos = op[1]
                    add(pos)
                else:
                    _, c1, c2, p1 = op
                    for i in range(1, 33):
                        t, mt = i / 32.0, 1 - i / 32.0
                        add(tuple(mt ** 3 * pos[j] + 3 * mt * mt * t * c1[j]
                                  + 3 * mt * t * t * c2[j] + t ** 3 * p1[j]
                                  for j in (0, 1)))
                    pos = p1
    return min(xs), min(ys), max(xs), max(ys)


def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def path_d(subpaths, scale, xmin, ymid):
    """Emit one layer's subpaths as a path, local to (left margin, baseline)."""
    def local(p):
        x, y = rotated(p)
        return ((x - xmin) * scale, (y - ymid) * scale - CAP_HEIGHT / 2)

    def xy(p):
        lp = local(p)
        return f"{fmt(lp[0])} {fmt(lp[1])}"

    parts = []
    for ops in subpaths:
        for op in ops:
            if op[0] == "M":
                parts.append(f"M{xy(op[1])}")
            elif op[0] == "L":
                parts.append(f"L{xy(op[1])}")
            else:
                parts.append(f"C{xy(op[1])} {xy(op[2])} {xy(op[3])}")
        parts.append("Z")
    return "".join(parts)


def layer_class(index):
    """One layer's class list — the canonical annotation trio per layer, plus
    the app-preview wireframe class every exported variant path carries."""
    return (f"monochrome-{index} multicolor-{index}:tintColor "
            f"hierarchical-{index}:primary SFSymbolsPreviewWireframe")


def layer_styles(opacities):
    """The per-layer style-block entries, in the canonical export's shape.

    Each layer keeps the single-layer template's properties (one shared motion
    group so the mark animates as a unit; a unique layer tag) and bakes the
    fade in as a plain CSS `opacity` on its classes — the documented encoding
    for custom-symbol layer opacity, honored wherever the symbol renders.
    """
    blocks = []
    for i, alpha in enumerate(opacities):
        props = (f"-sfsymbols-motion-group:0;"
                 f"-sfsymbols-layer-tags:{LAYER_TAG_BASE + i:016x}")
        if alpha < 1.0:
            props += f";opacity:{fmt(alpha)}"
        blocks += [f".monochrome-{i} {{{props}}}",
                   f".multicolor-{i}:tintColor {{{props}}}",
                   f".hierarchical-{i}:primary {{{props}}}"]
    return "\n\n".join(blocks)


def paths_block(d_by_layer):
    """The <path> lines of one variant group, back-to-front in layer order."""
    return "\n".join(f'   <path class="{layer_class(i)}" d="{d}"/>'
                     for i, d in enumerate(d_by_layer))

# The canonical template skeleton: byte-for-byte the structure the SF Symbols
# app (v7 / Xcode 26) exports — style block with layer classes, Notes with the
# template-version marker, Guides with H-references and per-variant margins —
# with only the glyph paths, margins, and provenance text as ours.
SKELETON = """<?xml version="1.0" encoding="UTF-8"?>
<!--Quickie mark - orbital Q (glide). Generated by docs/brand/make-quickie-mark.py
    from the geometry of docs/brand/app-icon.svg, arrow included verbatim; the
    icon trail's fade is baked in as per-layer opacities along the orbit.-->
<!DOCTYPE svg
PUBLIC "-//W3C//DTD SVG 1.1//EN"
       "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 3300 2200">
 <!--glyph: "quickie.mark", point size: 100.0, template writer version: "138.0.0"-->
 <style>.defaults {-sfsymbols-variable-value-mode:color;-sfsymbols-draw-reverses-motion-groups:true}

{LAYER_STYLES}

.SFSymbolsPreviewWireframe {fill:none;opacity:1.0;stroke:black;stroke-width:0.5}
</style>
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="292" y2="292"/>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 559.711 322)">Ultralight</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 856.422 322)">Thin</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 1153.13 322)">Light</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 1449.84 322)">Regular</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 1746.56 322)">Medium</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 2043.27 322)">Semibold</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 2339.98 322)">Bold</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 2636.69 322)">Heavy</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 2933.4 322)">Black</text>
  <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1903" y2="1903"/>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 1953)">Design Variations</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1971)">Symbols are supported in up to nine weights and three scales.</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1989)">For optimal layout with text and other symbols, vertically align</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 2007)">symbols with the adjacent text.</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 776 1953)">Margins</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 776 1971)">Leading and trailing margins on the left and right side of each symbol</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 776 1989)">can be adjusted by modifying the x-location of the margin guidelines.</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 776 2007)">Modifications are automatically applied proportionally to all</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 776 2025)">scales and weights.</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 1289 1953)">Exporting</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 1289 1971)">Symbols should be outlined when exporting to ensure the</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 1289 1989)">design is preserved when submitting to Xcode.</text>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.7.0</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1951)">Requires Xcode 26 or greater</text>
  <text id="descriptive-name" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">Generated from docs/brand/app-icon.svg</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1987)">Typeset at 100.0 points</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 726)">Small</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1156)">Medium</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1586)">Large</text>
 </g>
 <g id="Guides">
  <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 696)">
   <path d="{H_REFERENCE}"/>
  </g>
  <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="696" y2="696"/>
  <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="625.541" y2="625.541"/>
  <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 1126)">
   <path d="{H_REFERENCE}"/>
  </g>
  <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1126" y2="1126"/>
  <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
  <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 1556)">
   <path d="{H_REFERENCE}"/>
  </g>
  <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1556" y2="1556"/>
  <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
  <line id="right-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{RM_M}" x2="{RM_M}" y1="1030.79" y2="1150.12"/>
  <line id="left-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{LM_M}" x2="{LM_M}" y1="1030.79" y2="1150.12"/>
  <line id="right-margin-Black-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{RM_B}" x2="{RM_B}" y1="600.785" y2="720.121"/>
  <line id="left-margin-Black-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{LM_B}" x2="{LM_B}" y1="600.785" y2="720.121"/>
  <line id="right-margin-Regular-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{RM_R}" x2="{RM_R}" y1="600.785" y2="720.121"/>
  <line id="left-margin-Regular-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{LM_R}" x2="{LM_R}" y1="600.785" y2="720.121"/>
  <line id="right-margin-Ultralight-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{RM_U}" x2="{RM_U}" y1="600.785" y2="720.121"/>
  <line id="left-margin-Ultralight-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{LM_U}" x2="{LM_U}" y1="600.785" y2="720.121"/>
 </g>
 <g id="Symbols">
  <g id="Regular-M" transform="matrix(1 0 0 1 {LM_M} 1126)">
{PATHS_M}
  </g>
  <g id="Black-S" transform="matrix(1 0 0 1 {LM_B} 696)">
{PATHS_S}
  </g>
  <g id="Regular-S" transform="matrix(1 0 0 1 {LM_R} 696)">
{PATHS_S}
  </g>
  <g id="Ultralight-S" transform="matrix(1 0 0 1 {LM_U} 696)">
{PATHS_S}
  </g>
 </g>
</svg>
"""

# The template's reference capital H (fill #27AAE1), verbatim from an SF Symbols
# app export; the parser uses it as the typographic reference for the guides.
H_REFERENCE = (
    "M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459"
    "L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.2315-26.7285"
    "L12.4385-26.7285ZM55.1196 0L57.7637 0L30.6382-70.459L29.4326-70.459"
    "L29.4326-67.1323Z"
)


def build():
    """The finished template, as a string — main() writes it to OUT, and
    docs/brand/check-brand-assets.py byte-compares it against the checked-in
    file to catch a stale or hand-edited symbolset."""
    xmin, ymin, xmax, ymax = glyph_bbox()
    scale_s = GLYPH_HEIGHT_S / (ymax - ymin)
    ymid = (ymin + ymax) / 2
    width_s = (xmax - xmin) * scale_s
    width_m = width_s * M_SCALE

    layers = glyph_layers()
    d_s = [path_d(subpaths, scale_s, xmin, ymid) for _, subpaths in layers]
    d_m = [path_d(subpaths, scale_s * M_SCALE, xmin, ymid) for _, subpaths in layers]

    margins = {
        "LM_U": COLUMN_CENTER["Ultralight"] - width_s / 2,
        "RM_U": COLUMN_CENTER["Ultralight"] + width_s / 2,
        "LM_R": COLUMN_CENTER["Regular"] - width_s / 2,
        "RM_R": COLUMN_CENTER["Regular"] + width_s / 2,
        "LM_B": COLUMN_CENTER["Black"] - width_s / 2,
        "RM_B": COLUMN_CENTER["Black"] + width_s / 2,
        "LM_M": COLUMN_CENTER["Regular"] - width_m / 2,
        "RM_M": COLUMN_CENTER["Regular"] + width_m / 2,
    }

    svg = SKELETON
    svg = svg.replace("{H_REFERENCE}", H_REFERENCE)
    svg = svg.replace("{LAYER_STYLES}", layer_styles([a for a, _ in layers]))
    svg = svg.replace("{PATHS_S}", paths_block(d_s))
    svg = svg.replace("{PATHS_M}", paths_block(d_m))
    for key, value in margins.items():
        svg = svg.replace("{%s}" % key, fmt(value))
    assert not re.search(r"\{[A-Z_]+\}", svg), "unfilled skeleton placeholder"
    return svg


def main():
    OUT.write_text(build())
    xmin, ymin, xmax, ymax = glyph_bbox()
    width_s = (xmax - xmin) * GLYPH_HEIGHT_S / (ymax - ymin)
    sectors = len(glyph_layers()) - 2  # minus the base ring and the dot/arrow
    print(f"wrote {OUT.relative_to(REPO)}")
    print(f"  S glyph: {width_s:.2f} x {GLYPH_HEIGHT_S} "
          f"(cap height {CAP_HEIGHT}), M glyph: {width_s * M_SCALE:.2f} wide, "
          f"{sectors + 2} layers (base ring + {sectors}/{TRAIL_SEGMENTS} "
          f"fading sectors + 1 opaque)")


if __name__ == "__main__":
    main()
