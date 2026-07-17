#!/usr/bin/env python3
"""Fail if a generated brand asset drifted, a brand constant drifted, or the
gold budget was overspent.

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
  3. The provider-badge palette (issue #178) must keep one *distinct* hue per
     ActionKind, clear of the accent's hue and gold's. Swift's exhaustive
     switch forces every kind to name a hue, but nothing in the language
     notices when two kinds name the *same* one — which is exactly how the
     palette this replaced ended up with three kinds sharing .gray, two
     sharing .brown, and two on .indigo. There is no app-side unit test
     target (the App's logic lives in QuickieCore, which ADR 0033 keeps
     color-free), so this script is where that invariant is executable.
  4. ADR 0033 spends gold on exactly one thing — the Highlighted result's hero
     treatment — and that scarcity *is* the decision ("two accent colors is no
     accent"). Unlike the rest of this script it checks no value: nothing is
     wrong with any one use of gold, only with a second *place*, which no review
     of a diff in isolation would catch. So the budget is counted here, by file.

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
import math
import re
import sys
import xml.dom.minidom
from pathlib import Path

BRAND = Path(__file__).resolve().parent
REPO = BRAND.parents[1]
BRAND_SWIFT = REPO / "App/QuickieEntry/QuickieBrand.swift"
ACCENT_ASSET = REPO / "App/Quickie/Assets.xcassets/AccentColor.colorset/Contents.json"
ACTION_ICONS = REPO / "App/QuickieEntry/ActionIcons.swift"
ACTION_KIND = REPO / "Core/Sources/QuickieCore/Action.swift"
APP = REPO / "App"


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
        "lightAccent": lift(field_top, 0.45),
    }


def swift_literals(source):
    """Every `static let <name> = Color(red: R / 255, ...)` in the module."""
    return {
        m[0]: tuple(int(v) for v in m[1:])
        for m in re.findall(
            r"static let (\w+) = Color\(red: (\d+) / 255, green: (\d+) / 255, blue: (\d+) / 255\)",
            source)
    }


# ADR 0033 / issue #178 — the rules the badge ring is built to, restated as
# numbers. They are thresholds rather than the exact derivation: the palette is
# hand-tuned within these bounds, and this check states what "curated" has to keep
# meaning. Each is comfortably clear in the shipped set (the tightest margins are
# noted), so a failure means a real regression, not a rounding wobble.
BADGE_LIGHTNESS = (0.53, 0.57)      # one OKLCH lightness for the whole set
BADGE_WHITE_CONTRAST = (4.4, 5.6)   # ...which is what pins white-glyph legibility
BADGE_MIN_SEPARATION = 0.030        # min OKLab (a,b) distance between any two kinds
BADGE_ACCENT_CLEARANCE = 25.0       # degrees a badge must keep off the accent axis
BADGE_GOLD_CLEARANCE = 20.0         # ...and off gold, which ADR 0033 spends elsewhere


def oklab(rgb):
    """sRGB 0-255 -> OKLab (L, a, b). Perceptual, so distances mean something."""
    def linear(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (linear(c) for c in rgb)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def oklab_hue(rgb):
    _, a, b = oklab(rgb)
    return math.degrees(math.atan2(b, a)) % 360


def hue_gap(h1, h2):
    """Absolute separation between two hue angles, the short way round."""
    return min((h1 - h2) % 360, (h2 - h1) % 360)


def white_contrast(rgb):
    """WCAG contrast of white-on-`rgb` — every badge carries a white glyph."""
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(c) for c in rgb)
    return 1.05 / (0.2126 * r + 0.7152 * g + 0.0722 * b + 0.05)


def action_kind_body():
    """Just ActionKind's body — Action.swift declares plenty of other enums."""
    source = ACTION_KIND.read_text()
    start = source.index("public enum ActionKind")
    return source[start:source.index("\n}\n", start)]


