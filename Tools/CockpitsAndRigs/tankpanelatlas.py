"""Procedural per-unit panel atlas for the Grizzly (avtank/bvtank) cockpits.

Deterministic (seeded) diffuse, emissive and normal art. Panel seams, rivets and
stripes are drawn per chart; the cockpit builder maps each chart onto one
metric panel cell in a face-local frame, so lines follow the mesh, never a
world projection. Palettes come from the accepted faction scout atlases.
"""
import math
from pathlib import Path
import numpy as np
from PIL import Image

SIZE = 1024
# Chart regions (u0, v0, u1, v1). UVs use an inset copy so mips never bleed.
REGIONS = {
    'plate': (0, 0, .5, .5), 'scope': (.75, 0, 1, .25),
    'hazard': (.5, .25, 1, .3125), 'frame': (.5, .3125, 1, .375), 'trim': (.5, .375, 1, .5),
    'pod': (0, .5, .5, .75), 'switch': (.5, .5, 1, .75), 'service': (0, .75, .5, 1), 'gauge': (.5, .75, 1, 1)}
PAD = 4 / SIZE
CHARTS = {k: (a + PAD, b + PAD, c - PAD, d - PAD) for k, (a, b, c, d) in REGIONS.items()}
CHARTS['armor'] = CHARTS['plate']
CHARTS['console'] = CHARTS['gauge']
# Metric size of one chart cell on the mesh (metres along u, v).
CELL = {'plate': (.40, .40), 'hazard': (.48, .06)}

PALETTE = {
    'nsdf': dict(plate=(46, 74, 76), metal=(58, 62, 60), frame=(42, 46, 45), trim=(30, 31, 30), dark=(22, 25, 24),
                 stripe=(190, 152, 38), glass=(8, 20, 18), phosphor=(60, 200, 170)),
    'bdog': dict(plate=(44, 42, 41), metal=(56, 54, 52), frame=(118, 26, 21), trim=(28, 28, 28), dark=(20, 19, 19),
                 stripe=(150, 30, 22), glass=(20, 8, 6), phosphor=(225, 85, 35))}


class Canvas:
    def __init__(self, seed):
        self.d = np.zeros((SIZE, SIZE, 3)); self.e = np.zeros((SIZE, SIZE, 3)); self.h = np.zeros((SIZE, SIZE))
        self.rng = np.random.default_rng(seed)

    def region(self, name):
        u0, v0, u1, v1 = REGIONS[name]
        return int(v0 * SIZE), int(u0 * SIZE), int(v1 * SIZE), int(u1 * SIZE)

    def grid(self, name):
        y0, x0, y1, x1 = self.region(name)
        y, x = np.mgrid[y0:y1, x0:x1]
        return (y0, x0, y1, x1), x - x0, y - y0

    def noise(self, h, w, scale):
        """Smooth value noise in [0, 1] from a bilinear-upsampled random grid."""
        gy, gx = max(2, h // scale + 2), max(2, w // scale + 2)
        g = self.rng.random((gy, gx))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)
        return np.asarray(img, float) / 255


def disc(x, y, cx, cy, r):
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def rect(x, y, x0, y0, x1, y1):
    return (x >= x0) & (x < x1) & (y >= y0) & (y < y1)


def paint(c, name, mask, colour, height=None):
    (y0, x0, y1, x1), _, _ = c.grid(name)
    c.d[y0:y1, x0:x1][mask] = colour
    if height is not None:
        c.h[y0:y1, x0:x1][mask] = height


def worn_base(c, name, colour, grime=.25, scale=24):
    (y0, x0, y1, x1), x, y = c.grid(name)
    h, w = y1 - y0, x1 - x0
    tone = .82 + .30 * c.noise(h, w, scale) + .06 * c.rng.standard_normal((h, w)) * .3
    grad = 1 - grime * (y / h) ** 2
    c.d[y0:y1, x0:x1] = np.array(colour)[None, None] * (tone * grad)[..., None]
    return x, y, w, h


