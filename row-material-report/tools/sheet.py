#!/usr/bin/env python3
"""PROTOTYPE (#286) — tile one device/appearance set into a contact sheet for judging.
Usage: sheet.py <device> <appearance> [out.png]"""
import os, sys
from PIL import Image, ImageDraw
dev, app = sys.argv[1], sys.argv[2]
out = sys.argv[3] if len(sys.argv) > 3 else f"/tmp/proto-sheet-{dev}-{app}.jpg"
d = f"row-material-report/img/{dev}/{app}"
rows = ["bare", "flat", "material"]
cols = [("fill", "home"), ("fill", "ranked"), ("fill", "long"), ("fill", "calc"), ("ring", "ranked"), ("strong", "ranked")]
W = 360
tiles = []
for r in rows:
    line = []
    for hero, state in cols:
        p = f"{d}/{r}-{hero}-{state}.jpg"
        if os.path.exists(p):
            im = Image.open(p).convert("RGB"); im = im.resize((W, int(im.height * W / im.width)))
        else:
            im = Image.new("RGB", (W, int(W * 2.17)), "grey")
        line.append(im)
    tiles.append(line)
H = max(im.height for line in tiles for im in line)
sheet = Image.new("RGB", (W * len(cols) + 8 * (len(cols) + 1), (H + 28) * len(rows) + 8), "white")
draw = ImageDraw.Draw(sheet)
for i, line in enumerate(tiles):
    for j, im in enumerate(line):
        x, y = 8 + j * (W + 8), 8 + i * (H + 28)
        sheet.paste(im, (x, y + 20))
        draw.text((x, y + 4), f"{rows[i]} · {cols[j][0]} · {cols[j][1]}", fill="black")
sheet.save(out)
print(out)
