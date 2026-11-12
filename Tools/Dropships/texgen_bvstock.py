"""'bdrv' atlas (Black Dog dropship bvdrop): the avdrop model retextured. Same atlas layout, trim strips and painter
(texgen_avstock.py) with a darker Black Dog palette measured from the stock Redux DDS bvrecy/bvmuf/bvtank/bvslf/bvhaul/bvturr
(README, measure_stock.py): weathered blue-teal grey plate over near-black slabs (the green `hull` texture), dark red panels
(`hullw`, which the model puts on every side-facing flank; stock panel reds measure (68-123, 13-30, 10-27), (88,18,17) here), extra
red/black hazard patches, red accent bands, cyan/yellow/red/green lamps.
Insignia come from the user's four high-res Black Dog images (read at paint time from the Google Drive archive, paths in the env vars
BZ_BDOG_LOGO, BZ_BDOG_STENCIL, BZ_BDOG_HOUND, BZ_BDOG_HOUND2; never copied into the repo, the generated textures are the shipped asset):
BdogLogoHD1.png (star disc) in the `star` cell = main marking on both pod flanks; BlackDog-HDLogo.png (black disc, yellow ring, hound,
red collar) in the `roundel` cell = ramp faces; BdogLogoHD2.png (star and bones on near-white, keyed to alpha by flood fill) in the
`dish` cell = wing tops (build_dropship.py) and the small `hatch` cell; BlackDog-BasedOffOriginal.png (alternate hound) in the
`chevron` cell = nacelle sides. Discs are cut with a circular alpha mask, feathered, and get the same light grime as the rest.
Everything else is generated in code; Total Command's bvdropcox
renders were only looked at for the dark-armour proportion.
Writes tex/bdrv*.png and out/bdrv*.dds.  Run: python texgen_bvstock.py"""
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import texgen as T
import texgen_avstock as A

FAC = "bdrv"
A.PAL.update(
    base=(44, 56, 52), mottle=(30, 38, 35), darkpanel=(22, 26, 24), accent=(86, 22, 20), trim=(10, 10, 9),
    light=(222, 214, 60), red=(228, 32, 30), emblem=(206, 206, 196), emblem2=(30, 30, 28),
    stripe_a=(184, 26, 22), stripe_b=(12, 12, 11), glow=(0, 150, 230), window=(110, 190, 210), number="17")
A.RUST = np.array((96, 58, 36), np.float32)
A.DIRT = np.array((16, 18, 16), np.float32)
A.METAL = np.array((92, 100, 96), np.float32)
A.HAZ_EXTRA = 0.12
A.star_pts = lambda cx, cy, R, rot=0: [(-50, -50)] * 3        # no stars: the Black Dog roundel is painted instead

# ---- the two logo images (reference files on the user's drive; override with the env vars)
_IMG = r"C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Archives\Images" + "\\"
LOGO_FILE = os.environ.get("BZ_BDOG_LOGO", _IMG + "BdogLogoHD1.png")             # main emblem: disc on a black background
LOGO_CIRCLE = (511, 766, 462)      # disc centre x, y and radius (px) measured from BdogLogoHD1.png (1024 x 1536), just inside the black rim
STENCIL_FILE = os.environ.get("BZ_BDOG_STENCIL", _IMG + "BdogLogoHD2.png")       # secondary marking: star + bones on near-white
HOUND_FILE = os.environ.get("BZ_BDOG_HOUND", _IMG + "BlackDog-HDLogo.png")       # black disc, yellow ring, hound, red collar
HOUND_CIRCLE = (512, 515, 445)
HOUND2_FILE = os.environ.get("BZ_BDOG_HOUND2", _IMG + "BlackDog-BasedOffOriginal.png")   # alternate hound on a grey vignette
HOUND2_CIRCLE = (513, 486, 424)
_IMGS = {}


def _load(path, what):
    if not os.path.isfile(path):
        sys.exit(f"Black Dog {what} not found: {path} (set BZ_BDOG_LOGO / BZ_BDOG_STENCIL / BZ_BDOG_HOUND / BZ_BDOG_HOUND2)")
    if path not in _IMGS:
        _IMGS[path] = Image.open(path).convert("RGB")
    return _IMGS[path]


def disc(path, circle, px, what):
    """A logo image cut by a circular alpha mask on its rim into an RGBA roundel of `px` pixels (edge feathered about 1.5 px)."""
    cx, cy, r = circle
    sq = _load(path, what).crop((cx - r, cy - r, cx + r, cy + r)).resize((px, px), Image.LANCZOS)
    ss = 4
    m = Image.new("L", (px * ss, px * ss), 0)
    ImageDraw.Draw(m).ellipse((0, 0, px * ss - 1, px * ss - 1), fill=255)
    m = m.resize((px, px), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.75))
    out = sq.convert("RGBA")
    out.putalpha(m)
    return out


