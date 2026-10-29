"""Cut botanical plates into flower cards for Achilles (misn17).

Raw plates in, committed outputs out:

* References/Misn17Flowers/cutouts/<card>.png  each graded RGBA cutout, at atlas size
* Assets/Textures/cr17_flowers.dds              the 2048 DXT5 atlas with full mips
* Assets/Models/cr17_fl_<plant>.mesh            crossed-quad clumps, sway-baked
* Materials/cr17_flowers.material               CR17/FlowerWind, CR17/FlowerTallWind
* References/Misn17Flowers/preview.png          every card on a grey-blue ground
* References/Misn17Flowers/source-assets.json   plate hashes, atlas rects, triangles

The plates are public-domain botanical illustrations from Wikimedia Commons,
plus ambientCG's CC0 Foliage006 grass blades (Docs/FOLIAGE_ART_CREDITS.md).
They are not committed. Download them (URLs below) into one folder, unzip the
ambientCG archive into its Foliage006/ subfolder, and pass the folder as
--plates. The build checks every SHA-256 before it reads anything.

Cutting. The scanned paper is estimated locally: a smooth field fitted to the
paper-coloured pixels, so foxing and page gradients key out. Each pixel's
distance from that field becomes alpha. Enclosed pale areas (white petals,
cotton tufts) are filled. Plate furniture (numbers, text, dissections, roots)
is erased with hand-placed boxes and polygons, and only the plant's connected
pieces are kept. Edge colour is un-mixed from the paper, graded toward
Achilles' cold palette, and bled into the transparent texels so that mips do
not fringe.

Plate coordinates in CARDS are in a 900 px preview space: the plate scaled so
that its longer side is 900 px.

--place scatters the cards into Scripts/CRJungle17Sites.lua as render-only
StaticGeometry layers (References/Misn17Flowers/PLACEMENT_PLAN.md). It needs
no plates and is deterministic.
Every Ogre mesh byte comes from the shared libraries (Tools/bzmodellibs.py)
through Build-Misn17Forest.py's submesh helper and Bake-FoliageSway.py.

Usage:
  python Tools/Build-Misn17Flowers.py --plates <download folder> [--debug <folder>]
  python Tools/Build-Misn17Flowers.py --place
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import math
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
ROOT = Path(__file__).resolve().parents[1]
OUT_REF = ROOT / 'References/Misn17Flowers'
ATLAS = 'cr17_flowers.dds'
ATLAS_SIZE = 2048
PAD = 12
SEED = 17170
COMMONS = 'https://upload.wikimedia.org/wikipedia/commons/'

# ----------------------------------------------------------------------------
# Sources. The SHA-256 pins the exact scan the boxes and polygons were drawn on.
PLATES = {
    'harebell': ('01_harebell.jpg', '9863e9c83cd98b1d3eee693831a0626b2a66e5f1e21b468652abe639e3e31ce8',
                 COMMONS + '3/39/Campanula_rotundifolia_%28Thom%C3%A9_Bd.4_1905%2C_BHL-81515%2C_Tafel_561%29_clean.jpg'),
    'fireweed': ('02_fireweed.jpg', '58c254b9e4af2b5108a63bd3e32f6ef1311e68abb2e833b3a8afde8ef1f40c58',
                 COMMONS + '6/66/Illustration_Epilobium_angustifolium0.jpg'),
    'anemone': ('03_anemone.jpg', '9f9f9cb229241480609621db5b3302c43efd76f845b6d9e6cc8c481bc2c7b6b8',
                COMMONS + '1/14/Illustration_Anemone_nemorosa0.jpg'),
    'bunchberry': ('04_bunchberry.png', '13dbc5c0b804e5febb210df00fef6dd1bafd7af2a7efc88c615d07fbac04b5b7',
                   COMMONS + '4/4c/Cornus_canadensis_HdB2.png'),
    'twinflower': ('06_twinflower_sturm.jpg', 'bf9b927a2779a20e04447cb5966c5704edc7c9115183e81213cb4e4ea817320e',
                   COMMONS + '0/0f/Linnaea_borealis_Sturm12046.jpg'),
    'cottongrass': ('07_cottongrass.jpg', 'ecf87e96d85b14a2a2ebe15e1e05497e02cb7ba41cd53ca3e3cf4eafc26172a3',
                    COMMONS + '2/2a/Eriophorum_polystachion_%E2%80%94_Flora_Batava_%E2%80%94_Volume_v1.jpg'),
    'saxifrage': ('08_saxifrage.jpg', '2d3a5e83e8294fc97ba2caeefb7ee349ca9948551306065fc4e74273c3f6651b',
                  COMMONS + 'e/e4/Saxifraga_oppositifolia_Sturm54.jpg'),
    'lupine': ('09_lupine.jpg', '36a370a4a66e654db363d64e3875f18566dcf3834342ac0273df4811032d227b',
               COMMONS + 'a/a2/Lupinus_polyphyllus_Lindley_1827.jpg'),
    'fern_moore': ('10_fern_moore.png', 'f244eee97d15dfd6a29b27a42ea55af8c50be531e28f87c3ebb89ba99078043a',
                   COMMONS + 'a/a7/Athyrium_filix-femina_Moore30.png'),
    'fern_thome': ('11_fern_thome.jpg', '4db4335856c91bd3a3d409e5071698b45d1a06bb4be189217a0ecc5b544a1b00',
                   COMMONS + 'd/dc/Illustration_Athyrium_filix-femina0.jpg'),
    'fescue': ('12_fescue.jpg', 'd4c8e7f049cc7684a455d39ac69e21b6c889c28bdd8f98b7c9975313e830dd66',
               COMMONS + '5/50/Illustration_Festuca_ovina0.jpg'),
    'sedge': ('13_sedge.jpg', '0aa26da033370c0c7338bc156b0bea3194cec32f2b4a3adb1f4d345975beee9b',
              COMMONS + 'b/b2/Carex_vulgaris_%E2%80%94_Flora_Batava_%E2%80%94_Volume_v12.jpg'),
    'blades': ('Foliage006/Foliage006_1K-PNG_Color.png', '4ded0f29ccffbc8a7044f4cf439cc54d366c9db49f7aa9547066c6b16c3aed49',
               'https://ambientcg.com/get?file=Foliage006_1K-PNG.zip'),
    'blades_alpha': ('Foliage006/Foliage006_1K-PNG_Opacity.png', '9961f4b9284d898c5346445ce09e91a212155ad60b785b9d5b21a20bbdc8170a',
                     'https://ambientcg.com/get?file=Foliage006_1K-PNG.zip'),
}

# ----------------------------------------------------------------------------
# Grades. Greens go cooler, deeper and a little greyer; each flower colour is
# steered to the hue it should read as. (hue range lo-hi in degrees, target hue,
# pull 0-1, saturation and value multipliers).
GREEN = dict(lo=55, hi=175, target=138, pull=.45, sat=.72, val=.8)
FLOWERS = {
    'harebell': [(235, 300, 238, .7, 1.25, 1.0)],        # mauve plate -> harebell blue-violet
    'fireweed': [(330, 375, 322, .75, 1.2, .95), (20, 50, 330, .5, .8, .9)],  # pink -> magenta; orange sepals toward it
    'anemone': [(300, 380, 345, 0, .5, 1.05)],           # keep white, mute the pink blush
    'twinflower': [(300, 380, 340, .3, 1.15, 1.0)],      # pink bells
    'cottongrass': [(200, 290, 250, 0, .8, 1.0)],        # spikelets stay blue
    'saxifrage': [(240, 360, 292, .8, 2.2, .9), (0, 30, 320, .5, 1.1, .9)],  # grey-mauve -> purple
    'lupine': [(200, 290, 248, .35, 1.1, .95)],          # violet-blue
}

# ----------------------------------------------------------------------------
# Cards. box/erase/ground in 900 px preview space of the plate.
#   key: (lo, hi) distance from local paper mapped to alpha 0..1
#   fill: largest enclosed pale hole filled, as a share of the box area
#   join: pieces within this many preview px of the plant are kept
#   height: card's real height in metres (the mesh scales the card to it)
CARDS = [
    dict(name='harebell', plate='harebell', box=(150, 5, 455, 818), ground=816,
         erase=[(215, 75, 272, 245), (372, 18, 530, 66), (410, 420, 520, 660), (400, 640, 545, 770),
                [(300, 688), (470, 688), (470, 818), (318, 818), (300, 760)]],
         key=(.07, .17), fill=.004, join=6),
    dict(name='fireweed', plate='fireweed', box=(68, 28, 338, 868), ground=862,
         erase=[(0, 0, 120, 70), (0, 60, 72, 545), [(0, 540), (150, 540), (150, 610), (95, 660), (70, 712), (0, 712)],
                (30, 760, 120, 880), (170, 840, 240, 900),
                [(262, 600), (340, 560), (340, 868), (240, 868), (245, 760)],
                [(60, 440), (100, 440), (135, 470), (170, 500), (170, 560), (150, 620), (60, 620)],
                [(318, 470), (340, 460), (340, 580), (300, 600)]],
         key=(.08, .18), fill=.002, join=5, curls=True),
    dict(name='anemone', plate='anemone', box=(70, 150, 475, 742), ground=738,
         erase=[(320, 540, 480, 710), (395, 425, 510, 560), (395, 90, 520, 230),
                [(266, 417), (266, 350), (284, 350), (289, 396)]],
         key=(.07, .16), fill=.02, join=6, fill_tone=0),
    dict(name='anemone_leaf', plate='anemone', box=(18, 590, 245, 800), ground=800,
         erase=[], key=(.07, .16), fill=.01, join=4, fill_tone=.1),
    dict(name='bunchberry', plate='bunchberry', box=(25, 305, 540, 650), ground=632,
         erase=[], key=(.06, .16), fill=.004, join=6, colorize=True),
    dict(name='bunchberry_top', plate='bunchberry', box=(160, 30, 375, 330), ground=330,
         erase=[], key=(.06, .16), fill=.004, join=6, colorize=True),
    dict(name='twinflower', plate='twinflower', box=(55, 290, 545, 720), ground=712,
         erase=[(370, 680, 480, 760), (40, 690, 130, 800)],
         key=(.07, .17), fill=.004, join=6, fill_tone=.1),
    dict(name='cottongrass', plate='cottongrass', box=(78, 40, 525, 748), ground=742,
         erase=[(365, 570, 530, 800), (395, 95, 530, 215), (78, 40, 135, 110)],
         key=(.05, .13), fill=.03, join=6),
    dict(name='saxifrage', plate='saxifrage', box=(285, 370, 515, 612), ground=606,
         erase=[(446, 584, 466, 612)], key=(.07, .17), fill=.004, join=6, fill_tone=.1,
         paint=[(372, 405, 44, 292, .5), (470, 402, 46, 292, .5)]),
    dict(name='lupine', plate='lupine', box=(85, 25, 668, 858), ground=856,
         erase=[(640, 25, 690, 60)], key=(.06, .15), fill=.004, join=8),
    dict(name='fern', plate='fern_moore', box=(30, 18, 545, 870), ground=868,
         erase=[[(430, 525), (482, 400), (505, 330), (512, 305), (532, 308), (522, 390), (498, 410), (450, 525)], (490, 22, 560, 50)],
         key=(.06, .15), fill=.0005, join=6, tone=(1.25, .68)),
    dict(name='fern_b', plate='fern_thome', box=(20, 20, 550, 830), ground=830,
         erase=[(395, 25, 540, 205), (420, 545, 560, 720), (210, 25, 430, 60), (90, 720, 130, 755)],
         key=(.08, .18), fill=.0005, join=6, rotate=-29, tone=(.95, .9)),
    dict(name='grass', plate='fescue', box=(245, 60, 480, 742), ground=738,
         erase=[(410, 70, 540, 290), (405, 290, 560, 790), (230, 610, 260, 640)],
         key=(.07, .17), fill=.0005, join=5),
    dict(name='grass_seed', plate='fescue', box=(30, 20, 215, 760), ground=752,
         erase=[(15, 20, 130, 60), (58, 710, 78, 736)], key=(.07, .17), fill=.0005, join=5),
    dict(name='sedge', plate='sedge', box=(90, 0, 455, 795), ground=790,
         erase=[], key=(.06, .15), fill=.0005, join=8, speck=16),
]

# Mesh per plant: (mesh name, cards, layout, height m, material).
# layout: cross3 = three vertical quads 60 deg apart; cross2 = two at 90 deg;
# carpet = a near-flat top card plus a vertical cross; fan = fronds leaning out.
MESHES = [
    ('cr17_fl_harebell', ['harebell'], 'cross3', .30, 'small'),
    ('cr17_fl_fireweed', ['fireweed'], 'cross3', 1.25, 'tall'),
    ('cr17_fl_anemone', ['anemone_leaf', 'anemone'], 'carpet', .15, 'small'),
    ('cr17_fl_bunchberry', ['bunchberry_top', 'bunchberry'], 'carpet', .15, 'small'),
    ('cr17_fl_twinflower', ['twinflower', 'twinflower'], 'carpet', .15, 'small'),
    ('cr17_fl_cottongrass', ['cottongrass'], 'cross3', .40, 'small'),
    ('cr17_fl_saxifrage', ['saxifrage', 'saxifrage'], 'carpet', .08, 'small'),
    ('cr17_fl_lupine', ['lupine'], 'cross3', .60, 'tall'),
    ('cr17_fl_fern', ['fern'], 'fan', .75, 'tall'),
    ('cr17_fl_fernb', ['fern_b'], 'fan', .75, 'tall'),
    ('cr17_fl_grass', ['grass'], 'cross3', .40, 'small'),
    ('cr17_fl_grassseed', ['grass_seed'], 'cross2', .50, 'small'),
    ('cr17_fl_sedge', ['sedge'], 'cross3', .45, 'small'),
    ('cr17_fl_tuft', ['tuft'], 'cross3', .35, 'small'),
]


def preview_scale(shape):
    return max(shape[:2]) / 900.0


# ------------------------------------------------------------------ helpers
def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def blur(a, sigma):
    from scipy import ndimage
    return ndimage.gaussian_filter(a, sigma=(sigma, sigma) + (0,) * (a.ndim - 2), mode='nearest')


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r); gm = m & (mx == g) & ~rm; bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return np.stack([h * 60.0, s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0] % 360 / 60.0, hsv[..., 1], hsv[..., 2]
    c = v * s
    x = c * (1 - np.abs(h % 2 - 1))
    z = np.zeros_like(h)
    i = np.floor(h).astype(int) % 6
    r = np.choose(i, [c, x, z, z, x, c]); g = np.choose(i, [x, c, c, x, z, z]); b = np.choose(i, [z, z, x, c, c, x])
    return np.stack([r, g, b], -1) + (v - c)[..., None]


def hue_weight(h, lo, hi, soft=12.0):
    """1 inside [lo, hi] (degrees, hi may exceed 360), easing to 0 over `soft` degrees outside."""
    out = np.zeros_like(h)
    for shift in (-360, 0, 360):
        hh = h + shift
        w = np.clip(np.minimum(hh - (lo - soft), (hi + soft) - hh) / soft, 0, 1)
        out = np.maximum(out, w)
    return out


def steer(hsv, lo, hi, target, pull, sat, val):
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    w = hue_weight(h, lo, hi) * np.clip((s - .06) / .1, 0, 1)
    dh = ((target - h + 180) % 360) - 180
    h2 = h + dh * pull * w
    s2 = np.clip(s * (1 + (sat - 1) * w), 0, 1)
    v2 = np.clip(v * (1 + (val - 1) * w), 0, 1)
    return np.stack([h2, s2, v2], -1)


def grade(rgb, flowers):
    hsv = rgb_to_hsv(rgb)
    for f in flowers:
        hsv = steer(hsv, *f)
    hsv = steer(hsv, GREEN['lo'], GREEN['hi'], GREEN['target'], GREEN['pull'], GREEN['sat'], GREEN['val'])
    out = hsv_to_rgb(hsv)
    # A faint cold cast over everything, and lift the deepest blacks of the ink.
    out = out * np.array([.95, .99, 1.03]) + .015
    return np.clip(out, 0, 1)


def polygon_mask(shape, poly, k):
    from PIL import Image, ImageDraw
    m = Image.new('L', (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(m)
    if len(poly) == 4 and not isinstance(poly[0], (tuple, list)):
        x0, y0, x1, y1 = poly
        d.rectangle([x0 * k, y0 * k, x1 * k, y1 * k], fill=255)
    else:
        d.polygon([(x * k, y * k) for x, y in poly], fill=255)
    return np.asarray(m) > 0


def paper_field(img, seed_mask, sigma):
    """Smooth local paper colour: normalised convolution of the paper-like pixels."""
    w = seed_mask.astype(np.float32)
    num = blur(img * w[..., None], sigma)
    den = blur(w, sigma)[..., None]
    field = num / np.maximum(den, 1e-4)
    # Where no paper was seen nearby, widen until there is.
    weak = den[..., 0] < .02
    if weak.any():
        wide = blur(img * w[..., None], sigma * 4) / np.maximum(blur(w, sigma * 4)[..., None], 1e-4)
        field[weak] = wide[weak]
    return field


# ------------------------------------------------------------------ cutting
def cut_card(card, plates_dir, debug=None):
    from PIL import Image
    from scipy import ndimage
    fname = PLATES[card['plate']][0]
    im = Image.open(plates_dir / fname).convert('RGB')
    full = np.asarray(im, np.float32) / 255
    k = preview_scale(full.shape)
    x0, y0, x1, y1 = [int(round(v * k)) for v in card['box']]
    m = int(40 * k)  # context margin for the paper field
    X0, Y0 = max(0, x0 - m), max(0, y0 - m)
    X1, Y1 = min(full.shape[1], x1 + m), min(full.shape[0], y1 + m)
    img = full[Y0:Y1, X0:X1].copy()
    H, W = img.shape[:2]
    inbox = np.zeros((H, W), bool); inbox[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0] = True

    # Paper: the bright envelope (a grey closing at quarter scale removes ink
    # and paint narrower than ~60 preview px), trusted only where the pixel is
    # close to it, pale and unsaturated; then a smooth field fitted to those.
    lum = img.mean(-1)
    q = 4
    small = img[::q, ::q]
    size = max(3, int(60 * k / q))
    env = np.dstack([ndimage.grey_closing(small[..., c], size=(size, size)) for c in range(3)])
    env = ndimage.zoom(env, (H / env.shape[0], W / env.shape[1], 1), order=1)[:H, :W]
    env = np.pad(env, ((0, H - env.shape[0]), (0, W - env.shape[1]), (0, 0)), mode='edge')
    sat = (img.max(-1) - img.min(-1)) / np.maximum(img.max(-1), 1e-3)
    seed = (np.abs(img - env).max(-1) < .06) & (sat < .32) & (lum > .45)
    seed = ndimage.binary_erosion(seed, iterations=max(1, int(1 * k)))
    field = paper_field(img, seed, sigma=10 * k)
    diff = img - field
    # Chroma difference plus darkening; lighter-than-paper counts a little.
    dist = np.sqrt((diff ** 2).sum(-1)) * .7 + np.clip(-diff.mean(-1), 0, None) * .8
    lo, hi = card['key']
    alpha = np.clip((dist - lo) / (hi - lo), 0, 1)

    hard = alpha > .5
    hard &= inbox
    # Erase plate furniture and everything under the ground line.
    erase = np.zeros((H, W), bool)
    def shift(poly):
        if len(poly) == 4 and not isinstance(poly[0], (tuple, list)):
            return (poly[0] - X0 / k, poly[1] - Y0 / k, poly[2] - X0 / k, poly[3] - Y0 / k)
        return [(x - X0 / k, y - Y0 / k) for x, y in poly]
    for poly in card['erase']:
        erase |= polygon_mask((H, W), shift(poly), k)
    erase[int(card['ground'] * k) - Y0:, :] = True
    if card.get('curls'):
        # Fireweed: plant B's seed-hair curls are a bright straw yellow that plant
        # A never uses outside its orange-tinted sepals.
        hsv = rgb_to_hsv(img)
        curl = (hsv[..., 0] > 45) & (hsv[..., 0] < 75) & (hsv[..., 1] > .35) & (hsv[..., 2] > .55)
        erase |= ndimage.binary_dilation(curl, iterations=max(1, int(1 * k)))
    hard &= ~erase

    # Fill enclosed pale holes (white petals, cotton) up to a size limit.
    holes = ndimage.binary_fill_holes(hard) & ~hard
    lab, n = ndimage.label(holes)
    if n:
        sizes = ndimage.sum(holes, lab, range(1, n + 1))
        # Only holes that are not themselves paper: white petals and cotton
        # differ from the local paper; gaps between leaves do not.
        tone = ndimage.mean(dist, lab, range(1, n + 1))
        limit = card['fill'] * (x1 - x0) * (y1 - y0)
        keep = np.zeros(n + 1, bool); keep[1:] = (sizes <= limit) & (np.asarray(tone) > card.get('fill_tone', .035))
        filled = keep[lab]
    else:
        filled = np.zeros_like(hard)
    solid = hard | filled

    # Keep the plant: the largest piece plus anything within `join` of it.
    lab, n = ndimage.label(solid, structure=np.ones((3, 3)))
    if n == 0:
        raise SystemExit(f"{card['name']}: nothing keyed")
    sizes = ndimage.sum(solid, lab, range(1, n + 1))
    main = lab == (1 + int(np.argmax(sizes)))
    join = max(1, int(card['join'] * k))
    for _ in range(3):
        reach = ndimage.binary_dilation(main, iterations=join)
        touched = np.unique(lab[reach & solid])
        main = np.isin(lab, touched[touched > 0])
    # Specks: tiny pieces that only joined by proximity.
    lab2, n2 = ndimage.label(main, structure=np.ones((3, 3)))
    if n2 > 1:
        s2 = ndimage.sum(main, lab2, range(1, n2 + 1))
        main = np.isin(lab2, 1 + np.nonzero(s2 >= (card.get('speck', 6) * k) ** 2)[0])

    # Soft edge: keyed alpha inside a 1-2 px grow of the kept shape.
    grown = ndimage.binary_dilation(main, iterations=max(1, int(1.2 * k)))
    a = np.where(filled & main, 1.0, alpha) * grown * ~erase
    a = np.where(main & ~filled, np.maximum(a, .55), a)  # solid core stays above the cutoff
    a = blur(a[..., None], .5)[..., 0] * grown
    # Un-mix the paper from edge pixels: I = a*C + (1-a)*P.
    safe = np.maximum(a, .2)[..., None]
    col = np.clip((img - (1 - safe) * field) / safe, 0, 1)
    col = np.where((a > .97)[..., None], img, col)

    if card.get('colorize'):
        col = colorize_bunchberry(col, card, k, X0, Y0)
    else:
        col = grade(col, FLOWERS.get(card['plate'], []))
    if card.get('colorize'):
        col = grade(col, [])
    if card.get('paint') or card.get('tone'):
        hsv = rgb_to_hsv(col)
        yy, xx = np.mgrid[0:H, 0:W]
        px, py = (xx + X0) / k, (yy + Y0) / k
        for cx, cy, r, hue, smin in card.get('paint', []):
            # Recolour a flower the plate printed in a washed-out grey: keep
            # its shading, set its hue, lift its saturation. Yellow anthers stay.
            w = np.clip((r - np.hypot(px - cx, py - cy)) / (r * .2), 0, 1)
            w *= ~((hsv[..., 0] > 40) & (hsv[..., 0] < 70) & (hsv[..., 1] > .4))
            hsv[..., 0] = hsv[..., 0] + (((hue - hsv[..., 0] + 180) % 360) - 180) * w
            hsv[..., 1] = hsv[..., 1] + (np.maximum(hsv[..., 1], smin) - hsv[..., 1]) * w
        s_mul, v_mul = card.get('tone', (1, 1))
        hsv[..., 1] = np.clip(hsv[..., 1] * s_mul, 0, 1)
        hsv[..., 2] = np.clip(hsv[..., 2] * v_mul, 0, 1)
        col = hsv_to_rgb(hsv)

    rgba = np.dstack([col, a]).astype(np.float32)
    ys, xs = np.nonzero(a > .02)
    rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    if card.get('rotate'):
        rgba = rotate_rgba(rgba, card['rotate'])
    if debug:
        save_debug(rgba, Path(debug) / (card['name'] + '.png'))
    return rgba


# Bunchberry: the only plate is an uncoloured engraving. Shade it as a cool
# green ramp, then paint the four-bracted flowers white with a green-yellow eye
# and the berry cluster red. Centres are in preview space of the plate.
BUNCH_FLOWERS = [(68, 465, 30), (380, 330, 32), (455, 465, 30)]
BUNCH_EYES = [(68, 465, 9), (382, 332, 9), (457, 466, 9)]
BUNCH_BERRIES = [(222, 172, 26)]


def colorize_bunchberry(col, card, k, X0, Y0):
    lum = np.clip(col.mean(-1), 0, 1)[..., None]
    dark, mid, light = np.array([.05, .13, .09]), np.array([.22, .38, .26]), np.array([.62, .72, .6])
    t = lum
    g = np.where(t < .5, dark + (mid - dark) * (t / .5), mid + (light - mid) * ((t - .5) / .5))
    H, W = lum.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    px, py = (xx + X0) / k, (yy + Y0) / k
    def disc(cx, cy, r):
        return np.clip((r - np.hypot(px - cx, py - cy)) / (r * .25), 0, 1)[..., None]
    white = np.array([.93, .95, .94]) * (.55 + .5 * t)
    for cx, cy, r in BUNCH_FLOWERS:
        g = g + (white - g) * disc(cx, cy, r)
    for cx, cy, r in BUNCH_EYES:
        g = g + (np.array([.55, .62, .3]) * (.5 + .6 * t) - g) * disc(cx, cy, r)
    for cx, cy, r in BUNCH_BERRIES:
        berry = np.array([.72, .1, .08]) * (.35 + .9 * t)
        w = disc(cx, cy, r) * (lum < .8)
        g = g + (berry - g) * w
    return np.clip(g, 0, 1)


def rotate_rgba(rgba, deg):
    from PIL import Image
    pre = rgba.copy(); pre[..., :3] *= pre[..., 3:]
    chans = [np.asarray(Image.fromarray(pre[..., i]).rotate(deg, Image.BICUBIC, expand=True)) for i in range(4)]
    out = np.dstack(chans)
    out[..., 3] = np.clip(out[..., 3], 0, 1)
    out[..., :3] = np.clip(out[..., :3] / np.maximum(out[..., 3:], 1e-4), 0, 1)
    ys, xs = np.nonzero(out[..., 3] > .02)
    return out[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def make_tuft(plates_dir, debug=None):
    """A grass tuft fanned from ambientCG Foliage006's single blades."""
    from PIL import Image
    from scipy import ndimage
    col = np.asarray(Image.open(plates_dir / PLATES['blades'][0]).convert('RGB'), np.float32) / 255
    alp = np.asarray(Image.open(plates_dir / PLATES['blades_alpha'][0]).convert('L'), np.float32) / 255
    lab, n = ndimage.label(alp > .5, structure=np.ones((3, 3)))
    blades = []
    for sl in ndimage.find_objects(lab):
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if h < 250 or w > h * .35:   # straight single blades only
            continue
        piece = np.dstack([col[sl], alp[sl]])
        blades.append(piece)
    rng = np.random.default_rng(SEED)
    Wc, Hc = 1000, 760
    canvas = np.zeros((Hc, Wc, 4), np.float32)
    order = []
    for i in range(22):
        b = blades[i % len(blades)]
        ang = float(rng.uniform(-38, 38)) * (1 if i % 2 else -1) * (.4 + .6 * (i / 22))
        sc = float(rng.uniform(.55, .95)) * (Hc * .95 / b.shape[0])
        order.append((abs(ang), b, ang, sc, float(rng.normal(0, 18))))
    # Upright blades last, so the tuft's core sits in front.
    for _, b, ang, sc, dx in sorted(order, key=lambda o: -o[0]):
        pre = b.copy(); pre[..., :3] *= pre[..., 3:]
        hh, ww = int(b.shape[0] * sc), max(2, int(b.shape[1] * sc))
        chans = []
        for c in range(4):
            ch = Image.fromarray(pre[..., c]).resize((ww, hh), Image.BICUBIC)
            # Pivot at the blade foot: pad below so rotate(expand) keeps it locatable.
            big = Image.new('F', (ww, hh * 2), 0); big.paste(ch, (0, 0))
            chans.append(np.asarray(big.rotate(ang, Image.BICUBIC, expand=True)))
        r = np.dstack(chans)
        cy, cx = r.shape[0] // 2, r.shape[1] // 2
        ox, oy = int(Wc / 2 + dx - cx), int(Hc - 4 - cy)
        ys0, xs0 = max(0, oy), max(0, ox)
        ys1, xs1 = min(Hc, oy + r.shape[0]), min(Wc, ox + r.shape[1])
        sub = r[ys0 - oy:ys1 - oy, xs0 - ox:xs1 - ox]
        a = np.clip(sub[..., 3:], 0, 1)
        canvas[ys0:ys1, xs0:xs1, :3] = sub[..., :3] + canvas[ys0:ys1, xs0:xs1, :3] * (1 - a)
        canvas[ys0:ys1, xs0:xs1, 3:] = a + canvas[ys0:ys1, xs0:xs1, 3:] * (1 - a)
    a = np.clip(canvas[..., 3:], 0, 1)
    rgb = np.clip(canvas[..., :3] / np.maximum(a, 1e-4), 0, 1)
    # Photo blades are lit lime; bring them to the painted plates' darker range.
    rgb = grade(rgb * .78, [])
    rgba = np.dstack([rgb, a[..., 0]])
    ys, xs = np.nonzero(rgba[..., 3] > .02)
    rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    if debug:
        save_debug(rgba, Path(debug) / 'tuft.png')
    return rgba


