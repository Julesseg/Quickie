#!/usr/bin/env python3
"""Is the flip a transition, or a teleport?

Consecutive-frame diffs cannot answer this on their own: the burst samples at
~0.6s/frame (an XCUITest screenshot is not cheap) while the capture-transition
budget is 0.35s, so a *properly animated* flip would also read as a single-frame
cliff at this cadence.

So classify instead. Take the two endpoint layouts from the burst itself, then
ask of every frame: is it docked, is it palette, or is it **neither**? A frame
that matches neither endpoint is the bar caught mid-flight — real evidence of an
interpolated transition. If 90 frames spanning a dozen flips contain zero such
frames, the flip is not being animated at all.
"""
import sys, os, glob
from PIL import Image, ImageChops, ImageStat

root = sys.argv[1]
frames = sorted(glob.glob(os.path.join(root, "flip-[0-9]*.png")))
imgs = [Image.open(f).convert("RGB") for f in frames]

def dist(a, b):
    d = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 12 else 0)
    return ImageStat.Stat(d).mean[0] / 255.0

# Endpoint A is the first frame; endpoint B is the frame furthest from it.
A = imgs[0]
dists_from_A = [dist(A, im) for im in imgs]
B = imgs[max(range(len(imgs)), key=lambda i: dists_from_A[i])]

NEAR = 0.02          # within 2% of moved pixels == "is that layout"
intermediates = []
for path, im, dA in zip(frames, imgs, dists_from_A):
    dB = dist(B, im)
    if dA < NEAR or dB < NEAR:
        continue
    intermediates.append((os.path.basename(path), dA, dB))

print(f"frames analysed:        {len(frames)}")
print(f"endpoint separation:    {max(dists_from_A)*100:.1f}% of pixels")
print(f"frames matching an endpoint: {len(frames) - len(intermediates)}")
print(f"frames matching NEITHER:     {len(intermediates)}")
if intermediates:
    print("\nmid-flight frames (distance to each endpoint):")
    for name, dA, dB in intermediates:
        print(f"  {name}  docked={dA*100:5.1f}%  palette={dB*100:5.1f}%")
else:
    print("\nNo frame sits between the two layouts. Every frame is fully one or")
    print("fully the other: the flip is a cut, not a transition.")
