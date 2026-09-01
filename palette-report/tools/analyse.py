#!/usr/bin/env python3
"""PROTOTYPE (#269) — measure the mode flip from its captured frames.

Two questions the eye is bad at and a pixel diff is good at:

  1. How much of the screen actually changes between docked and palette?
     (mean absolute difference of the two endpoints, and the fraction of
     pixels that move at all)
  2. How long does the flip take, and does it *settle* or does it ring?
     (frame-to-frame difference across the burst — a settling transition
     decays monotonically; a rebuild shows one cliff and then nothing)
"""
import sys, os, glob
from PIL import Image, ImageChops, ImageStat

def load(p):
    return Image.open(p).convert("RGB")

def diff_stats(a, b):
    """Mean channel difference (0-255) and the fraction of pixels that moved."""
    d = ImageChops.difference(a, b)
    mean = sum(ImageStat.Stat(d).mean) / 3.0
    gray = d.convert("L").point(lambda v: 255 if v > 12 else 0)
    moved = ImageStat.Stat(gray).mean[0] / 255.0
    return mean, moved

def endpoints(dirname, a_name, b_name, label):
    pa, pb = os.path.join(dirname, a_name), os.path.join(dirname, b_name)
    if not (os.path.exists(pa) and os.path.exists(pb)):
        print(f"  [{label}] missing ({a_name} / {b_name})")
        return
    mean, moved = diff_stats(load(pa), load(pb))
    print(f"  [{label}] mean diff {mean:6.2f}/255   pixels moved {moved*100:5.1f}%")

def burst(dirname, pattern, label):
    frames = sorted(glob.glob(os.path.join(dirname, pattern)))
    if len(frames) < 3:
        print(f"  [{label}] only {len(frames)} frames — nothing to measure")
        return
    imgs = [load(f) for f in frames]
    print(f"  [{label}] {len(frames)} frames")
    prev = None
    for i, (path, img) in enumerate(zip(frames, imgs)):
        if prev is not None:
            mean, moved = diff_stats(prev, img)
            bar = "#" * int(min(moved, 1.0) * 50)
            print(f"    {os.path.basename(path):>16}  d={mean:6.2f}  moved={moved*100:5.1f}%  {bar}")
        prev = img
    # settled? compare each frame to the last
    last = imgs[-1]
    settle = None
    for i, img in enumerate(imgs):
        _, moved = diff_stats(img, last)
        if moved < 0.01 and settle is None:
            settle = i
    print(f"    settles at frame {settle if settle is not None else 'never'} of {len(frames)-1}")

def contact_sheet(dirname, pattern, out, cols=8, thumb_w=220):
    frames = sorted(glob.glob(os.path.join(dirname, pattern)))
    if not frames:
        return
    thumbs = []
    for f in frames:
        im = load(f)
        h = int(im.height * thumb_w / im.width)
        thumbs.append(im.resize((thumb_w, h)))
    tw, th = thumbs[0].size
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * th), (20, 20, 22))
    for i, t in enumerate(thumbs):
        sheet.paste(t, ((i % cols) * tw, (i // cols) * th))
    sheet.save(out)
    print(f"  contact sheet -> {out} ({len(thumbs)} frames)")

if __name__ == "__main__":
    root = sys.argv[1]
    print("== endpoints: docked vs palette (light) ==")
    light = os.path.join(root, "light")
    for state in ("10-home", "11-results-ranked", "12-results-calc", "13-results-long"):
        endpoints(light, f"docked-{state}.png", f"palette-{state}.png", state)

    print("\n== endpoints: docked vs palette (dark) ==")
    dark = os.path.join(root, "dark")
    for state in ("10-home", "11-results-ranked", "12-results-calc", "13-results-long"):
        endpoints(dark, f"docked-{state}.png", f"palette-{state}.png", state)

    print("\n== the flip, frame by frame ==")
    flip = os.path.join(root, "flip")
    burst(flip, "flip-[0-9]*.png", "continuous burst across several flips")
    contact_sheet(flip, "flip-*.png", os.path.join(root, "flip-contact-sheet.png"), cols=10)

    print("\n== the trigger ==")
    endpoints(os.path.join(root, "trigger"), "unforced.png", "forced.png",
              "GCKeyboard absent vs forced attached")
