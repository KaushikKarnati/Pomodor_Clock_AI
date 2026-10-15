"""Split the generated hourglass into app layers (680-unit frame):
base (frame + back post + see-through glass), sandTop, pile, stream, bottomMask."""
import sys
from PIL import Image
A = sys.argv[1]
src = Image.open(f'{A}/hourglass-680.png').convert('RGBA'); P = src.load(); W, H = src.size
def lum(p): return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]
def gr(p): return p[1] / max(1, p[0])
def sandy(p): return p[3] > 200 and gr(p) >= 0.80 and p[0] - p[2] > 10 and lum(p) > 100
def neutral(p): return abs(p[0] - p[2]) < 18 and abs(p[0] - p[1]) < 14 and lum(p) > 135
TOP = (150, 325); PILE = (486, 569); SX = (236, 446); STREAM = (326, 351, 318, 500); POST = (322, 360)
GLASS_X = (230, 452); GLASS_Y = (92, 572)
names = ['base', 'sandTop', 'pile', 'stream', 'bottomMask']
layers = {k: Image.new('RGBA', (W, H), (0, 0, 0, 0)) for k in names}; L = {k: v.load() for k, v in layers.items()}
post_tex = [[P[x, y] for y in range(108, 151)] for x in range(W)]
for y in range(H):
    for x in range(W):
        p = P[x, y]
        if p[3] == 0: continue
        in_glass = GLASS_X[0] <= x <= GLASS_X[1] and GLASS_Y[0] <= y <= GLASS_Y[1]
        if in_glass and SX[0] <= x <= SX[1] and sandy(p) and TOP[0] <= y <= TOP[1]:
            L['sandTop'][x, y] = p
            L['base'][x, y] = post_tex[x][(y - TOP[0]) % 43] if POST[0] <= x <= POST[1] else (255, 255, 255, 12)
        elif in_glass and SX[0] <= x <= SX[1] and sandy(p) and PILE[0] <= y <= PILE[1]:
            L['pile'][x, y] = p; L['base'][x, y] = (255, 255, 255, 12)
        elif STREAM[0] <= x <= STREAM[1] and STREAM[2] <= y <= STREAM[3] and gr(p) >= 0.85 and lum(p) > 150 and p[0] - p[2] > 6:
            L['stream'][x, y] = p; L['base'][x, y] = (255, 255, 255, 12)
        elif in_glass and neutral(p):
            # glass painted over an opaque white backdrop -> translucent white highlight
            L['base'][x, y] = (255, 255, 255, int(max(0, min(210, (252 - lum(p)) * 1.9)) + 12))
        else:
            L['base'][x, y] = p
# bottom-bulb clip mask from the glass interior below the neck (row runs of non-wood around x=340)
def woodish(p): return p[3] > 200 and gr(p) < 0.78 and lum(p) < 150
for y in range(330, 570):
    l = r = 340
    while l > 232 and not woodish(P[l - 1, y]) and P[l - 1, y][3] > 200: l -= 1
    while r < 450 and not woodish(P[r + 1, y]) and P[r + 1, y][3] > 200: r += 1
    for x in range(l + 3, r - 2): L['bottomMask'][x, y] = (255, 255, 255, 255)
for k, im in layers.items(): im.save(f'{A}/hourglass-{k}.png')
print({k: v.getbbox() for k, v in layers.items()})


# Inpaint the base where sand/pile/stream were lifted out.
# 1) stream (in front of the vertical back post): interpolate each row across the gap.
# 2) top sand: mirror the empty bottom bulb about the neck (the glass is near-symmetric).
# 3) pile: mirror the empty top bulb; fall back to row interpolation inside the cap.
base = Image.open(f'{A}/hourglass-base.png').convert('RGBA'); B = base.load()
NECK_Y = 326
def removed_set(k, skip_post=False):
    q = Image.open(f'{A}/hourglass-{k}.png').load()
    return {(x, y) for y in range(H) for x in range(W) if q[x, y][3] > 0}
def interpolate_rows(points):
    by_row = {}
    for x, y in points: by_row.setdefault(y, []).append(x)
    for y, xs in by_row.items():
        xs.sort(); i = 0
        while i < len(xs):
            j = i
            while j + 1 < len(xs) and xs[j + 1] == xs[j] + 1: j += 1
            l, r = xs[i] - 1, xs[j] + 1; lp, rp = B[l, y], B[r, y]
            for x in range(xs[i], xs[j] + 1):
                t = (x - l) / (r - l); B[x, y] = tuple(int(lp[c] * (1 - t) + rp[c] * t) for c in range(4))
            i = j + 1
stream = removed_set('stream'); interpolate_rows(stream)
top = removed_set('sandTop'); pile = removed_set('pile')
for x, y in top:
    my = 2 * NECK_Y - y
    if 0 <= my < H and (x, my) not in pile: B[x, y] = B[x, my]
fallback = []
for x, y in pile:
    my = 2 * NECK_Y - y
    if 95 <= my < H and (x, my) not in top: B[x, y] = B[x, my]
    else: fallback.append((x, y))
for x, y in pile:
    my = 2 * NECK_Y - y
    if 95 <= my and (x, my) in top: B[x, y] = B[x, my]   # second pass after top was filled
interpolate_rows(fallback)
base.save(f'{A}/hourglass-base.png')
print('inpainted', len(stream), len(top), len(pile), 'fallback', len(fallback))