def save_debug(rgba, path, ground=(.38, .44, .5), size=900):
    from PIL import Image
    a = rgba[..., 3:]
    out = rgba[..., :3] * a + np.array(ground, np.float32) * (1 - a)
    im = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))
    im.thumbnail((size, size), Image.LANCZOS)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    im.save(path)


# ------------------------------------------------------------------ atlas
def resize_rgba(rgba, w, h):
    from PIL import Image
    pre = rgba.copy(); pre[..., :3] *= pre[..., 3:]
    chans = [np.asarray(Image.fromarray(pre[..., i]).resize((w, h), Image.LANCZOS)) for i in range(4)]
    out = np.dstack(chans)
    out[..., 3] = np.clip(out[..., 3], 0, 1)
    out[..., :3] = np.clip(out[..., :3] / np.maximum(out[..., 3:], 1e-4), 0, 1)
    return out


# Relative on-texture height of each card: tall plants get the most texels.
CARD_WEIGHT = {'fireweed': 1.0, 'lupine': .95, 'fern': 1.0, 'fern_b': .95, 'harebell': .85,
               'cottongrass': .8, 'sedge': .85, 'grass': .8, 'grass_seed': .85, 'tuft': .55,
               'anemone': .6, 'anemone_leaf': .35, 'bunchberry': .5, 'bunchberry_top': .45,
               'twinflower': .55, 'saxifrage': .45}


