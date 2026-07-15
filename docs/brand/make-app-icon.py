#!/usr/bin/env python3
"""Generate the Quickie app icon — "Orbital Q (glide)" — and its asset PNGs.

Writes docs/brand/app-icon.svg (the full-bleed 1:1 vector source; iOS applies
the squircle mask itself) and renders the asset-catalog PNGs at 1024x1024:

  - light:  as-is (opaque)
  - dark:   glyph + glow only, transparent background
  - tinted: glyph in grayscale, transparent background

The orbit trail is one *continuous gradient along the trajectory* — not SVG's
straight-line gradients, which can't follow a curved stroke. The trail fades in
just past the release point, sweeps counterclockwise around the warm mass
(brightening as it goes), whitens on the final approach, and releases
tangentially at the bottom of the orbit into the white arrow. It is built from
many short opaque quads (color ramp) under a single grayscale luminance mask
(alpha ramp): opaque paint can overlap without seams, so the ramp stays smooth
where semi-transparent strokes would double-blend.

Rendering uses headless Chromium (Playwright's, or $CHROME_BIN); its mask
luminance maps a pure gray g straight to alpha g/255, which the mask grays
here rely on. Pure stdlib; deterministic. Run from the repo root:

    python3 docs/brand/make-app-icon.py
"""

import math
import os
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SVG_OUT = REPO / "docs/brand/app-icon.svg"
ICONSET = REPO / "App/Quickie/Assets.xcassets/AppIcon.appiconset"

# ---------------------------------------------------------------------------
# Design constants (icon frame: 100x100 viewBox, orbit center (50,45), the
# whole glyph rotated 14 degrees and scaled by GLYPH_SCALE about the center).
# ---------------------------------------------------------------------------
GLYPH_SCALE = 1.2                   # glyph size about the orbit center; at 1.2
                                    # every extreme (arrow tip/head, orbit rim)
                                    # still clears the iOS squircle mask
ORBIT_RX, ORBIT_RY = 27.0, 17.0     # trail centerline ellipse
TRAIL_SEGMENTS = 240                # quads approximating the along-path ramp
TRAIL_ALPHA = (0.12, 0.95)          # fade-in floor -> release
TRAIL_ALPHA_EASE = 2.2              # >1: stays faint long, brightens late
TRAIL_WHITEN_EASE = 5.0             # color holds lavender, whitens on approach
TRAIL_SOLID_FROM = 0.88             # ramps saturate here: solid white before the
                                    # arrow overlaps the head, hiding its tail edge
TRAIL_WIDTH = (5.5, 6.5)            # comet tail -> head stroke width
LAVENDER = (203, 184, 255)          # #CBB8FF
WHITE = (255, 255, 255)
ARROW_ALPHA = 0.95
DOT_COLOR = (255, 201, 79)          # #FFC94F warm mass (and its glow)
BG_TOP, BG_BOTTOM = "#2E1A5E", "#0F0726"


def luma(rgb):
    return round(0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2])


def hexc(rgb):
    return "#%02X%02X%02X" % rgb


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def trail_quads():
    """The trail as (points, color, alpha) quads along the travel direction.

    Travel parameter u runs 0 -> 1 counterclockwise (screen coords) around the
    full orbit, both ends at the bottom tangent point: the faint tail-start and
    the bright head meet exactly where the arrow departs, so the seam reads as
    the release. Angle t is the screen-space ellipse parameter (t = 90 degrees
    is the bottom); counterclockwise travel is t decreasing from 450 to 90.
    """
    def point(t, offset):
        px = 50 + ORBIT_RX * math.cos(t)
        py = 45 + ORBIT_RY * math.sin(t)
        nx, ny = ORBIT_RY * math.cos(t), ORBIT_RX * math.sin(t)  # outward normal
        n = math.hypot(nx, ny)
        return (px + nx / n * offset, py + ny / n * offset)

    quads = []
    for i in range(TRAIL_SEGMENTS):
        u0 = i / TRAIL_SEGMENTS
        u1 = min(1.0, (i + 1.6) / TRAIL_SEGMENTS)   # slight overlap: no AA seams
        um = (u0 + u1) / 2
        prog = min(1.0, um / TRAIL_SOLID_FROM)
        alpha = TRAIL_ALPHA[0] + (TRAIL_ALPHA[1] - TRAIL_ALPHA[0]) * prog ** TRAIL_ALPHA_EASE
        color = mix(LAVENDER, WHITE, prog ** TRAIL_WHITEN_EASE)
        pts = []
        for u, sign in ((u0, 1), (u1, 1), (u1, -1), (u0, -1)):
            t = math.radians(450 - 360 * u)
            w = TRAIL_WIDTH[0] + (TRAIL_WIDTH[1] - TRAIL_WIDTH[0]) * u
            pts.append(point(t, sign * w / 2))
        quads.append((pts, color, alpha))
    return quads


