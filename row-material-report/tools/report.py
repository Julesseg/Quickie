#!/usr/bin/env python3
"""PROTOTYPE (#286) — assemble the captured evidence into one self-contained page.

Images are inlined as JPEG data URIs so `index.html` can be opened from anywhere
(or attached to the issue) without its `img/` tree. Run from the repo root:

    python3 row-material-report/tools/report.py
"""
import base64, glob, html, io, os
from PIL import Image

ROOT = "row-material-report"
IMG = os.path.join(ROOT, "img")
VIDEO = os.path.join(ROOT, "video")
VERDICT = os.path.join(ROOT, "verdict.html")

ROWS = [("bare", "a · Bare + hairline"), ("flat", "b · Flat adaptive fill"), ("material", "d · System material")]
HEROES = [("fill", "i · Gold fill + slide"), ("ring", "ii · Ring light"), ("strong", "iii · Strong fill, no shimmer")]
STATES = [("home", "Home"), ("ranked", "Ranked (“se”)"), ("long", "Long list (“s”)"), ("calc", "Calculator (“2+2”)")]


def uri(path, max_w):
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGB")
    if im.width > max_w:
        im = im.resize((max_w, int(im.height * max_w / im.width)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=72)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def fig(path, caption, max_w):
    u = uri(path, max_w)
    if not u:
        return f'<figure class="missing"><figcaption>{html.escape(caption)} — missing</figcaption></figure>'
    return f'<figure><img src="{u}"><figcaption>{html.escape(caption)}</figcaption></figure>'


def grid(device, appearance, max_w):
    out = []
    for row, row_label in ROWS:
        out.append(f"<h4>{html.escape(row_label)}</h4><div class='strip'>")
        for state, state_label in STATES:
            out.append(fig(f"{IMG}/{device}/{appearance}/{row}-fill-{state}.png", state_label, max_w))
        out.append("</div>")
    return "".join(out)


def hero_grid(device, appearance, max_w):
    out = []
    for row, row_label in ROWS:
        out.append(f"<h4>{html.escape(row_label)}</h4><div class='strip'>")
        for hero, hero_label in HEROES:
            out.append(fig(f"{IMG}/{device}/{appearance}/{row}-{hero}-ranked.png", hero_label, max_w))
        out.append("</div>")
    return "".join(out)


def strips():
    out = []
    for path in sorted(glob.glob(f"{VIDEO}/*-strip.png")):
        name = os.path.basename(path)[:-10]
        out.append(fig(path, f"{name}: 6s at 4 fps, left to right, top row then bottom", 1400))
    return "".join(out)


verdict = open(VERDICT).read() if os.path.exists(VERDICT) else "<p><em>No verdict yet.</em></p>"

sections = [f"<section><h2>Verdict</h2>{verdict}</section>"]
for device, dev_label, w in [("iphone", "iPhone 17 Pro", 300), ("ipad", "iPad Pro 13″ (M5)", 420)]:
    for appearance in ("light", "dark"):
        sections.append(f"<section><h2>{dev_label} · {appearance} · row treatments (hero held at i)</h2>{grid(device, appearance, w)}</section>")
        sections.append(f"<section><h2>{dev_label} · {appearance} · hero treatments (ranked list)</h2>{hero_grid(device, appearance, w)}</section>")
sections.append(f"<section><h2>The hero settling after typing</h2><p class='note'>Frame strips from the clips in <code>video/</code>: the launcher autotypes “settings” one character every 220 ms, so the hero slot changes hands several times and the light settles ~2 s after the last keystroke.</p>{strips()}</section>")

page = f"""<!doctype html><meta charset="utf-8"><title>#286 — dressing result rows without Liquid Glass</title>
<style>
body{{font:15px/1.5 -apple-system,system-ui,sans-serif;margin:32px;color:#222;max-width:1500px}}
h2{{margin-top:48px;border-top:1px solid #ddd;padding-top:16px}} h4{{margin:20px 0 6px}}
.strip{{display:flex;gap:12px;flex-wrap:wrap;align-items:flex-start}}
figure{{margin:0}} figure img{{display:block;border:1px solid #ccc;border-radius:6px}}
figcaption{{font-size:12px;color:#666;margin-top:4px}} .missing{{color:#c00}}
.note{{color:#555}} code{{background:#f3f3f3;padding:1px 4px;border-radius:3px}}
</style>
<h1>#286 — what dresses a result row once it is no longer Liquid Glass?</h1>
<p class="note">Prototype on <code>prototype/row-material</code>. Two switches: row treatment (a / b / d) × hero treatment (i / ii / iii); geometry frozen per ADR 0042. Every shot taken with <code>simctl launch</code> + <code>simctl io screenshot</code> 7 s after launch, so the hero light is at rest.</p>
{"".join(sections)}
"""
with open(os.path.join(ROOT, "index.html"), "w") as f:
    f.write(page)
print("wrote", os.path.join(ROOT, "index.html"), len(page) // 1024, "KB")