def shelf_pack(sizes, size):
    """sizes: {name: (w, h)} -> {name: (x, y)} or None. Tallest first, left to right."""
    order = sorted(sizes, key=lambda n: (-sizes[n][1], n))
    x = y = shelf = 0
    pos = {}
    for n in order:
        w, h = sizes[n]
        if x + w + PAD > size:
            x, y, shelf = 0, y + shelf + PAD, 0
        if w + PAD > size or y + h + PAD > size:
            return None
        pos[n] = (x + PAD, y + PAD)
        x += w + PAD
        shelf = max(shelf, h)
    return pos


def build_atlas(cards):
    lo, hi = 100.0, 4000.0
    best = None
    for _ in range(40):
        mid = (lo + hi) / 2
        sizes = {n: (max(8, int(c.shape[1] / c.shape[0] * mid * CARD_WEIGHT[n])), int(mid * CARD_WEIGHT[n])) for n, c in cards.items()}
        pos = shelf_pack(sizes, ATLAS_SIZE)
        if pos:
            lo, best = mid, (sizes, pos)
        else:
            hi = mid
    sizes, pos = best
    atlas = np.zeros((ATLAS_SIZE, ATLAS_SIZE, 4), np.float32)
    rects, scaled = {}, {}
    for n, c in cards.items():
        w, h = sizes[n]; x, y = pos[n]
        r = resize_rgba(c, w, h)
        atlas[y:y + h, x:x + w] = r
        scaled[n] = r
        rects[n] = (x, y, w, h)
    return bleed(atlas), rects, scaled