def seams(c, name, x, y, w, h, width=5, depth=-1.):
    edge = np.minimum.reduce([x, y, w - 1 - x, h - 1 - y])
    groove = edge < width
    c.d[c.region(name)[0]:c.region(name)[2], c.region(name)[1]:c.region(name)[3]][groove] *= .35
    reg = c.region(name)
    c.h[reg[0]:reg[2], reg[1]:reg[3]][groove] = depth
    # One-pixel lit bevel just inside the groove sells the plate edge.
    lip = (edge >= width) & (edge < width + 2)
    c.d[reg[0]:reg[2], reg[1]:reg[3]][lip] *= 1.35


def chips(c, name, x, y, w, h, count, metal, near_edge=40):
    reg = c.region(name)
    for _ in range(count):
        side = c.rng.integers(4)
        t = c.rng.random()
        off = c.rng.random() ** 2 * near_edge + 6
        cx, cy = [(t * w, off), (w - off, t * h), (t * w, h - off), (off, t * h)][side]
        r = 1.5 + c.rng.random() * 4
        m = disc(x, y, cx, cy, r) & (c.rng.random((h, w)) < .8)
        c.d[reg[0]:reg[2], reg[1]:reg[3]][m] = np.array(metal) * (1.6 + .3 * c.rng.random())


def rivet(c, name, x, y, cx, cy, r, colour):
    reg = c.region(name)
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    m = dist <= r
    shade = 1.25 - .5 * ((x - cx) + (y - cy)) / (2 * r)
    c.d[reg[0]:reg[2], reg[1]:reg[3]][m] = (np.array(colour)[None] * shade[m][:, None])
    c.h[reg[0]:reg[2], reg[1]:reg[3]][m] = np.sqrt(np.maximum(1 - (dist[m] / r) ** 2, 0)) * 1.2


