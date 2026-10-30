#!/usr/bin/env python3
# make-wallpapers.py GUIX-DISC-SVG OUTDIR — the Pro¹x backgrounds
#
#   light.svg  a low-poly gradient (pink, violet, teal), drawn here
#   gnu.svg    Guix's gnu from guix-backgrounds' guix-disc-flat-16-9.svg
#              (CC-BY-SA 4.0), alone and recoloured, for the dark one
#
# The build (pro1x-wallpapers) renders them with rsvg-convert and puts the
# gnu on a dark slate square with ImageMagick.  Square 2160x2160 images
# fill the panel in portrait and landscape.  Deterministic (fixed seed).

import random, re, sys

src, out = sys.argv[1], sys.argv[2]
SIZE, CELLS = 2160, 9

def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))

STOPS = [(0.0, (238, 120, 120)), (0.45, (150, 105, 160)), (1.0, (25, 110, 140))]

def gradient(t):
    t = min(max(t, 0.0), 1.0)
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return STOPS[-1][1]

rnd = random.Random(1050)              # QX1050
step = SIZE / CELLS
pts = [[(min(max(i * step + (rnd.uniform(-0.35, 0.35) * step if 0 < i < CELLS else 0), 0), SIZE),
         min(max(j * step + (rnd.uniform(-0.35, 0.35) * step if 0 < j < CELLS else 0), 0), SIZE))
        for i in range(CELLS + 1)] for j in range(CELLS + 1)]
polys = []
for j in range(CELLS):
    for i in range(CELLS):
        a, b, c, d = pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]
        tris = [(a, b, c), (a, c, d)] if rnd.random() < 0.5 else [(a, b, d), (b, c, d)]
        for t in tris:
            cx = sum(p[0] for p in t) / 3; cy = sum(p[1] for p in t) / 3
            col = gradient((cx + cy) / (2 * SIZE) + rnd.uniform(-0.06, 0.06))
            col = tuple(min(255, max(0, v + rnd.randint(-8, 8))) for v in col)
            polys.append('<polygon points="%s" fill="#%02x%02x%02x"/>' % (
                " ".join("%.1f,%.1f" % p for p in t), *col))
with open(out + "/light.svg", "w") as f:
    f.write('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
            'shape-rendering="crispEdges">%s</svg>\n' % (SIZE, SIZE, "".join(polys)))

# The gnu: a stylesheet hides every other shape of the disc wallpaper and
# recolours the gnu (inline styles lose to !important).
s = open(src).read()
style = ('<style>path, rect, circle, ellipse, use, image, text '
         '{ display: none !important; } '
         '#path3190-3 { display: inline !important; fill: #c8cdf2 !important; '
         'stroke: none !important; }</style>')
s = re.sub(r'(<svg\b[^>]*>)', r'\1' + style, s, count=1)
with open(out + "/gnu.svg", "w") as f:
    f.write(s)