def bleed(rgba):
    """Push-pull: fill every transparent texel with the average of nearby opaque colour."""
    from PIL import Image
    a = rgba[..., 3]
    w = (a > .02).astype(np.float32)
    levels = [(rgba[..., :3] * w[..., None], w)]
    while levels[-1][1].shape[0] > 1:
        c, ww = levels[-1]
        h2, w2 = c.shape[0] // 2, c.shape[1] // 2
        c = c[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2, 3).sum((1, 3))
        ww = ww[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2).sum((1, 3))
        levels.append((c, ww))
    fill = levels[-1][0] / np.maximum(levels[-1][1][..., None], 1e-6)
    for c, ww in reversed(levels[:-1]):
        up = np.repeat(np.repeat(fill, 2, 0), 2, 1)
        up = np.pad(up, ((0, c.shape[0] - up.shape[0]), (0, c.shape[1] - up.shape[1]), (0, 0)), mode='edge')
        own = c / np.maximum(ww[..., None], 1e-6)
        fill = np.where((ww > 0)[..., None], own, up)
    out = rgba.copy()
    out[..., :3] = np.where((a > .02)[..., None], rgba[..., :3], fill)
    return out


def write_preview(scaled, path):
    from PIL import Image, ImageDraw, ImageFont
    ground = (97, 112, 128)
    cell_h, gap = 300, 16
    items = sorted(scaled.items())
    tiles = []
    for n, c in items:
        k = cell_h / c.shape[0]
        w = max(1, int(c.shape[1] * k))
        r = resize_rgba(c, w, cell_h)
        a = r[..., 3:]
        out = r[..., :3] * a + np.array(ground) / 255 * (1 - a)
        tiles.append((n, Image.fromarray((out * 255).astype(np.uint8))))
    try:
        font = ImageFont.truetype('arial.ttf', 20)
    except OSError:
        font = ImageFont.load_default()
    # A cell is as wide as its card or its label, whichever is wider.
    cell_w = {n: max(t.width, int(font.getlength(n)) + 8) for n, t in tiles}
    cols_w = 1600
    rows, row, x = [], [], 0
    for n, t in tiles:
        if x + cell_w[n] + gap > cols_w and row:
            rows.append(row); row, x = [], 0
        row.append((n, t)); x += cell_w[n] + gap
    rows.append(row)
    H = len(rows) * (cell_h + 40 + gap) + gap
    sheet = Image.new('RGB', (cols_w, H), ground)
    d = ImageDraw.Draw(sheet)
    y = gap
    for row in rows:
        x = gap
        for n, t in row:
            sheet.paste(t, (x, y))
            d.text((x, y + cell_h + 8), n, fill=(235, 240, 245), font=font)
            x += cell_w[n] + gap
        y += cell_h + 40 + gap
    sheet.save(path, optimize=True)