def badge_failures(literals):
    """Every way the provider-badge ring can stop doing its job (issue #178).

    Reads the kind -> hue mapping straight out of ActionIcons.swift rather than
    restating it here: a copy of the mapping in this file would be one more thing
    to drift. The ActionKind list comes from Core, so a kind added there and wired
    up in the App is checked automatically, on its first CI run.
    """
    failures = []
    kinds = re.findall(r"^    case (\w+)$", action_kind_body(), re.M)
    tints = dict(re.findall(r"case \.(\w+): return QuickieBrand\.(badge\w+)",
                            ACTION_ICONS.read_text()))

    # Assert the parse before trusting it: a regex that quietly matched nothing
    # would turn every check below into a vacuous pass.
    if not kinds:
        return [f"{ACTION_KIND.relative_to(REPO)}: could not parse ActionKind's cases "
                "— this script's badge checks all just went vacuous, so fix the regex"]
    missing = [k for k in kinds if k not in tints]
    if missing:
        failures.append(f"{ACTION_ICONS.relative_to(REPO)}: no QuickieBrand badge hue for "
                        f"ActionKind {', '.join('.' + m for m in missing)} — every kind owes "
                        "the badge a hue of its own (issue #178)")

    # One kind, one hue. This is the check that the old palette would have failed
    # on three separate counts.
    by_token = {}
    for kind, token in sorted(tints.items()):
        by_token.setdefault(token, []).append(kind)
    for token, sharers in sorted(by_token.items()):
        if len(sharers) > 1:
            failures.append(f"{ACTION_ICONS.relative_to(REPO)}: {', '.join('.' + s for s in sharers)} "
                            f"all render QuickieBrand.{token} — a badge whose hue is shared "
                            "cannot say which provider a row came from (issue #178)")

    colors = {}
    for kind, token in sorted(tints.items()):
        if token not in literals:
            failures.append(f"{ACTION_ICONS.relative_to(REPO)}: .{kind} names QuickieBrand.{token}, "
                            f"which has no Color literal in {BRAND_SWIFT.relative_to(REPO)}")
        else:
            colors[kind] = literals[token]

    unused = sorted(t for t in literals if t.startswith("badge") and t not in set(tints.values()))
    for token in unused:
        failures.append(f"{BRAND_SWIFT.relative_to(REPO)}: QuickieBrand.{token} is a badge hue "
                        "no ActionKind renders — a dead hue still crowds the ring, so drop it")

    # The set is one lightness, so hue is the only channel carrying meaning — which
    # is also what holds white-glyph contrast even across all fifteen.
    for kind, rgb in sorted(colors.items()):
        lightness = oklab(rgb)[0]
        if not BADGE_LIGHTNESS[0] <= lightness <= BADGE_LIGHTNESS[1]:
            failures.append(f"{BRAND_SWIFT.relative_to(REPO)}: {tints[kind]} sits at OKLCH "
                            f"lightness {lightness:.3f}, outside the set's {BADGE_LIGHTNESS} band "
                            "— the badge ring varies by hue only (issue #178)")
        contrast = white_contrast(rgb)
        if not BADGE_WHITE_CONTRAST[0] <= contrast <= BADGE_WHITE_CONTRAST[1]:
            failures.append(f"{BRAND_SWIFT.relative_to(REPO)}: {tints[kind]} gives its white glyph "
                            f"{contrast:.2f}:1, outside the set's {BADGE_WHITE_CONTRAST} band")

    # Distinct means *visibly* distinct: equal hue *angles* would crowd the greens
    # and waste the magentas, so the floor is a perceptual distance.
    for a, b in ((a, b) for a in sorted(colors) for b in sorted(colors) if a < b):
        _, a1, b1 = oklab(colors[a])
        _, a2, b2 = oklab(colors[b])
        distance = math.hypot(a1 - a2, b1 - b2)
        if distance < BADGE_MIN_SEPARATION:
            failures.append(f"{BRAND_SWIFT.relative_to(REPO)}: {tints[a]} and {tints[b]} are only "
                            f"{distance:.4f} apart in OKLab (floor {BADGE_MIN_SEPARATION}) — "
                            f".{a} and .{b} would not be tellable apart at a glance")

    # The accent's hue and gold's are reserved (ADR 0033). A badge in the accent's
    # zone reads as a broken accent; a gold-ish badge spends the hero treatment's budget.
    axis = {n: oklab_hue(literals[n]) for n in ("lightAccent", "lavender") if n in literals}
    for kind, rgb in sorted(colors.items()):
        hue = oklab_hue(rgb)
        for name, accent_hue in sorted(axis.items()):
            gap = hue_gap(hue, accent_hue)
            if gap < BADGE_ACCENT_CLEARANCE:
                failures.append(f"{BRAND_SWIFT.relative_to(REPO)}: {tints[kind]} is {gap:.1f}deg from "
                                f"the accent axis ({name}, needs {BADGE_ACCENT_CLEARANCE}) — a badge "
                                "that close reads as a broken accent (ADR 0033)")
        if "gold" in literals:
            gap = hue_gap(hue, oklab_hue(literals["gold"]))
            if gap < BADGE_GOLD_CLEARANCE:
                failures.append(f"{BRAND_SWIFT.relative_to(REPO)}: {tints[kind]} is {gap:.1f}deg from "
                                f"gold (needs {BADGE_GOLD_CLEARANCE}) — ADR 0033 spends gold only on "
                                "the Highlighted result's hero treatment, never on a badge")

    return failures


