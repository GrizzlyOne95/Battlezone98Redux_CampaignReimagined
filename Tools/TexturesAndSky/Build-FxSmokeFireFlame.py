"""Build CR's smoke, fireball, engine-flame and construction-blob textures from the project author's generated
source frames (smoke_src.jpg, fireball_src.jpg, flame_src.jpg, construction_src.jpg in --src-dir; 2048 px
sheets, 4x4 grids on black, flame_src is four strips). No third-party art.

Writes (Assets/Textures):
  cr_fx_smoke.dds              4x4 x 128 px, BC3 alpha-blended, white-grey puff; spritea.st rows cr_fx_sml/smm/smd/smb.N
                               reuse it with the stock lsmoke/msmoke/dsmoke/bsmoke tint flags 0..3
  cr_fx_fire.dds               4x8 x 128 px, BC3 additive; spritea.st rows cr_fx_fire.0..31 (stock xsecx.0..31 layout)
  rflame/gflame/bflame.png     the four exhaust strips (top 368 of 512 rows) replaced; the lower rows (bullet and
                               beam sprites that share these sheets) are kept from the existing PNG
  cr_exhaust_cca/_blackdog.png same, for the CCA orange and Black Dog blood-red flames
  cr_fx_cbl_a/s/c/b.dds        256x256 BC3 additive construction-blob puffs, one per faction colour family
The flame sheets keep their names and cell layout, because OpenShim's faction flame swap looks the sprites up by
name (exhaust_r/g/b/o/bd.0). Colour comes from each flame's stock alpha->RGB ramp, so the faction hues do not move.

Per-frame timing follows the stock sheets (measured from BZ_ASSETS smoke.png and xsecxpl.png).
"""
import argparse
import importlib.util
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bcdds import save_bc  # noqa: E402

_spec = importlib.util.spec_from_file_location("fxdp", Path(__file__).with_name("Build-FxDustPortal.py"))
fxdp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fxdp)

ROOT = Path(__file__).resolve().parents[2]
TEX = ROOT / "Assets" / "Textures"
SRC_DIR = Path("C:/Users/iestu/Documents/CR_fx_gen")
STOCK_DIR = fxdp.STOCK_DIR

# Stock smoke.png (128 px, 32 px cells): per-frame mean alpha (0..255), measured.
SMOKE_MEAN = [71.2, 60.2, 50.7, 42.5, 35.4, 29.4, 24.3, 19.9, 16.2, 13.0, 10.4, 8.2, 6.4, 4.9, 3.6, 3.6]
SMOKE_DENSITY = 1.35      # CR smoke is a little denser than stock so the new billows read

# Stock alpha -> RGB knots (alpha, R, G, B) of each engine flame, measured from the sheets (see Build-HiResSprites.py).
FLAME_RAMPS = {
    "rflame": [(0, 255, 4, 1), (24, 255, 23, 6), (40, 255, 39, 11), (72, 255, 72, 24), (104, 255, 104, 43),
               (136, 255, 136, 72), (168, 255, 168, 112), (200, 255, 200, 161), (232, 255, 231, 213), (252, 255, 253, 252), (255, 255, 255, 255)],
    "gflame": [(0, 4, 255, 1), (24, 23, 255, 6), (40, 39, 255, 11), (72, 72, 255, 24), (104, 104, 255, 43),
               (136, 136, 255, 72), (168, 168, 255, 112), (200, 200, 255, 161), (232, 231, 255, 213), (252, 253, 255, 252), (255, 255, 255, 255)],
    "bflame": [(0, 1, 4, 255), (24, 6, 23, 255), (40, 11, 39, 255), (72, 24, 72, 255), (104, 43, 104, 255),
               (136, 72, 136, 255), (168, 112, 168, 255), (200, 161, 200, 255), (232, 213, 231, 255), (252, 252, 253, 255), (255, 255, 255, 255)],
    "cr_exhaust_cca": [(0, 197, 15, 0), (24, 255, 42, 0), (40, 255, 52, 0), (72, 255, 71, 3), (104, 255, 89, 8),
                       (136, 255, 107, 14), (168, 255, 126, 22), (200, 255, 150, 41), (232, 255, 193, 107), (252, 255, 250, 241), (255, 255, 255, 255)],
    "cr_exhaust_blackdog": [(0, 63, 0, 0), (24, 112, 0, 11), (40, 123, 0, 14), (72, 146, 0, 20), (104, 168, 0, 28),
                            (136, 189, 4, 35), (168, 211, 12, 41), (200, 241, 28, 51), (232, 255, 95, 103), (252, 255, 237, 237), (255, 255, 255, 255)],
}
FLAME_CELL_H = 92         # 23 px of the 128 ref sheet at 4x
FLAME_STRIPS = 4
BLOB_FRAME = (6, 7, 8, 9)  # construction_src frames layered into the single blob puff