# ------------------------------------------------------------------ meshes
def quad(c, u, v, w, h, uv):
    """Corners of a card: c foot centre, u width axis, v up axis (unit), uv=(u0,v0,u1,v1)."""
    u0, v0, u1, v1 = uv
    p = [c - u * w / 2, c + u * w / 2, c + u * w / 2 + v * h, c - u * w / 2 + v * h]
    t = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
    return p, t


def clump(layout, cards, height, rects, rng):
    """-> positions, normals, uvs, indices. Y up, foot at the origin, metres."""
    up = np.array([0., 1, 0])
    quads = []
    def uv(n):
        x, y, w, h = rects[n]
        # Half-texel inset so bilinear never reads the neighbouring card.
        return ((x + .5) / ATLAS_SIZE, (y + .5) / ATLAS_SIZE, (x + w - .5) / ATLAS_SIZE, (y + h - .5) / ATLAS_SIZE)
    def aspect(n):
        return rects[n][2] / rects[n][3]
    yaw0 = float(rng.uniform(0, math.pi))
    sink = -.04 * height
    if layout in ('cross2', 'cross3'):
        n = 2 if layout == 'cross2' else 3
        name = cards[0]
        for i in range(n):
            yaw = yaw0 + i * math.pi / n + float(rng.uniform(-.12, .12))
            u = np.array([math.cos(yaw), 0, math.sin(yaw)])
            side = np.cross(u, up)
            lean = float(rng.uniform(-.08, .08))
            v = up * math.cos(lean) + side * math.sin(lean)
            off = side * float(rng.uniform(-.05, .05)) * height
            h = height * float(rng.uniform(.9, 1.05))
            quads.append(quad(off + up * sink, u, v, h * aspect(name), h, uv(name)) + (side,))
    elif layout == 'carpet':
        top, side_card = cards
        # A near-flat card (tilted 12-25 deg) carrying the top view or the mat ...
        flat_tilt = math.radians(12 if top != side_card else 28)
        w = height * 2.4 if top != side_card else height * 2.2 * aspect(top) ** .5
        hgt = w / aspect(top)
        u = np.array([math.cos(yaw0), 0, math.sin(yaw0)])
        fwd = np.cross(up, u)
        v = fwd * math.cos(flat_tilt) + up * math.sin(flat_tilt)
        c = -v * hgt / 2 + up * .01
        quads.append(quad(c, u, v, w, hgt, uv(top)) + (np.cross(v, u),))
        # ... and a vertical cross of the side view through it.
        for i in range(2):
            yaw = yaw0 + math.pi / 4 + i * math.pi / 2 + float(rng.uniform(-.1, .1))
            uu = np.array([math.cos(yaw), 0, math.sin(yaw)])
            h = height * float(rng.uniform(.9, 1.05))
            quads.append(quad(up * sink, uu, up, h * aspect(side_card), h, uv(side_card)) + (np.cross(uu, up),))
    elif layout == 'fan':
        name = cards[0]
        n = 5
        for i in range(n):
            yaw = yaw0 + i * math.tau / n + float(rng.uniform(-.2, .2))
            out = np.array([math.cos(yaw), 0, math.sin(yaw)])
            tang = np.cross(up, out)
            lean = math.radians(float(rng.uniform(22, 42)))
            v = up * math.cos(lean) + out * math.sin(lean)
            # Frond length so the tallest point is about the plant's height.
            length = height / math.cos(lean) * float(rng.uniform(.85, 1.05))
            foot = out * .04 * height + up * sink
            quads.append(quad(foot, tang, v, length * aspect(name), length, uv(name)) + (np.cross(v, tang),))
    else:
        raise ValueError(layout)
    pos, nrm, uvs, idx = [], [], [], []
    for p, t, fn in quads:
        fn = fn / np.linalg.norm(fn)
        # Upward-biased normals: both faces of a double-sided card light alike,
        # like the ground cover, and the clump reads as one rounded mass.
        n_ = up + .35 * fn
        n_ /= np.linalg.norm(n_)
        b = len(pos)
        pos += [list(q) for q in p]; uvs += t; nrm += [list(n_)] * 4
        idx += [b, b + 1, b + 2, b, b + 2, b + 3]
    return np.array(pos), np.array(nrm), np.array(uvs), np.array(idx)