def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def polygon(pts, fill):
    d = " ".join(f"{fmt(x)},{fmt(y)}" for x, y in pts)
    return f'<polygon points="{d}" fill="{fill}"/>'


def arrow(stroke):
    return (f'<g stroke="{stroke}" stroke-width="6.5" stroke-linecap="round" '
            'stroke-linejoin="round" fill="none">'
            '<line x1="50" y1="62" x2="77" y2="62"/>'
            '<path d="M75 66.5 L82 62 L75 57.5"/></g>')


HEADER = """<!-- Quickie app icon - "Orbital Q (Glide)".
     A single continuous trajectory: the trail fades in just past the release
     point, sweeps counterclockwise around the warm mass at the center of
     gravity as one unbroken gradient - lavender brightening along the orbit,
     whitening on the final approach - and releases exactly at the bottom of
     the orbit, where the tangent runs flat, skimming out beneath the bowl into
     the white arrow. Bowl + tail spell a Q; the motion tells the launcher
     story (orbit, choose, go).

     This is the full-bleed 1:1 source. iOS applies the squircle mask itself,
     so there are no rounded corners here. GENERATED by
     docs/brand/make-app-icon.py (which also renders the asset-catalog PNGs at
     1024x1024: light as-is; dark glyph-only on transparency; tinted grayscale
     on transparency) - edit and rerun the script instead of this file. -->
"""