def ramp_rgb(table, alpha255):
    k = np.array(table, np.float32)
    return np.stack([np.interp(alpha255, k[:, 0], k[:, i]) for i in (1, 2, 3)], -1)


def load_rgb_cells(path, grid=4, black=6.0):
    a = np.array(Image.open(path).convert("RGB"), np.float32)
    a = np.clip((a - black) / (255.0 - black), 0, 1)
    n = a.shape[0] // grid
    return [a[(i // grid) * n:(i // grid + 1) * n, (i % grid) * n:(i % grid + 1) * n] for i in range(grid * grid)]


def recentre_rgb(cells, cell, fill=0.94, grow=1.0):
    """fxdp.recentre for RGB cells: the box comes from the brightest channel, every channel gets one transform."""
    lum = [c.max(-1) for c in cells]
    boxes = [fxdp.blob_bbox(v) for v in lum]
    spans = [max(b[1] - b[0], b[3] - b[2]) if b else 0 for b in boxes]
    top = max(spans)
    k_all = cell * fill / top
    out = []
    for c, b, sp in zip(cells, boxes, spans):
        canvas = np.zeros((cell, cell, 3), np.float32)
        if b:
            sz = top * (sp / top) ** grow
            k = k_all * sz / sp
            crop = c[b[0]:b[1], b[2]:b[3]]
            h, w = max(1, round(crop.shape[0] * k)), max(1, round(crop.shape[1] * k))
            im = np.array(Image.fromarray((crop * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), np.float32) / 255.0
            y0, x0 = (cell - h) // 2, (cell - w) // 2
            ys, xs = max(0, y0), max(0, x0)
            ye, xe = min(cell, y0 + h), min(cell, x0 + w)
            canvas[ys:ye, xs:xe] = im[ys - y0:ye - y0, xs - x0:xe - x0]
        out.append(canvas)
    return out


def edge_fade(cell, width=0.09):
    """Radial window so no frame touches the cell edge (neighbouring cells bleed under bilinear and mips)."""
    y, x = np.mgrid[0:cell, 0:cell].astype(np.float32)
    r = np.hypot(x - (cell - 1) / 2, y - (cell - 1) / 2) / (cell / 2)
    return 1.0 - fxdp.smoothstep(1.0 - width * 2.2, 1.0 - width * 0.4, r)


def build_smoke(src, cell=128):
    f = fxdp.recentre(fxdp.load_cells(src), cell, fill=0.88, grow=0.3)
    win = edge_fade(cell)
    big = np.zeros((4 * cell, 4 * cell, 4), np.float32)
    for i, v in enumerate(f):
        v = np.clip(v, 0, 1) * win
        # soften the billow tops a touch: stock smoke is a soft puff and the engine scales it up a long way
        v = 0.65 * v + 0.35 * gaussian_filter(v, cell * 0.02)
        shade = np.clip(v / max(v.max(), 1e-3), 0, 1)
        alpha = np.clip(v * 1.25, 0, 1) ** 0.9
        want = SMOKE_MEAN[i] * SMOKE_DENSITY / 255.0
        g = np.clip(want / max(alpha.mean(), 1e-4), 0.25, 1.6)
        alpha = np.clip(alpha * g, 0, 0.96)
        rgb = 255.0 * (0.55 + 0.45 * shade)
        r, c = divmod(i, 4)
        sl = (slice(r * cell, (r + 1) * cell), slice(c * cell, (c + 1) * cell))
        big[sl][..., :3] = rgb[..., None]
        big[sl][..., 3] = alpha * 255.0
    return big


def build_fire(src, cell=128, frames=32, cols=4):
    f16 = recentre_rgb(load_rgb_cells(src), cell, fill=0.9, grow=0.6)
    win = edge_fade(cell, 0.1)[..., None]
    f16 = [v * win for v in f16]
    big = np.zeros((frames // cols * cell, cols * cell, 4), np.float32)
    for j in range(frames):
        u = j * 15.0 / (frames - 1)
        i0 = int(u)
        i1 = min(15, i0 + 1)
        w = u - i0
        v = f16[i0] * (1 - w) + f16[i1] * w
        a = v.max(-1)
        hue = v / np.maximum(a[..., None], 1e-3)
        hue = np.where(a[..., None] < 0.02, np.array([1.0, 0.55, 0.2], np.float32), hue)
        r, c = divmod(j, cols)
        sl = (slice(r * cell, (r + 1) * cell), slice(c * cell, (c + 1) * cell))
        big[sl][..., :3] = np.clip(hue, 0, 1) * 255.0
        big[sl][..., 3] = np.clip(a, 0, 1) * 255.0
    return big


def flame_strips(src, w=512, h=FLAME_CELL_H):
    """Four exhaust strips from flame_src.jpg: bright nozzle end on the left, tail fading out on the right."""
    L = np.array(Image.open(src).convert("L"), np.float32)
    L = np.clip((L - 5.0) / 250.0, 0, 1)
    q = L.shape[0] // FLAME_STRIPS
    out = []
    for i in range(FLAME_STRIPS):
        band = L[i * q:(i + 1) * q]
        ys, xs = np.nonzero(gaussian_filter(band, 2) > 0.035)
        crop = band[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        im = Image.fromarray((crop * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
        a = np.array(im, np.float32) / 255.0
        y = (np.arange(h) - (h - 1) / 2) / (h / 2)
        x = np.arange(w) / (w - 1)
        a = a * (1 - fxdp.smoothstep(0.82, 1.0, np.abs(y)))[:, None] * (1 - fxdp.smoothstep(0.80, 1.0, x))[None, :]
        # push the soft wisps up a little: stock flames are much fatter than this smoke-like source
        out.append(np.clip(a * 1.3, 0, 1) ** 0.8)
    return out


def paint_flame(base_png, strips, table):
    im = Image.open(base_png).convert("RGBA")
    arr = np.array(im, np.float32)
    n = arr.shape[0] // 128 * 23 * FLAME_STRIPS  # 368 at 512: the strip rows only
    arr[:n] = 0
    for i, a in enumerate(strips):
        y0 = i * FLAME_CELL_H
        a255 = np.clip(a * 255.0, 0, 255)
        arr[y0:y0 + FLAME_CELL_H, :512, :3] = ramp_rgb(table, a255)
        arr[y0:y0 + FLAME_CELL_H, :512, 3] = a255
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA")


def build_blob(src, table, cell=256):
    """One additive puff: the sparkle-cloud frames layered, recoloured with the faction flame ramp."""
    cells = fxdp.recentre(fxdp.load_cells(src), cell, fill=0.94, grow=0.0)
    v = np.clip(sum(cells[i] for i in BLOB_FRAME) / 2.2, 0, 1) * edge_fade(cell, 0.12)
    v = np.clip(v * 1.15, 0, 1)
    a255 = v * 255.0
    out = np.zeros((cell, cell, 4), np.float32)
    out[..., :3] = ramp_rgb(table, a255)
    out[..., 3] = a255
    return out


def to_image(arr):
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src-dir", type=Path, default=SRC_DIR)
    ap.add_argument("--contact-sheet", type=Path)
    ap.add_argument("--no-write", action="store_true")
    args = ap.parse_args()
    S = args.src_dir
    smoke = to_image(build_smoke(S / "smoke_src.jpg"))
    fire = to_image(build_fire(S / "fireball_src.jpg"))
    strips = flame_strips(S / "flame_src.jpg")
    blobs = {k: to_image(build_blob(S / "construction_src.jpg", FLAME_RAMPS[v]))
             for k, v in (("a", "bflame"), ("s", "cr_exhaust_cca"), ("c", "gflame"), ("b", "cr_exhaust_blackdog"))}
    flames = {n: paint_flame(TEX / f"{n}.png", strips, t) for n, t in FLAME_RAMPS.items()}
    if not args.no_write:
        save_bc(smoke, TEX / "cr_fx_smoke.dds", "BC3_UNORM")
        save_bc(fire, TEX / "cr_fx_fire.dds", "BC3_UNORM")
        for k, im in blobs.items():
            save_bc(im, TEX / f"cr_fx_cbl_{k}.dds", "BC3_UNORM")
        for n, im in flames.items():
            im.save(TEX / f"{n}.png", optimize=True)
        print("wrote smoke, fire, 4 blobs, 5 flames")
    if args.contact_sheet:
        panels = [("smoke", STOCK_DIR / "smoke.png", smoke, False, (70, 70, 74)),
                  ("fireball", STOCK_DIR / "xsecxpl.png", fire, True, (0, 0, 0)),
                  ("flame r", STOCK_DIR / "rflame.png", flames["rflame"].resize((128, 128), Image.LANCZOS), True, (0, 0, 0))]
        fxdp.contact_sheet(args.contact_sheet, panels)
        print("contact sheet", args.contact_sheet)


if __name__ == "__main__":
    main()
