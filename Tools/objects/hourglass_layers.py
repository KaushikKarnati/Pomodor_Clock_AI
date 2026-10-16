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
TOP = (150, 325); PILE = (486, 569); SX = (236, 446); STREAM = (326, 351, 318, 500); STREAM_TILE = (420, 480); POST = (322, 360)
GLASS_X = (230, 452); GLASS_Y = (92, 572); BULB_X = 341
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
# bottom-bulb clip mask from the glass interior below the neck: row runs of non-wood pixels.
# Scan outward from the back post's edges (the post itself is wood and would stop a scan from its
# centre), then median-smooth the edges over neighbouring rows so highlights and stray wood-coloured
# reflections can't punch holes in the mask or leak it onto the base.
def woodish(p): return p[3] > 200 and gr(p) < 0.78 and lum(p) < 150
edges = {}
for y in range(330, 570):
    l, r = POST
    while l > 232 and not woodish(P[l - 1, y]) and P[l - 1, y][3] > 200: l -= 1
    while r < 450 and not woodish(P[r + 1, y]) and P[r + 1, y][3] > 200: r += 1
    edges[y] = (l, r)
def median(values): values = sorted(values); return values[len(values) // 2]
for y in range(330, 570):
    near = [edges[v] for v in range(max(330, y - 6), min(570, y + 7))]
    l, r = median([e[0] for e in near]), median([e[1] for e in near])
    l, r = max(l, 2 * BULB_X - r), min(r, 2 * BULB_X - l)   # the bulb is symmetric: keep the tighter side
    for x in range(l + 3, r - 2): L['bottomMask'][x, y] = (255, 255, 255, 255)
# Glass highlights cross the top sand; they aren't sand-coloured, so they'd stay behind as gaps in
# the sand. Short gaps between sand pixels in a row drain with the sand.
for y in range(TOP[0], TOP[1] + 1):
    xs = [x for x in range(SX[0], SX[1] + 1) if L['sandTop'][x, y][3]]
    for a, b in zip(xs, xs[1:]):
        if 1 < b - a <= 32:
            for x in range(a + 1, b): L['sandTop'][x, y] = P[x, y]; L['base'][x, y] = (255, 255, 255, 12)
# The stream thins out where it met the generated pile (~row 480). Continue it to the bulb floor by
# repeating a clean stretch, so the app can end it wherever the scaled pile's tip is.
for y in range(STREAM_TILE[1], PILE[1]):
    for x in range(STREAM[0], STREAM[1] + 1):
        L['stream'][x, y] = L['stream'][x, STREAM_TILE[0] + (y - STREAM_TILE[1]) % (STREAM_TILE[1] - STREAM_TILE[0])]
for k, im in layers.items(): im.save(f'{A}/hourglass-{k}.png')
print({k: v.getbbox() for k, v in layers.items()})


# Inpaint the base where sand/pile/stream were lifted out.
# - Back post: below the neck it showed through the glass's white backdrop, which the glass
#   conversion above turned partly translucent. Repaint it, top to bottom, with the clean wood
#   visible above the top sand so it reads as one straight post.
# - Stream and pile: a diffusion fill. Each hole pixel settles to the average of its neighbours
#   while the clean pixels around the hole stay fixed, so no seams or stripes are left. Only some
#   sides feed a hole: the stream takes from its sides and below (not the bright neck), the pile
#   from the glass above and beside it (not the bright rim below, nor the post).
# - Top sand: mirror the (now clean) bottom bulb about the neck.
import numpy as np
NECK_Y = 326; POST_X = (328, 354); POST_Y = (334, 570)
FROM_ABOVE, FROM_BELOW, FROM_LEFT, FROM_RIGHT = (1, 0), (-1, 0), (0, 1), (0, -1)
def removed(k): return np.asarray(Image.open(f'{A}/hourglass-{k}.png'))[..., 3] > 0
def diffuse(img, hole, sources, blocked=None, iterations=4000):
    a = img[..., 3:4] / 255.0; px = np.concatenate([img[..., :3] * a, a * 255], axis=2)   # premultiplied
    ys, xs = np.nonzero(hole); y0, y1, x0, x1 = ys.min() - 1, ys.max() + 2, xs.min() - 1, xs.max() + 2
    v = px[y0:y1, x0:x1].copy(); h = hole[y0:y1, x0:x1]
    usable = ~h if blocked is None else ~h & ~blocked[y0:y1, x0:x1]   # clean pixels a hole may take from
    shifts = [FROM_ABOVE, FROM_BELOW, FROM_LEFT, FROM_RIGHT]
    def moved(m, s): return np.roll(m, s, (0, 1))
    ok = [moved(h, s) | (moved(usable, s) if s in sources else False) for s in shifts]
    count = np.maximum(sum(o.astype(float) for o in ok), 1)[..., None]
    v[h] = v[~h].mean(axis=0)
    for _ in range(iterations):
        v[h] = (sum(np.where(o[..., None], moved(v, s), 0) for o, s in zip(ok, shifts)) / count)[h]
    alpha = np.clip(v[..., 3:4], 0, 255); rgb = v[..., :3] / np.maximum(alpha, 1e-6) * 255
    out = img.copy(); out[y0:y1, x0:x1][h] = np.concatenate([rgb, alpha], axis=2)[h]; return out
img = np.asarray(Image.open(f'{A}/hourglass-base.png').convert('RGBA')).astype(float)
rows, cols = np.mgrid[0:H, 0:W]
post = np.asarray(src).astype(float)[112:147, POST_X[0]:POST_X[1] + 1].mean(axis=0)
img[POST_Y[0]:POST_Y[1], POST_X[0]:POST_X[1] + 1] = post
in_post = (cols >= POST_X[0]) & (cols <= POST_X[1]) & (rows >= POST_Y[0]) & (rows < POST_Y[1])
img = diffuse(img, removed('stream') & ~in_post, {FROM_BELOW, FROM_LEFT, FROM_RIGHT})
def grow(mask, px):
    for _ in range(px): mask = mask | np.roll(mask, 1, 0) | np.roll(mask, -1, 0) | np.roll(mask, 1, 1) | np.roll(mask, -1, 1)
    return mask
# The pile's soft, lighter edge isn't sand-coloured enough to be lifted with it; take a few pixels
# around the pile too, so the fill starts from the glass beyond that edge.
in_bulb = np.asarray(layers['bottomMask'])[..., 3] > 0
img = diffuse(img, grow(removed('pile'), 4) & in_bulb & ~in_post, {FROM_ABOVE, FROM_LEFT, FROM_RIGHT}, blocked=in_post)
for y, x in zip(*np.nonzero(removed('sandTop'))):
    img[y, x] = post[x - POST_X[0]] if POST_X[0] <= x <= POST_X[1] else img[2 * NECK_Y - y, x]
Image.fromarray(np.clip(img.round(), 0, 255).astype(np.uint8), 'RGBA').save(f'{A}/hourglass-base.png')
