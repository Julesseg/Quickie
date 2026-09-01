#!/usr/bin/env python3
"""PROTOTYPE (#269) — assemble the captured PNGs into one self-contained page.

Images are inlined as data URIs, like the iPad audit's report, so the file can
be opened from anywhere (or attached to the issue) without its `img/` tree.
"""
import base64, glob, html, os, sys
from PIL import Image

ROOT = sys.argv[1]                       # palette-report/
IMG = os.path.join(ROOT, "img")
VERDICT = open(os.path.join(ROOT, "verdict.html")).read() if os.path.exists(os.path.join(ROOT, "verdict.html")) else ""

def uri(path, max_w=900):
    # The committed evidence set is JPEG (the raw PNGs are hundreds of MB and
    # are gitignored); fall back so this runs against either.
    if not os.path.exists(path):
        alt = path[:-4] + ".jpg" if path.endswith(".png") else None
        if alt and os.path.exists(alt):
            path = alt
        else:
            return None
    im = Image.open(path).convert("RGB")
    if im.width > max_w:
        im = im.resize((max_w, int(im.height * max_w / im.width)), Image.LANCZOS)
    tmp = path + ".tmp.jpg"
    im.save(tmp, "JPEG", quality=78)
    with open(tmp, "rb") as f:
        b = base64.b64encode(f.read()).decode()
    os.remove(tmp)
    return "data:image/jpeg;base64," + b

def pair(title, note, a, b, a_label="Docked (ships today)", b_label="Palette (alternative B)"):
    ua, ub = uri(a), uri(b)
    if not (ua and ub):
        return ""
    return f"""
    <section class="pair">
      <h3>{html.escape(title)}</h3>
      <p class="note">{note}</p>
      <div class="row">
        <figure><img src="{ua}"><figcaption>{html.escape(a_label)}</figcaption></figure>
        <figure><img src="{ub}"><figcaption>{html.escape(b_label)}</figcaption></figure>
      </div>
    </section>"""

def sheet(title, note, path):
    u = uri(path, max_w=1600)
    if not u:
        return ""
    return f"""
    <section class="pair">
      <h3>{html.escape(title)}</h3>
      <p class="note">{note}</p>
      <figure class="wide"><img src="{u}"></figure>
    </section>"""

TITLES = {
    "10-home": "Home, empty query",
    "11-results-ranked": "Ranked results",
    "12-results-calc": "A single calculator result",
    "13-results-long": "A long ranked list",
}

STATES = [
    ("10-home", "Home, empty query. The launch state — what a hardware-keyboard user sees before typing a character."),
    ("11-results-ranked", "A ranked Result list. The rank-0 adjacency question: is the Highlighted result still against the input?"),
    ("12-results-calc", "A single boosted Calculator result — the shortest possible list, where the layout has nowhere to hide."),
    ("13-results-long", "A long ranked list — the case where the layout has the most to carry."),
]

body = []
for mode_dir, mode_label in (("light", "Light"), ("dark", "Dark")):
    chunks = [pair(f"{TITLES[key]} — {mode_label.lower()}", note,
                   os.path.join(IMG, mode_dir, f"docked-{key}.png"),
                   os.path.join(IMG, mode_dir, f"palette-{key}.png"))
              for key, note in STATES]
    chunks = [c for c in chunks if c]
    if chunks:
        body.append(f"<h2>{mode_label} appearance</h2>" + "".join(chunks))

trigger = pair(
    "The trigger",
    "Same build, same simulator, same launch arguments but one: the right-hand shot forces the "
    "<em>hardware keyboard attached</em> term true and leaves the rest of the decision running for real. "
    "The left-hand shot is what a simulator can actually reach — <code>GCKeyboard</code> reports no "
    "keyboard even with Connect Hardware Keyboard on, so the trigger never fires. The badge prints "
    "the trigger's inputs and its answer.",
    os.path.join(IMG, "trigger", "unforced.png"),
    os.path.join(IMG, "trigger", "forced.png"),
    a_label="GCKeyboard sees nothing → DOCKED",
    b_label="Hardware term forced → PALETTE",
)
if trigger:
    body.append("<h2>The trigger</h2>" + trigger)

flips = sheet("The flip, frame by frame",
              "One continuous burst of 90 screenshots taken back to back at the real motion budget, "
              "across a dozen automatic flips. Read left to right, top to bottom.",
              os.path.join(IMG, "flip-contact-sheet.jpg"))
mid = ""
for name, note in (("flip-004", "Mid-flight. The bar is between the two docks and the result list is "
                                "showing <b>two differently-ordered copies of itself at once</b> — New "
                                "Snippet, Save for later, Search the web and Search the App Store each "
                                "appear twice, in two places."),
                   ("flip-025", "Mid-flight, worse: the input bar is travelling <b>through the middle of "
                                "the result list</b>, drawn over the rows, while the same doubling plays "
                                "out beneath it.")):
    u = uri(os.path.join(IMG, "flip-key", name + ".jpg"), max_w=760)
    if u:
        mid += f'''<section class="pair"><h3>{name}</h3><p class="note">{note}</p>
        <figure style="max-width:760px"><img src="{u}"></figure></section>'''
if flips or mid:
    body.append("<h2>The flip</h2>" + flips + mid)

analysis = ""
apath = os.path.join(ROOT, "analysis.txt")
if os.path.exists(apath):
    analysis = f"<h2>Pixel measurements</h2><pre>{html.escape(open(apath).read())}</pre>"

out = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Quickie — palette mode prototype (#269)</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font: 16px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
         max-width: 1180px; margin: 0 auto; padding: 40px 24px 120px; }}
  h1 {{ font-size: 2rem; margin-bottom: .2em; }}
  h2 {{ margin-top: 2.6em; padding-bottom: .3em; border-bottom: 1px solid color-mix(in srgb, currentColor 18%, transparent); }}
  h3 {{ margin-bottom: .2em; font-size: 1.05rem; }}
  .sub {{ opacity: .7; margin-top: 0; }}
  .note {{ opacity: .75; margin-top: .2em; }}
  .row {{ display: grid; grid-template-columns: 1fr 1fr; gap: 18px; margin: 14px 0 34px; }}
  figure {{ margin: 0; }}
  figure img {{ width: 100%; border-radius: 10px;
                border: 1px solid color-mix(in srgb, currentColor 20%, transparent); display: block; }}
  figure.wide img {{ border-radius: 6px; }}
  figcaption {{ font-size: .85rem; opacity: .7; margin-top: .5em; text-align: center; }}
  pre {{ background: color-mix(in srgb, currentColor 7%, transparent); padding: 16px;
         border-radius: 10px; overflow-x: auto; font-size: .8rem; line-height: 1.45; }}
  .verdict {{ border-left: 4px solid currentColor; padding: 4px 0 4px 18px; margin: 28px 0; }}
  code {{ font-size: .9em; }}
</style></head><body>
<h1>Palette mode on a hardware-keyboard iPad</h1>
<p class="sub">Prototype for issue #269 — iPad UI audit direction alternative <b>B</b>.
Branch <code>prototype/ipad-palette-mode</code>, iPad Pro 13″ (M5) simulator.
Throwaway: the deliverable is the ADR, not this branch.</p>
{VERDICT}
{''.join(body)}
{analysis}
</body></html>"""

dest = os.path.join(ROOT, "index.html")
open(dest, "w").write(out)
print(f"wrote {dest} ({len(out)//1024} KB)")
