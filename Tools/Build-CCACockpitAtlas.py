"""Build the CR CCA cockpit atlas (crcca_cockpit_d/n/s/e.dds) from generated panel art.

The stock soviet_units_cockpit atlas is shared by every CCA cockpit, and their UVs
sample all of it (wrapping past 0..1), so the new sheet keeps the stock module
layout: each stock box (and, at their measured world size, svtank's tub cells) is
packed with rows of whole instrument modules framed by their own panel steel, so
no gauge is sliced and dials stay round. Normal, specular and emissive maps are
derived from the diffuse. Units opt in by pointing their *01 material at
crcca_cockpit_*; the stock atlas stays untouched.

python Tools/Build-CCACockpitAtlas.py [--preview out.png]
Masters and prompts: References/TankCockpits/cca/atlas-src/ (see provenance.json).
"""
from pathlib import Path
import io, json, struct, sys
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'References/TankCockpits/cca/atlas-src'
OUT = ROOT / 'Assets/Textures'
SIZE = 2048            # diffuse/normal/specular; boxes below are in stock 1024 px
K = SIZE / 1024

# Whole instruments cut from the generated masters (master, x0, y0, x1, y1): each crop
# holds one complete gauge, lamp cluster, switch bank or rack unit with its bezel, so
# nothing is ever sliced. Each cell shows a module framed by its own panel steel.
MODULES = [
    ('dial', 1340, 170, 2350, 1180), ('dial', 2330, 210, 2570, 460), ('dial', 2350, 780, 2560, 990),
    ('dial', 1070, 320, 1310, 560), ('dial', 430, 300, 1020, 580), ('dial', 380, 980, 880, 1180),
    ('plate', 300, 460, 650, 820), ('plate', 1300, 110, 2220, 1400), ('plate', 2320, 520, 2570, 950),
    ('plate', 740, 830, 1200, 1140),
    ('keypad', 1390, 380, 2210, 1170), ('keypad', 270, 660, 650, 1040), ('keypad', 270, 260, 640, 600),
    ('keypad', 690, 260, 1270, 570),
    ('lamps', 1520, 170, 2400, 1100), ('lamps', 310, 520, 790, 1000), ('lamps', 1350, 560, 1510, 900),
    ('lamps', 770, 960, 1000, 1190),
    ('switches', 1220, 460, 2570, 1040), ('switches', 740, 370, 1090, 720), ('switches', 2240, 150, 2530, 440),
    ('racks', 90, 80, 480, 1450), ('racks', 490, 80, 870, 1450), ('racks', 990, 80, 1760, 500),
    ('racks', 990, 890, 1760, 1250), ('racks', 1880, 80, 2670, 480), ('racks', 1880, 480, 2670, 1020),
    ('racks', 1880, 1020, 2670, 1420),
    ('circuit', 1590, 160, 2620, 1400), ('circuit', 250, 580, 610, 940), ('circuit', 970, 330, 1190, 1090),
    ('pod', 360, 240, 750, 620), ('pod', 1540, 580, 2580, 1380), ('pod', 390, 1020, 990, 1220),
    ('dial', 1520, 1250, 2180, 1440),    # hazard bracket
]
RECESS = (.07, .075, .08)
ROW = .11          # target panel row height (m)
PPM = 1600         # compose resolution (px/m) before fitting a region's atlas rect
STOCK_PPM = 600    # assumed px/m of the stock 1024 boxes (units without measured cells)

# Stock 1024 atlas boxes (every CCA cockpit's UVs sample them): packed generically.
BOXES = [(205, 0, 372, 312), (205, 318, 372, 704), (205, 708, 372, 1016), (372, 0, 570, 155),
         (372, 160, 570, 430), (372, 436, 570, 645), (372, 645, 570, 1016), (575, 0, 770, 341),
         (575, 341, 770, 682), (575, 682, 770, 1024), (775, 0, 1024, 318), (775, 318, 1024, 635),
         (775, 635, 930, 1016), (930, 635, 1024, 1016)]
HAZARD = ((0, 0, 205, 1024), ('hazard', 150, 150, 580, 1390))
# svtank's tub cells (Tools/tankcockpits.py CCA MOSAIC and charts), stock 1024 px, with
# their world size (m): packed over the boxes so its walls show whole instruments at
# their true aspect. 'armor' (lid/frame) gets plain welded plate.
SVTANK = [((378, 2, 566, 152), (.27, .20)), ((379, 162, 566, 305), (.27, .20)),
          ((378, 312, 566, 436), (.27, .20)), ((378, 440, 566, 652), (.27, .20)),
          ((210, 4, 362, 306), (.27, .45)), ((210, 318, 366, 704), (.27, .55)),
          ((210, 708, 366, 1016), (.27, .48)), ((778, 640, 928, 1016), (.27, .43)),
          ((655, 599, 788, 722), (.54, .57))]