def stripes(c, name, x, y, colour, period=64):
    reg = c.region(name)
    band = ((x + y) // (period // 2)) % 2 == 0
    c.d[reg[0]:reg[2], reg[1]:reg[3]][band] = np.array(colour)[None] * (.8 + .3 * c.noise(*band.shape, 16))[band][:, None]


def draw(faction):
    p = PALETTE[faction]
    c = Canvas(seed=0x7A1 if faction == 'nsdf' else 0xB0D)
    # Armor plate: one panel per chart; seams on all four edges, corner rivets, worn edges.
    x, y, w, h = worn_base(c, 'plate', p['plate'], scale=48)
    seams(c, 'plate', x, y, w, h, width=6)
    chips(c, 'plate', x, y, w, h, 160, p['metal'])
    for cx in (22, w - 22):
        for cy in (22, h - 22):
            rivet(c, 'plate', x, y, cx, cy, 7, p['metal'])
    for cx in np.linspace(60, w - 60, 5):
        for cy in (22, h - 22):
            rivet(c, 'plate', x, y, cx, cy, 5, p['metal'])
    # Hazard band: 45-degree faction stripes, period divides the chart so cells tile.
    x, y, w, h = worn_base(c, 'hazard', p['dark'], grime=0, scale=8)
    stripes(c, 'hazard', x, y, p['stripe'])
    chips(c, 'hazard', x, y, w, h, 50, p['metal'], near_edge=12)
    edge = (y < 3) | (y >= h - 3)
    paint(c, 'hazard', edge, p['dark'], -.6)
    # Frame and trim: brushed gunmetal and dark trim.
    for name, colour in (('frame', p['frame']), ('trim', p['trim'])):
        x, y, w, h = worn_base(c, name, colour, grime=.1, scale=6)
        reg = c.region(name)
        c.d[reg[0]:reg[2], reg[1]:reg[3]] *= (1 + .08 * np.sin(y / 1.7 + c.noise(h, w, 4) * 4))[..., None]
    # Scope: square bezel, recessed round CRT with a dim phosphor sweep.
    x, y, w, h = worn_base(c, 'scope', p['frame'] if faction == 'nsdf' else p['trim'], grime=0, scale=12)
    cx, cy, r = w / 2, h / 2, w * .40
    c.h[c.region('scope')[0]:c.region('scope')[2], c.region('scope')[1]:c.region('scope')[3]] = .6
    screen = disc(x, y, cx, cy, r)
    ring = disc(x, y, cx, cy, r * 1.08) & ~screen
    paint(c, 'scope', ring, (14, 14, 14), -.2)
    paint(c, 'scope', screen, p['glass'], -.6)
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    ang = np.arctan2(y - cy, x - cx)
    reg = c.region('scope')
    trace = screen & ((abs(dist % (r / 3)) < 1.2) | (abs(x - cx) < 1) | (abs(y - cy) < 1))
    sweep = screen & (((ang + 2.4) % (2 * math.pi)) < .9)
    fade = np.clip(1 - ((ang + 2.4) % (2 * math.pi)) / .9, 0, 1)
    phos = np.array(p['phosphor'])
    c.e[reg[0]:reg[2], reg[1]:reg[3]][trace] = phos * .30
    c.e[reg[0]:reg[2], reg[1]:reg[3]][sweep] += phos[None] * (fade[sweep] * .45)[:, None]
    c.d[reg[0]:reg[2], reg[1]:reg[3]] += c.e[reg[0]:reg[2], reg[1]:reg[3]] * .25
    for sx in (14, w - 14):
        for sy in (14, h - 14):
            rivet(c, 'scope', x, y, sx, sy, 5, p['metal'])
    # Pod, switch unit and console faces keep the accepted scout-atlas
    # instrument art (pasted in images()); only their height stays flat here.
    # Service hatch: louvred grille and screws, no lamps.
    x, y, w, h = worn_base(c, 'service', p['plate'], grime=.3, scale=24)
    seams(c, 'service', x, y, w, h, width=5)
    for k in range(7):
        slot = rect(x, y, w * .18, h * (.18 + .095 * k), w * .82, h * (.18 + .095 * k) + 9)
        paint(c, 'service', slot, (10, 10, 10), -1)
    for sx in (18, w - 18):
        for sy in (18, h - 18):
            rivet(c, 'service', x, y, sx, sy, 6, p['metal'])
    return c


# Accepted scout atlas crops (u0, v0, u1, v1) reused for the instrument charts,
# as the stock-grounded pods looked before: the pod shows the button block at the
# right end of the scout console chart, the console the whole chart.
SCOUT = {'nsdf': 'crvascp', 'bdog': 'crvbscp'}
SCOUT_CROPS = {'pod': (.02 + .96 * .72, .02, .98, .34), 'gauge': (.02, .02, .98, .34), 'switch': (.02, .38, .48, .64)}


def paste_scout(faction, images_):
    folder = Path(__file__).resolve().parents[2] / 'Assets/Textures'
    for channel, im in zip(('d', 'e', 'N'), images_):
        src = Image.open(folder / (SCOUT[faction] + '_' + channel + '.dds')).convert('RGB')
        sw, sh = src.size
        for name, (u0, v0, u1, v1) in SCOUT_CROPS.items():
            a, b, c, d = REGIONS[name]
            box = (round(a * SIZE), round(b * SIZE), round(c * SIZE), round(d * SIZE))
            crop = src.crop((round(u0 * sw), round(v0 * sh), round(u1 * sw), round(v1 * sh)))
            im.paste(crop.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS), box[:2])


def images(faction):
    """Return (diffuse, emissive, normal) Pillow images for one faction."""
    c = draw(faction)
    d = Image.fromarray(np.clip(c.d, 0, 255).astype(np.uint8))
    e = Image.fromarray(np.clip(c.e, 0, 255).astype(np.uint8))
    hgt = np.asarray(Image.fromarray(((c.h + 2) * 60).astype(np.uint8)).resize((SIZE, SIZE)), float) / 60
    gy, gx = np.gradient(hgt)
    strength = 1.6
    n = np.dstack([-gx * strength, gy * strength, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2)[..., None]
    nimg = Image.fromarray(((n * .5 + .5) * 255).astype(np.uint8))
    paste_scout(faction, (d, e, nimg))
    return d, e, nimg
