#!/usr/bin/env python3
"""Fail if a generated brand asset or a hand-copied brand constant drifted.

The brand pipeline has seams its generators cannot police themselves, first
flagged in PR #169 review:

  1. The checked-in vector outputs can go stale or get hand-edited — someone
     tweaks a generator (or the SVG directly) without regenerating. Checked
     by byte-comparing docs/brand/app-icon.svg and the QuickieMark symbolset
     SVG against what the generators emit right now. (The icon's PNG renders
     need Chromium, so only the vector sources are checked.)
  2. QuickieBrand.swift hand-copies make-app-icon.py's palette as SwiftUI
     Color literals (Swift can't read the Python constants), and the app's
     AccentColor asset hand-copies the accent a third time as JSON. Nothing
     else would catch the three drifting apart — so this script owns ADR
     0033's *derivation* and re-runs it against each copy.

Also re-parses the emitted symbolset as XML: Control Center's out-of-process
renderer draws a malformed template as an *empty* glyph, the least visible
possible failure.

Pure stdlib, no rendering. Run from anywhere:

    python3 docs/brand/check-brand-assets.py

A failure prints the expected numbers, so it doubles as "what do I paste?"
after an icon recolor.

CI runs this on every full run (see the brand-assets job in ci.yml). A
docs/**-only push skips CI wholesale (paths-ignore), so a generator edit that
forgets to regenerate is caught on the next full run, not necessarily its own.
"""

import colorsys
import importlib.util
import json
import re
import sys
import xml.dom.minidom
from pathlib import Path

BRAND = Path(__file__).resolve().parent
REPO = BRAND.parents[1]
BRAND_SWIFT = REPO / "App/QuickieEntry/QuickieBrand.swift"
ACCENT_ASSET = REPO / "App/Quickie/Assets.xcassets/AccentColor.colorset/Contents.json"


def load(stem):
    """Import a generator script by filename (their names aren't identifiers)."""
    spec = importlib.util.spec_from_file_location(stem.replace("-", "_"), BRAND / f"{stem}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rgb(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


def lift(color, lightness):
    """`color`'s hue and saturation at a new HSL lightness.

    ADR 0033's derivation: the icon's field and trail share a hue (~257 deg) and
    differ only in lightness/saturation, so the brand is a purple *axis* and an
    accent is a point picked along it. Lifting in HSL keeps the field's hue and
    its saturation character — mixing toward the lavender in RGB instead would
    pass through gray and land somewhere dusty.
    """
    hue, _, saturation = colorsys.rgb_to_hls(*[c / 255 for c in color])
    return tuple(round(c * 255) for c in colorsys.hls_to_rgb(hue, lightness, saturation))


def brand_palette(icon):
    """The expected QuickieBrand literals, keyed by the Swift constant's name.

    The one source for both the Swift module and the asset catalog: every value
    here is either straight from the icon generator or derived from it now.
    """
    field_top = rgb(icon.BG_TOP)
    return {
        "lavender": icon.LAVENDER,
        "gold": icon.DOT_COLOR,
        "fieldTop": field_top,
        "fieldBottom": rgb(icon.BG_BOTTOM),
        # ADR 0033: light mode's accent. The field itself is legible on white but
        # reads as near-black, so it is lifted to a mid lightness.
        "midPurple": lift(field_top, 0.45),
    }


def swift_literals(source):
    """Every `static let <name> = Color(red: R / 255, ...)` in the module."""
    return {
        m[0]: tuple(int(v) for v in m[1:])
        for m in re.findall(
            r"static let (\w+) = Color\(red: (\d+) / 255, green: (\d+) / 255, blue: (\d+) / 255\)",
            source)
    }


def asset_colors(contents):
    """The AccentColor colorset's components as RGB triples, keyed by appearance.

    An entry carrying no `appearances` is the any/light value; Xcode writes the
    components as `"0xNN"` strings.
    """
    colors = {}
    for entry in contents["colors"]:
        if "color" not in entry:
            continue
        appearances = {a["appearance"]: a["value"] for a in entry.get("appearances", [])}
        components = entry["color"]["components"]
        colors[appearances.get("luminosity", "light")] = tuple(
            int(components[c], 16) for c in ("red", "green", "blue"))
    return colors


def main():
    icon = load("make-app-icon")
    mark = load("make-quickie-mark")
    failures = []

    if icon.SVG_OUT.read_text() != icon.HEADER + icon.build_svg("light"):
        failures.append(f"{icon.SVG_OUT.relative_to(REPO)} is stale or hand-edited "
                        "— rerun docs/brand/make-app-icon.py")

    emitted = mark.build()
    xml.dom.minidom.parseString(emitted)
    if mark.OUT.read_text() != emitted:
        failures.append(f"{mark.OUT.relative_to(REPO)} is stale or hand-edited "
                        "— rerun docs/brand/make-quickie-mark.py")

    # QuickieBrand's literals, matched by *name* rather than by position: the
    # module is free to grow constants the icon has no opinion about (the
    # curated badge hues of #178) without silently shifting this comparison.
    expected = brand_palette(icon)
    found = swift_literals(BRAND_SWIFT.read_text())
    for name, want in expected.items():
        got = found.get(name)
        if got is None:
            failures.append(f"{BRAND_SWIFT.relative_to(REPO)} has no `static let {name}` Color "
                            f"literal — ADR 0033 expects one, and it should be {want}")
        elif got != want:
            failures.append(f"{BRAND_SWIFT.relative_to(REPO)}'s `{name}` is {got}, but "
                            f"make-app-icon.py says it should be {want}")

    # The AccentColor asset is the accent's third copy (ADR 0033: it exists so
    # that *default* tinting — every toggle that names no color — is brand
    # purple). It must agree with the module's two accent literals.
    accent = asset_colors(json.loads(ACCENT_ASSET.read_text()))
    for appearance, name in (("light", "midPurple"), ("dark", "lavender")):
        got, want = accent.get(appearance), expected[name]
        if got != want:
            failures.append(f"{ACCENT_ASSET.relative_to(REPO)}'s {appearance} color is {got}, but "
                            f"ADR 0033 pins it to QuickieBrand.{name} = {want}")

    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    if failures:
        sys.exit(1)
    print("brand assets in sync")


if __name__ == "__main__":
    main()