STEEL = ('plate', 1560, 160, 1880, 440)    # bare welded steel behind each module
ARMOR = ((650, 61, 757, 236), ('plate', 1300, 110, 2220, 1400))
# Emissive: only lamp glass glows. Marked in master px so the glow follows each
# lamp module wherever the grid places it: circles (cx, cy, r), squares (cx, cy, half).
GLOW = {'lamps': {'circles': [(1759, 439, 121), (2163, 439, 121), (1759, 866, 121), (2163, 866, 121)]},
        'keypad': {'squares': [(1993, 766, 73)]}}


def glow_mask(name, size):
    """Lamp-glass falloff mask in master space (L image)."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    g = np.zeros((h, w), np.float32)
    for cx, cy, r in GLOW.get(name, {}).get('circles', []):
        g = np.maximum(g, np.clip(1 - np.hypot(xx - cx, yy - cy) / r, 0, 1) ** .35)
    for cx, cy, a in GLOW.get(name, {}).get('squares', []):
        g[cy - a:cy + a, cx - a:cx + a] = 1
    return Image.fromarray((g * 255).astype(np.uint8))


def cover(img, w, h):
    """Scale to cover w x h keeping aspect, centre crop."""
    s = max(w / img.width, h / img.height)
    img = img.resize((max(w, round(img.width * s)), max(h, round(img.height * s))), Image.LANCZOS)
    x, y = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


class Packer:
    """Fills a region with rows of whole modules, each picked (unused first) for the
    closest aspect to its cell, framed by their own panel steel, with dark recess seams."""
    def __init__(self, masters):
        self.masters, self.cache, self.masks, self.used = masters, {}, {}, set()

    def src(self, name):
        if name not in self.cache:
            self.cache[name] = Image.open(SRC / self.masters[name]['file']).convert('RGB')
            if name in GLOW: self.masks[name] = glow_mask(name, self.cache[name].size)
        return self.cache[name], self.masks.get(name)

    def pick(self, aspect, peek=False):
        if len(self.used) == len(MODULES): self.used.clear()
        free = [i for i in range(len(MODULES)) if i not in self.used]
        err = lambda i: abs(np.log((MODULES[i][3] - MODULES[i][1]) / (MODULES[i][4] - MODULES[i][2]) / aspect))
        i = min(free, key=lambda i: (err(i), i))
        if not peek: self.used.add(i)
        return i, err(i)

    def window(self, i, aspect):
        """Crop window: the whole module plus a margin of its own panel steel. Never
        widened, so no sliver of a neighbouring instrument enters the cell."""
        name, a, b, c, d = MODULES[i]
        W, H = self.src(name)[0].size
        mx, my = (c - a) * .06, (d - b) * .06
        side = [mx, my, mx, my]                     # left, top, right, bottom
        for o in MODULES:                           # stop short of same-master neighbours
            if o[0] != name or o[1:] == (a, b, c, d): continue
            if o[2] < d and o[4] > b:               # overlaps vertically: limits left/right
                if o[3] <= a: side[0] = min(side[0], a - o[3])
                if o[1] >= c: side[2] = min(side[2], o[1] - c)
            if o[1] < c and o[3] > a:               # overlaps horizontally: limits top/bottom
                if o[4] <= b: side[1] = min(side[1], b - o[4])
                if o[2] >= d: side[3] = min(side[3], o[2] - d)
        return tuple(round(v) for v in (max(0, a - side[0]), max(0, b - side[1]),
                                         min(W, c + side[2]), min(H, d + side[3])))

    def region(self, w, h):
        """Compose a w x h px region (square px in world); returns RGB, glow, recess mask."""
        rgb = Image.new('RGB', (w, h), tuple(round(c * 255) for c in RECESS))
        glow, recess = Image.new('L', (w, h)), np.ones((h, w), bool)
        rows = max(1, round(h / (ROW * PPM)))
        m = max(2, round(.0025 * PPM))
        for r in range(rows):
            y0, y1 = round(h * r / rows), round(h * (r + 1) / rows)
            ra = w / (y1 - y0)
            n = min((1, 2, 3), key=lambda n: self.pick(ra / n, True)[1] - (.25 if n == 2 else 0) + (9 if ra / n < .3 else 0))
            for c in range(n):
                x0, x1 = round(w * c / n), round(w * (c + 1) / n)
                cw, ch = x1 - x0 - 2 * m, y1 - y0 - 2 * m
                i, _ = self.pick(cw / ch)
                win = self.window(i, cw / ch)
                s = min(cw / (win[2] - win[0]), ch / (win[3] - win[1]))
                tw, th = max(1, round((win[2] - win[0]) * s)), max(1, round((win[3] - win[1]) * s))
                px, py = x0 + m + (cw - tw) // 2, y0 + m + (ch - th) // 2
                bg, _ = self.src(STEEL[0])
                rgb.paste(cover(bg.crop(STEEL[1:]), cw, ch), (x0 + m, y0 + m))
                recess[y0 + m:y1 - m, x0 + m:x1 - m] = False
                im, mk = self.src(MODULES[i][0])
                rgb.paste(im.crop(win).resize((tw, th), Image.LANCZOS), (px, py))
                if mk is not None: glow.paste(mk.crop(win).resize((tw, th), Image.LANCZOS), (px, py))
                recess[py:py + th, px:px + tw] = False
        return rgb, glow, recess


def compose():
    pk = Packer(json.loads((SRC / 'provenance.json').read_text())['masters'])
    atlas = Image.new('RGB', (SIZE, SIZE), tuple(round(c * 255) for c in RECESS))
    glow = Image.new('L', (SIZE, SIZE))
    seam = np.ones((SIZE, SIZE), bool)

    def put(box, world=None):
        b = [round(v * K) for v in box]; bw, bh = b[2] - b[0], b[3] - b[1]
        w, h = world or ((box[2] - box[0]) / STOCK_PPM, (box[3] - box[1]) / STOCK_PPM)
        rgb, g, rec = pk.region(round(w * PPM), round(h * PPM))
        atlas.paste(rgb.resize((bw, bh), Image.LANCZOS), b[:2])
        glow.paste(g.resize((bw, bh), Image.LANCZOS), b[:2])
        seam[b[1]:b[3], b[0]:b[2]] = np.asarray(Image.fromarray(rec).resize((bw, bh), Image.NEAREST))

    def plain(box, crop):
        b = [round(v * K) for v in box]
        im, _ = pk.src(crop[0])
        atlas.paste(cover(im.crop(crop[1:]), b[2] - b[0], b[3] - b[1]), b[:2])
        seam[b[1]:b[3], b[0]:b[2]] = False

    plain(*HAZARD)
    for box in BOXES: put(box)
    for box, world in SVTANK: put(box, world)
    plain(*ARMOR)
    d = np.asarray(atlas, np.float32) / 255
    d[seam] = RECESS
    g = np.asarray(glow, np.float32) / 255
    g[seam] = 0
    return d, seam, g


def derive(d, seam, glow):
    lum = d @ np.float32([.299, .587, .114])
    h = np.asarray(Image.fromarray((lum * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    h[seam] -= .3
    # BZBase cotangent frame: encode (-dh/du, -dh/drow, 1) (v runs down the image).
    strength = 6.0
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * .5 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * .5 * strength
    n = np.dstack([-gx, -gy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    normal = (n * .5 + .5)
    mx, mn = d.max(2), d.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    spec = np.clip(.12 + .6 * lum ** 1.5 * (1 - .6 * sat), 0, 1)
    spec[seam] = 0
    glow = np.asarray(Image.fromarray((glow * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)), np.float32) / 255
    emis = d * glow[..., None] * .6
    return normal, np.dstack([spec] * 3), emis


def dxt1_dds(img):
    """DXT1 with a full mip chain (same layout as the stock atlas)."""
    def blocks(im):
        buf = io.BytesIO(); im.save(buf, format='DDS', pixel_format='DXT1'); return buf.getvalue()[128:]
    data, levels, cur = b'', 0, img.convert('RGBA')
    while True:
        data += blocks(cur); levels += 1
        if cur.width == 1 and cur.height == 1: break
        cur = cur.resize((max(1, cur.width // 2), max(1, cur.height // 2)), Image.BOX)
    top = max(8, (img.width // 4) * (img.height // 4) * 8)
    head = struct.pack('<4sI', b'DDS ', 124)
    head += struct.pack('<6I', 0xA1007, img.height, img.width, top, 0, levels) + b'\0' * 44
    head += struct.pack('<2I4s5I', 32, 4, b'DXT1', 0, 0, 0, 0, 0)
    head += struct.pack('<5I', 0x401008, 0, 0, 0, 0)
    return head + data


def img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + .5).astype(np.uint8))


def main():
    d, seam, glow = compose()
    normal, spec, emis = derive(d, seam, glow)
    maps = {'d': img(d), 'n': img(normal), 's': img(spec), 'e': img(emis).resize((1024, 1024), Image.LANCZOS)}
    if '--preview' in sys.argv:
        out = Path(sys.argv[sys.argv.index('--preview') + 1])
        for k, v in maps.items(): v.save(out.with_name(out.stem + '_' + k + '.png'))
        return
    for k, v in maps.items():
        (OUT / f'crcca_cockpit_{k}.dds').write_bytes(dxt1_dds(v))
        print('wrote', OUT / f'crcca_cockpit_{k}.dds', v.size)


if __name__ == '__main__':
    main()