def build_svg(appearance):
    """One appearance: 'light' (opaque), 'dark', or 'tinted' (transparent)."""
    gray = appearance == "tinted"

    def paint(rgb):
        return hexc((luma(rgb),) * 3 if gray else rgb)

    quads = trail_quads()
    mask_parts = [polygon(pts, hexc((round(a * 255),) * 3)) for pts, _, a in quads]
    mask_parts.append(arrow(hexc((round(ARROW_ALPHA * 255),) * 3)))
    color_parts = [polygon(pts, paint(c)) for pts, c, _ in quads]
    color_parts.append(arrow(paint(WHITE)))

    rot = (f'<g transform="translate(50 45) rotate(14) '
           f'scale({fmt(GLYPH_SCALE)}) translate(-50 -45)">')
    lines = ['<svg width="1024" height="1024" viewBox="0 0 100 100" '
             'xmlns="http://www.w3.org/2000/svg">',
             "<defs>"]
    if appearance == "light":
        lines.append(f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
                     f'<stop offset="0" stop-color="{BG_TOP}"/>'
                     f'<stop offset="1" stop-color="{BG_BOTTOM}"/></linearGradient>')
    lines.append(f'<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">'
                 f'<stop offset="0" stop-color="{paint(DOT_COLOR)}" stop-opacity="0.55"/>'
                 f'<stop offset="1" stop-color="{paint(DOT_COLOR)}" stop-opacity="0"/>'
                 f'</radialGradient>')
    lines.append('<mask id="trail-alpha" maskUnits="userSpaceOnUse" '
                 'x="0" y="0" width="100" height="100">'
                 '<rect width="100" height="100" fill="black"/>'
                 + rot + "".join(mask_parts) + "</g></mask>")
    lines.append("</defs>")
    if appearance == "light":
        lines.append('<rect width="100" height="100" fill="url(#bg)"/>')
    lines.append(rot +
                 '<circle cx="50" cy="45" r="14" fill="url(#glow)"/>'
                 f'<circle cx="50" cy="45" r="6.5" fill="{paint(DOT_COLOR)}"/>'
                 "</g>")
    lines.append('<g mask="url(#trail-alpha)">' + rot + "".join(color_parts) + "</g></g>")
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def find_chromium():
    for candidate in (os.environ.get("CHROME_BIN"), "/opt/pw-browsers/chromium",
                      shutil.which("chromium"), shutil.which("chromium-browser"),
                      shutil.which("google-chrome"),
                      "/Applications/Chromium.app/Contents/MacOS/Chromium",
                      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"):
        if candidate and Path(candidate).exists():
            return candidate
    return None


RENDER_PAD = 200  # some headless Chromium builds size the viewport ~90px short
                  # of --window-size (the shipped light icon once ended at row
                  # ~937); render taller than the icon and crop the pad back off


def render(chromium, svg_path, png_path):
    subprocess.run(
        [chromium, "--headless", "--no-sandbox", "--disable-gpu",
         f"--screenshot={png_path}", f"--window-size=1024,{1024 + RENDER_PAD}",
         "--force-device-scale-factor=1",
         "--default-background-color=00000000", "--hide-scrollbars",
         f"file://{svg_path}"],
        check=True, capture_output=True)
    width, height, color, rows = decode_png(png_path)
    if height > 1024:
        write_png(png_path, width, 1024, color, rows[:1024])


def decode_png(png_path):
    """Decode an RGB/RGBA PNG (pure stdlib) into (width, height, color, rows)."""
    data = png_path.read_bytes()
    pos, idat, width, height, color = 8, b"", None, None, None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        if kind == b"IHDR":
            width, height, _bits, color = struct.unpack(">IIBB", data[pos + 8:pos + 18])
            if color not in (2, 6):
                raise SystemExit(f"{png_path.name}: unexpected PNG color type {color}")
        elif kind == b"IDAT":
            idat += data[pos + 8:pos + 8 + length]
        pos += 12 + length
    bpp = 4 if color == 6 else 3
    raw, stride = zlib.decompress(idat), width * bpp
    prev = bytearray(stride)
    rows = []
    for y in range(height):
        offset = y * (stride + 1)
        filt, line = raw[offset], bytearray(raw[offset + 1:offset + 1 + stride])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        rows.append(line)
        prev = line
    return width, height, color, rows


def write_png(png_path, width, height, color, rows):
    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    png_path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                         + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def assert_full_bleed(png_path):
    """Fail if the opaque (light) render doesn't cover the full 1024x1024.

    Even with render()'s padded window, a Chromium build could still screenshot
    the SVG short of the icon, leaving transparent rows that iOS composites as
    a white line at the squircle's bottom edge. Require fully opaque corners.
    """
    width, height, color, rows = decode_png(png_path)
    if color == 2:
        return  # RGB without alpha: every pixel is opaque, so full bleed
    corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1),
               (width // 2, height - 1)]
    for x, y in corners:
        if rows[y][x * 4 + 3] != 255:
            raise SystemExit(
                f"{png_path.name}: pixel ({x},{y}) is not opaque — Chromium rendered the "
                "SVG short of the window; this would show as a white edge on the icon")


def main():
    SVG_OUT.write_text(HEADER + build_svg("light"))
    print(f"wrote {SVG_OUT.relative_to(REPO)}")

    chromium = find_chromium()
    if not chromium:
        raise SystemExit("no Chromium found: set CHROME_BIN to render the PNGs")
    with tempfile.TemporaryDirectory() as tmp:
        for appearance in ("light", "dark", "tinted"):
            svg = Path(tmp) / f"{appearance}.svg"
            svg.write_text(build_svg(appearance))
            png = ICONSET / f"icon-1024-{appearance}.png"
            render(chromium, svg, png)
            if appearance == "light":
                assert_full_bleed(png)
            print(f"rendered {png.relative_to(REPO)}")


if __name__ == "__main__":
    main()