MATERIALS_HEAD = '''// Generated by Tools/Build-Misn17Flowers.py. Achilles' flowers, ferns and grasses:
// cutout cards from public-domain botanical plates and ambientCG's CC0 Foliage006
// (Docs/FOLIAGE_ART_CREDITS.md), on one 2048 DXT5 atlas.
// Like the ground cover they sway through CR17/CutoutWind (meshes baked by
// Tools/Bake-FoliageSway.py); the wind reaches them once CRJungle17.lua registers
// these materials with Foliage.Register. Until then they stand still.
import * from "cr17_surface.material"
import * from "cr17_wind.material"
'''

CASTER = '''material CR17/CutoutCaster/FlowerTallWind
{
	technique
	{
		pass
		{
			scene_blend one one
			scene_blend_op min
			depth_check off
			depth_write off
			cull_hardware none
			cull_software none
			vertex_program_ref CR17_Wind_Caster_vertex
			{
				param_named windShape float4 0.5 1.2 0.1 6.5
			}
			fragment_program_ref CR17_Cutout_Caster_fragment
			{
				param_named cutoutParams float4 0.45 0 0 0
			}
			texture_unit diffuseMap
			{
				texture %s
			}
		}
	}
}
''' % ATLAS

FLOWER = '''material CR17/%s : CR17/CutoutWind
{
	set_texture_alias DiffuseMap %s
	set_texture_alias NormalMap cr17_flat.dds
	set_texture_alias SpecularMap cr17_black.dds
	set_texture_alias EmissiveMap cr17_black.dds
	set $cutoutParams "0.45 0.5 0.6 %d"
	set $diffuse "0.84 0.9 0.92"
	set $ambient "0.88 0.93 0.95"
	set $specular "0.08 0.09 0.1"
	set $shininess "16"
	set $caster "%s"
	set $windShape "%s"
}
'''
MATERIAL = {'small': 'FlowerWind', 'tall': 'FlowerTallWind'}


