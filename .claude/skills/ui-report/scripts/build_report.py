#!/usr/bin/env python3
"""Build a single-file HTML report from a manifest of screenshots.

Usage:
    build_report.py manifest.json --out report.html

Manifest (paths are relative to the manifest's directory):
{
  "title": "feat(editor): inline image previews (#42)",
  "meta": {"Repo": "owner/name", "Branch": "claude/issue-42", "Commit": "abc1234",
           "Devices": "iPhone 17 / iPad Pro 13, iOS 26"},
  "shots": [
    {"image": "shots/editor-light.png", "screen": "Editor", "state": "populated, light",
     "device": "iPhone", "caption": "Preview renders under the image line.",
     "criterion": "AC1: images preview inline"}
  ],
  "not_captured": [{"screen": "Settings", "reason": "needs an iCloud account"}]
}

Images are inlined as data URIs, so the output is one file that can be moved,
mailed, or attached anywhere. Shots are grouped by screen in manifest order.
"""

import argparse
import base64
import datetime as dt
import html
import json
import mimetypes
import sys
from pathlib import Path

CSS = """
:root { color-scheme: light dark; --fg:#1d1d1f; --muted:#6e6e73; --line:#d2d2d7; --bg:#fff; --card:#f5f5f7; }
@media (prefers-color-scheme: dark) { :root { --fg:#f5f5f7; --muted:#a1a1a6; --line:#3a3a3c; --bg:#000; --card:#1c1c1e; } }
* { box-sizing: border-box; }
body { margin: 0 auto; max-width: 1200px; padding: 2rem; font: 15px/1.5 -apple-system, system-ui, sans-serif; color: var(--fg); background: var(--bg); }
h1 { font-size: 1.6rem; margin: 0 0 .5rem; }
h2 { font-size: 1.2rem; margin: 2.5rem 0 1rem; padding-top: 1rem; border-top: 1px solid var(--line); }
dl.meta { display: grid; grid-template-columns: max-content 1fr; gap: .2rem 1rem; margin: 0 0 1rem; color: var(--muted); }
dl.meta dt { font-weight: 600; } dl.meta dd { margin: 0; }
nav ol { columns: 2; padding-left: 1.2rem; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1.2rem; }
figure { margin: 0; background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: .8rem; }
figure img { display: block; width: 100%; height: auto; border-radius: 8px; background: #888; cursor: zoom-in; }
figcaption { margin-top: .6rem; font-size: .9rem; }
figcaption .state { color: var(--muted); }
figcaption .criterion { display: block; margin-top: .3rem; font-size: .8rem; color: var(--muted); }
table { border-collapse: collapse; width: 100%; } td, th { text-align: left; padding: .4rem .6rem; border-bottom: 1px solid var(--line); }
.empty { color: var(--muted); font-style: italic; }
dialog { border: 0; padding: 0; background: transparent; max-width: 95vw; max-height: 95vh; }
dialog img { max-width: 95vw; max-height: 95vh; border-radius: 8px; }
dialog::backdrop { background: rgba(0,0,0,.8); }
"""

JS = """
const dlg = document.querySelector('dialog'), big = dlg.querySelector('img');
document.querySelectorAll('figure img').forEach(img => img.addEventListener('click', () => { big.src = img.src; dlg.showModal(); }));
dlg.addEventListener('click', () => dlg.close());
"""


def data_uri(path):
    mime = mimetypes.guess_type(str(path))[0] or "image/png"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"


def esc(value):
    return html.escape(str(value or ""))


def build(manifest, base_dir):
    shots = manifest.get("shots") or []
    missing = [s["image"] for s in shots if not (base_dir / s["image"]).is_file()]
    if missing:
        sys.exit("missing images: " + ", ".join(missing))

    screens = []
    for shot in shots:
        if shot.get("screen") not in screens:
            screens.append(shot.get("screen"))

    out = [
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">",
        f"<title>{esc(manifest.get('title'))}</title>",
        f"<style>{CSS}</style></head><body>",
        f"<h1>{esc(manifest.get('title'))}</h1>",
        "<dl class=\"meta\">",
    ]
    meta = dict(manifest.get("meta") or {})
    meta.setdefault("Generated", dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"))
    for key, value in meta.items():
        out.append(f"<dt>{esc(key)}</dt><dd>{esc(value)}</dd>")
    out.append("</dl>")

    if manifest.get("summary"):
        out.append(f"<p>{esc(manifest['summary'])}</p>")

    if screens:
        out.append("<nav><ol>")
        for i, screen in enumerate(screens):
            out.append(f"<li><a href=\"#s{i}\">{esc(screen)}</a></li>")
        out.append("</ol></nav>")

    for i, screen in enumerate(screens):
        out.append(f"<h2 id=\"s{i}\">{esc(screen)}</h2><div class=\"grid\">")
        for shot in shots:
            if shot.get("screen") != screen:
                continue
            state = " · ".join(esc(x) for x in (shot.get("device"), shot.get("state")) if x)
            out.append(
                f"<figure><img src=\"{data_uri(base_dir / shot['image'])}\" alt=\"{esc(shot.get('caption'))}\" loading=\"lazy\">"
                f"<figcaption>{esc(shot.get('caption'))}"
                + (f"<br><span class=\"state\">{state}</span>" if state else "")
                + (f"<span class=\"criterion\">{esc(shot['criterion'])}</span>" if shot.get("criterion") else "")
                + "</figcaption></figure>"
            )
        out.append("</div>")

    out.append("<h2>Not captured</h2>")
    not_captured = manifest.get("not_captured") or []
    if not_captured:
        out.append("<table><tr><th>Screen / state</th><th>Why</th></tr>")
        for item in not_captured:
            out.append(f"<tr><td>{esc(item.get('screen'))}</td><td>{esc(item.get('reason'))}</td></tr>")
        out.append("</table>")
    else:
        out.append("<p class=\"empty\">Every listed screen and state is above.</p>")

    out.append("<dialog><img alt=\"\"></dialog>")
    out.append(f"<script>{JS}</script></body></html>")
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path, required=True, help="Output .html path")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text())
    page = build(manifest, args.manifest.resolve().parent)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(page)
    print(args.out.resolve())


if __name__ == "__main__":
    main()