def gold_files():
    """The files that name the gold token, outside the module that defines it.

    ADR 0033's budget is *one place*, not one mention: the hero treatment tints
    the row's glass, draws a resting ring, and lights the moving arcs — three
    honest references to gold, all in the one view that renders the Highlighted
    result. So the unit counted is the file, not the line: a second *file* is the
    second place the ADR forbids, while the treatment is free to spend gold as
    many times as one row needs.

    A plain text match, comments included: a comment that spells the token out is
    rare, and "don't name it, describe it" is the right answer if one ever does —
    the budget is about where gold appears, and prose about gold is not gold.
    """
    return sorted(
        str(path.relative_to(REPO))
        for path in APP.rglob("*.swift")
        if path != BRAND_SWIFT and "QuickieBrand.gold" in path.read_text()
    )


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
    for appearance, name in (("light", "lightAccent"), ("dark", "lavender")):
        got, want = accent.get(appearance), expected[name]
        if got != want:
            failures.append(f"{ACCENT_ASSET.relative_to(REPO)}'s {appearance} color is {got}, but "
                            f"ADR 0033 pins it to QuickieBrand.{name} = {want}")

    # The badge ring (issue #178): unlike the palette above it is not derived from
    # the icon — the icon has no opinion about what colour a Snippet is — so it is
    # checked against its *rules* rather than against a generator.
    failures.extend(badge_failures(found))

    # ADR 0033's gold budget: one place, and the scarcity is the point. Counted
    # by file rather than valued — see this module's docstring and `gold_files`.
    files = gold_files()
    if not files:
        failures.append("nothing uses QuickieBrand.gold — ADR 0033 spends it on the "
                        "Highlighted result's hero treatment (ResultListView, issue #177). If "
                        "the treatment is gone on purpose, the ADR has to say so first")
    elif len(files) > 1:
        failures.append(f"QuickieBrand.gold appears in {len(files)} files ({', '.join(files)}), "
                        "but ADR 0033 spends it in exactly one place — the Highlighted result's "
                        "hero treatment. Gold marks the row Enter runs; a second place is what "
                        "stops it meaning that, so this is a budget, not a palette entry")

    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    if failures:
        sys.exit(1)
    print("brand assets in sync")


if __name__ == "__main__":
    main()