# ------------------------------------------------------------------ build
def build(plates_dir, debug=None):
    from PIL import Image
    import bzmodellibs
    sys.path.insert(0, str(bzmodellibs.toolbox_root()))
    from battlezone.meshes import ogre
    def load(name, path):
        spec = importlib.util.spec_from_file_location(name, ROOT / 'Tools' / path)
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        return mod
    forest = load('forest17', 'Build-Misn17Forest.py')
    sway = load('sway', 'Bake-FoliageSway.py')

    for key, (fname, digest, _) in PLATES.items():
        got = sha(plates_dir / fname)
        if got != digest:
            raise SystemExit(f'{fname}: SHA-256 {got} != pinned {digest}')

    cards = {}
    for card in CARDS:
        cards[card['name']] = cut_card(card, plates_dir, debug)
        print('cut', card['name'], cards[card['name']].shape[1::-1])
    cards['tuft'] = make_tuft(plates_dir, debug)

    atlas, rects, scaled = build_atlas(cards)
    textures = ROOT / 'Assets/Textures'
    img = Image.fromarray((np.clip(atlas, 0, 1) * 255 + .5).astype(np.uint8), 'RGBA')
    forest.dds(textures / ATLAS, img, 'DXT5')
    atlas_sha = forest.check_not_blank(textures / ATLAS)

    cut_dir = OUT_REF / 'cutouts'
    cut_dir.mkdir(parents=True, exist_ok=True)
    for n, r in scaled.items():
        Image.fromarray((np.clip(r, 0, 1) * 255 + .5).astype(np.uint8), 'RGBA').save(cut_dir / (n + '.png'), optimize=True)
    write_preview(scaled, OUT_REF / 'preview.png')

    mat = [MATERIALS_HEAD, CASTER]
    mat.append(FLOWER % (MATERIAL['small'], ATLAS, ATLAS_SIZE, 'CR17/NoShadowCaster', '0.45 1.6 0.07 8.0'))
    mat.append(FLOWER % (MATERIAL['tall'], ATLAS, ATLAS_SIZE, 'CR17/CutoutCaster/FlowerTallWind', '0.5 1.2 0.1 6.5'))
    (ROOT / 'Materials/cr17_flowers.material').write_text('\n'.join(mat), newline='\n')

    models = ROOT / 'Assets/Models'
    rng = np.random.default_rng(SEED)
    mesh_info = {}
    for name, use, layout, height, kind in MESHES:
        pos, nrm, uv, idx = clump(layout, use, height, rects, rng)
        material = 'CR17/' + MATERIAL[kind]
        mesh = ogre.OgreMesh(version='MeshSerializer_v1.100', endian='little',
                             submeshes=[forest.submesh(material, pos, nrm, uv, idx, None)])
        path = models / (name + '.mesh')
        ogre.write_mesh(mesh, path)
        sway.bake(path, 'plant', material, material, ogre)
        back = ogre.read_mesh(path)
        tris = sum(len(s.indices) for s in back.submeshes) // 3
        lo, hi = pos.min(0), pos.max(0)
        mesh_info[name] = {'cards': use, 'layout': layout, 'height_m': height, 'material': material,
                           'triangles': tris, 'bounds_min': [round(float(v), 3) for v in lo],
                           'bounds_max': [round(float(v), 3) for v in hi],
                           'sha256': sha(path)}

    report = {
        'plates': {k: {'file': f, 'sha256': d, 'url': u} for k, (f, d, u) in PLATES.items()},
        'atlas': {'file': ATLAS, 'size': ATLAS_SIZE, 'format': 'DXT5 with mips', 'sha256': atlas_sha,
                  'rects_xywh': {n: list(map(int, r)) for n, r in sorted(rects.items())}},
        'meshes': mesh_info,
    }
    OUT_REF.mkdir(parents=True, exist_ok=True)
    (OUT_REF / 'source-assets.json').write_text(json.dumps(report, indent=2) + '\n', newline='\n')
    print(json.dumps({n: (m['layout'], m['height_m'], m['triangles']) for n, m in mesh_info.items()}, indent=1))


# ---------------------------------------------------------------- placement
# Render-only StaticGeometry layers in Scripts/CRJungle17Sites.lua, beside the
# mire ground cover. Tile types are mat >> 12 on the 20 m grid: 0 open grass,
# 1 forest, 2 rock. Distances are to the jungle's tree sites, to the drawn water
# (watermask plus river strip) and to the forest pass's cr17_frock rocks.
#
# The cards are botanical size (a harebell is 0.3 m), which a tank cockpit
# cannot read beside 3 m mire ferns, so each species has its own game scale.
PLACE_SEED = SEED + 1
PLAY = (780, 3640, 98430, 101740)
TALL_DISTANCE, SMALL_DISTANCE = 220, 150
# name: (meshes, clumps, min spacing m, per clump, clump radius m, scale range, tall)
SPECIES = {
    'grasses':     (['cr17_fl_grass', 'cr17_fl_grassseed', 'cr17_fl_tuft'], 260, 25, (5, 9), 3.0, (1.5, 2.2), False),
    'harebell':    (['cr17_fl_harebell'], 70, 45, (3, 7), 2.5, (1.7, 2.4), False),
    'carpets':     (['cr17_fl_anemone', 'cr17_fl_bunchberry', 'cr17_fl_twinflower'], 180, 30, (5, 9), 2.5, (2.2, 3.2), False),
    'lupine':      (['cr17_fl_lupine'], 50, 70, (3, 5), 2.5, (1.3, 1.8), True),
    'fireweed':    (['cr17_fl_fireweed'], 35, 80, (4, 8), 3.5, (1.0, 1.4), True),
    'cottongrass': (['cr17_fl_cottongrass'], 65, 30, (5, 9), 3.0, (1.5, 2.2), False),
    'sedge':       (['cr17_fl_sedge'], 75, 25, (4, 8), 2.5, (1.5, 2.2), False),
    'saxifrage':   (['cr17_fl_saxifrage'], 70, 30, (3, 6), 1.8, (2.4, 3.4), False),
    'ferns':       (['cr17_fl_fern', 'cr17_fl_fernb'], 200, 20, (3, 6), 2.5, (1.3, 2.0), True),
}