_STENCIL = []


def stencil(px, seed=0):
    """HD2 star + bones as an RGBA image fitted into a px x px square: the near-white background is keyed out by flood filling inward
    from the border over pixels brighter than 246 (the grey halo round the bones stops the fill, so the white bones survive)."""
    if not _STENCIL:
        im = _load(STENCIL_FILE, "stencil")
        g = im.convert("L").point(lambda v: 255 if v >= 246 else 0)
        for pt in ((0, 0), (g.width - 1, 0), (0, g.height - 1), (g.width - 1, g.height - 1)):
            if g.getpixel(pt) == 255:
                ImageDraw.floodfill(g, pt, 128, thresh=0)
        a = g.point(lambda v: 0 if v == 128 else 255).filter(ImageFilter.GaussianBlur(1.0))
        rgba = im.convert("RGBA")
        rgba.putalpha(a)
        _STENCIL.append(rgba)
    src = _STENCIL[0]
    k = px / max(src.size)
    sz = (max(1, int(src.width * k)), max(1, int(src.height * k)))
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(src.resize(sz, Image.LANCZOS), ((px - sz[0]) // 2, (px - sz[1]) // 2))
    return out


def place(rgb, height, emb, cx, cy, seed):
    """Alpha-blend the roundel into the float atlas at (cx, cy), with light grime and scuffs so it matches the weathering."""
    a = np.asarray(emb, np.float32) / 255.0
    px = a.shape[0]
    x0, y0 = int(cx - px // 2), int(cy - px // 2)
    col, al = a[..., :3] * 255.0, a[..., 3:4]
    wear = 0.88 + 0.16 * A.noise(px, px, 5, seed)[..., None]
    col = col * wear
    sl = (slice(y0, y0 + px), slice(x0, x0 + px))
    rgb[sl] = rgb[sl] * (1 - al) + col * al
    height[sl] = np.where(al[..., 0] > 0.5, 0.75, height[sl])


_orig_finish = T.finish_maps


def _finish(rgb, height, spec, emit, prefix, *args, **kw):
    if prefix.endswith("trim") and height is not None:
        a, b = T.TRIM["cells"]
        cells = T.CELLS
        for name in ("roundel", "dish", "chevron"):      # plain dark plating under the markings (the avdrop disc/dish/slash art is not wanted)
            x0 = cells.index(name) * 256
            n = A.noise(256, 256, 7, 5 + x0)[..., None]
            rgb[a:b, x0:x0 + 256] = np.array((30, 38, 35), np.float32) * (1 + 0.08 * n)
            height[a:b, x0:x0 + 256] = 0.55
            if emit is not None:
                emit[a:b, x0:x0 + 256] = 0
        jobs = (("star", disc(LOGO_FILE, LOGO_CIRCLE, 236, "logo")),
                ("roundel", disc(HOUND_FILE, HOUND_CIRCLE, 236, "hound logo")),
                ("dish", stencil(236)),
                ("chevron", disc(HOUND2_FILE, HOUND2_CIRCLE, 236, "alternate hound logo")))
        for name, img in jobs:
            x0 = cells.index(name) * 256
            place(rgb, height, img, x0 + 128, a + 128, 17 + x0)
        x0 = cells.index("hatch") * 256                   # the hatch cell's small star becomes the small stencil
        place(rgb, height, stencil(64), x0 + 128, a + 84, 91)
    return _orig_finish(rgb, height, spec, emit, prefix, *args, **kw)


T.finish_maps = _finish


def red_plating(seed):
    """Dark-red plating for `hullw`: the same painter with panel reds measured from the stock Black Dog DDS."""
    keep = {k: A.PAL[k] for k in ("base", "mottle", "darkpanel")}
    A.PAL.update(base=(88, 18, 17), mottle=(62, 12, 12), darkpanel=(44, 10, 10))
    try:
        return A.stock_plating(seed)
    finally:
        A.PAL.update(keep)


def main():
    for f, what in ((LOGO_FILE, "logo"), (STENCIL_FILE, "stencil"), (HOUND_FILE, "hound"), (HOUND2_FILE, "hound2")):
        _load(f, what)   # fail before any output is written
    p = os.path.join(T.OUT, FAC)
    cv = A.stock_plating(540)
    T.finish_maps(cv.rgb.copy(), cv.height, cv.spec, None, p + "hull")
    red = red_plating(541)
    wrgb, wemit = T.add_windows(red.rgb.copy(), A.PAL, 640)
    T.finish_maps(wrgb, None, None, wemit * 0.8, p + "hullw")
    A.stock_trim(740, p + "trim")
    A.to_dds(sorted(glob.glob(p + "hull*.png") + glob.glob(p + "trim*.png")))


if __name__ == "__main__":
    main()