def place():
    """Write the cr17_fl_ layers into Scripts/CRJungle17Sites.lua (idempotent)."""
    from scipy import ndimage
    from scipy.spatial import cKDTree
    import bzmodellibs
    sys.path.insert(0, str(bzmodellibs.toolbox_root()))
    from battlezone.bzn.bz1 import read_bzn
    from battlezone.terrain.hg2 import read_hg2
    from battlezone.terrain.mat import read_mat
    spec = importlib.util.spec_from_file_location('forest17', ROOT / 'Tools/Build-Misn17Forest.py')
    forest = importlib.util.module_from_spec(spec); spec.loader.exec_module(forest)

    sites = forest.read_sites()
    _, h = read_hg2(ROOT / 'Missions/misn17.hg2'); ground = h.astype(float) * .1
    tiles = read_mat(ROOT / 'Missions/misn17.mat', 4, 4)
    def height(x, z):  # bilinear on the 5 m grid
        fz, fx = (z - 97280) / 5, x / 5
        iz, ix = int(fz), int(fx); tz, tx = fz - iz, fx - ix
        g = ground[iz:iz + 2, ix:ix + 2]
        return float(g[0, 0] * (1 - tx) * (1 - tz) + g[0, 1] * tx * (1 - tz) + g[1, 0] * (1 - tx) * tz + g[1, 1] * tx * tz)
    def slope(x, z):
        iz, ix = round((z - 97280) / 5), round(x / 5)
        return math.hypot(ground[iz, ix + 1] - ground[iz, ix - 1], ground[iz + 1, ix] - ground[iz - 1, ix]) / 10
    def tile(x, z): return int(tiles[int((z - 97280) / 20), int(x / 20)]) >> 12

    # Keep-outs: the forest pass's guards (bzn objects) and route points.
    bzn = read_bzn(ROOT / 'Missions/misn17cr.bzn')
    guards = cKDTree(np.array([o.fields['transform'].value[9::2] for o in bzn.objects
                               if o.prjid != 'sfield' and not o.label.startswith(('cr17_tree', 'cr17_ice'))]))
    route = cKDTree(np.array([pt for p in bzn.paths for pt in p['points'].value], float).reshape(-1, 2))
    def clear(x, z): return not guards.query_ball_point((x, z), 30) and not route.query_ball_point((x, z), 18)

    # Water: the run-length mask plus the river strip, as Build-Misn17Forest.py builds it.
    wm = sites['watermask']
    water = np.zeros(ground.shape, bool)
    for r, runs in enumerate(wm['rows']):
        for a, n in zip(runs[::2], runs[1::2]):
            water[wm['firstRow'] + r, a:a + n] = True
    river = sites['river']
    for (ax, az), (bx, bz) in zip(river, river[1:]):
        for t in np.linspace(0, 1, 40):
            iz, ix = round((az + (bz - az) * t - 97280) / 5), round((ax + (bx - ax) * t) / 5)
            water[iz - 1:iz + 2, ix - 1:ix + 2] = True
    dwater = ndimage.distance_transform_edt(~water) * 5  # metres from a dry cell centre to water
    def wet_dist(x, z): return float(dwater[round((z - 97280) / 5), round(x / 5)])

    trees = cKDTree(np.array([t['position'][::2] for t in sites['trees'] if t['label'].startswith('cr17_tree')]))
    rocks = cKDTree(np.array([p[::2][:2] for l in sites['layers'] if l['mesh'].startswith('cr17_frock') for p in l['instances']]))
    def dtree(x, z): return float(trees.query((x, z))[0])

    def centre_ok(kind, x, z, rng):
        typ, s, dt = tile(x, z), slope(x, z), dtree(x, z)
        if kind == 'grasses':      # open grass, thicker along the forest edge
            return typ == 0 and s < .5 and (6 <= dt <= 20 or rng.random() < .35)
        if kind == 'harebell':
            return typ == 0 and s < .47 and dt >= 8
        if kind == 'lupine':
            return typ == 0 and s < .36 and dt >= 12
        if kind == 'fireweed':     # clearings only
            return typ == 0 and s < .36 and dt >= 25
        if kind == 'carpets':      # forest floor and edges
            return typ == 1 and s < .5 and 3 <= dt <= 15
        if kind == 'ferns':        # under the firs
            return typ == 1 and s < .6 and dt <= 10
        if kind == 'cottongrass':  # wet ground above the waterline
            return typ != 2 and s < .4 and 2 <= wet_dist(x, z) <= 12
        if kind == 'sedge':        # banks
            return s < .5 and 1.5 <= wet_dist(x, z) <= 8
        if kind == 'saxifrage':    # rock tiles and beside the rocks
            return s < .9 and (typ == 2 or bool(rocks.query_ball_point((x, z), 4)))
        raise KeyError(kind)

    def plant_ok(kind, x, z):
        if not (PLAY[0] <= x <= PLAY[1] and PLAY[2] <= z <= PLAY[3]):
            return False
        if water[round((z - 97280) / 5), round(x / 5)] or slope(x, z) > .9:
            return False
        if kind in ('sedge', 'cottongrass') and wet_dist(x, z) < 1.5:
            return False
        return dtree(x, z) >= (2.5 if kind == 'ferns' else 2.0)  # off the trunks

    rng = np.random.default_rng(PLACE_SEED)
    placed = {}       # mesh -> [[x, y, z, yaw, scale]]
    centres = []      # every species' clump centres, so patches do not pile up
    report = {}
    for kind, (meshes, target, spacing, (nlo, nhi), radius, (slo, shi), _) in SPECIES.items():
        own, n_inst, tries = [], 0, 0
        while len(own) < target and tries < 60000:
            tries += 1
            x, z = float(rng.uniform(PLAY[0], PLAY[1])), float(rng.uniform(PLAY[2], PLAY[3]))
            if any(math.hypot(x - a, z - b) < spacing for a, b in own):
                continue
            if any(math.hypot(x - a, z - b) < 6 for a, b in centres):
                continue
            if not centre_ok(kind, x, z, rng) or not clear(x, z):
                continue
            own.append((x, z)); centres.append((x, z))
            for _ in range(int(rng.integers(nlo, nhi + 1))):
                r, a = radius * math.sqrt(rng.random()), rng.uniform(0, math.tau)
                px, pz = x + r * math.cos(a), z + r * math.sin(a)
                if not plant_ok(kind, px, pz):
                    continue
                mesh = meshes[int(rng.integers(len(meshes)))] + '.mesh'
                scale = float(rng.uniform(slo, shi))
                placed.setdefault(mesh, []).append([round(px, 2), round(height(px, pz) - .03 * scale, 2), round(pz, 2),
                                                    round(float(rng.uniform(0, math.tau)), 3), round(scale, 3)])
                n_inst += 1
        report[kind] = {'clumps': len(own), 'instances': n_inst}

    # One layer per mesh and 1152 m tile, like the rocks. They go straight after
    # the mire cover, so a Build-Misn17Forest.py rerun (which keeps every
    # non-rock, non-ice layer and appends ice then rocks) leaves the order alone.
    tall = {m + '.mesh' for meshes, *_, t in SPECIES.values() if t for m in meshes}
    by_tile = {}
    for mesh, inst in placed.items():
        for p in inst:
            by_tile.setdefault((mesh, math.floor((p[0] - 2048) / 1152), math.floor((p[2] - 99328) / 1152)), []).append(p)
    flowers = [{'mesh': key[0], 'distance': TALL_DISTANCE if key[0] in tall else SMALL_DISTANCE, 'instances': by_tile[key]}
               for key in sorted(by_tile)]
    old = [l for l in sites['layers'] if not l['mesh'].startswith('cr17_fl_')]
    cut = next((i for i, l in enumerate(old) if not l['mesh'].startswith('cr17_mire_')), len(old))
    sites['layers'] = old[:cut] + flowers + old[cut:]
    (ROOT / 'Scripts/CRJungle17Sites.lua').write_text(forest.SITES_HEAD + forest.lua_value(sites) + '\n', newline='\n')
    forest.read_sites()  # round-trips

    info = json.loads((OUT_REF / 'source-assets.json').read_text())
    tris = {n + '.mesh': m['triangles'] for n, m in info['meshes'].items()}
    out = {'species': report, 'layers': len(flowers), 'instances': sum(len(v) for v in placed.values()),
           'triangles': sum(tris[m] * len(v) for m, v in placed.items()),
           'by_mesh': {m: len(v) for m, v in sorted(placed.items())}}
    print(json.dumps(out, indent=1))
    return out


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--plates', type=Path, help='folder holding the downloaded plates')
    ap.add_argument('--debug', type=Path, help='write per-card cutout previews here')
    ap.add_argument('--only', nargs='*', help='cut only these cards into --debug and stop')
    ap.add_argument('--place', action='store_true', help='write the cr17_fl_ layers into Scripts/CRJungle17Sites.lua')
    a = ap.parse_args()
    if a.place:
        place()
    elif a.plates is None:
        ap.error('--plates is required unless --place')
    elif a.only is not None:
        for c in CARDS:
            if not a.only or c['name'] in a.only:
                cut_card(c, a.plates, a.debug)
        if not a.only or 'tuft' in a.only:
            make_tuft(a.plates, a.debug)
    else:
        build(a.plates, a.debug)
