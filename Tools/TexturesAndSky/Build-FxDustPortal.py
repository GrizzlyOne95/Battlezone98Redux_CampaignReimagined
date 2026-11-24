"""Build CR's ground-dust and portal-blob sprite sheets from the project author's generated source frames
(dust_src.jpg, portal_src.jpg: 4x4 grids on black; pass --src-dir). No third-party art.

Writes Assets/Textures/cr_fx_dust.dds, cr_fx_port_r.dds and cr_fx_port_b.dds (BC3, full mips) and,
with --contact-sheet, a stock-versus-CR comparison PNG.

Frame layout and timing follow the stock sheets (measured from BZ_ASSETS dust.png / rpuff.png / bpuff.png):
  dust.0..31      4 cols x 8 rows, alpha-blended, one puff growing then dissipating over dustLifespan
  rpuff/bpuff.0..15  4 x 4, additive, bright at frame 0 and decaying; PortalBlob indexes base + variance + frame
The per-frame mean alpha and extent below are those stock measurements, so the effect keeps the stock
length and density; only the shape and the colour treatment change.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bcdds import save_bc  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
TEX = ROOT / "Assets" / "Textures"
STOCK_DIR = Path(r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\BZ_ASSETS\common\textures\PNGS")

# Stock dust.png (256x512, 64 px cells): mean alpha and extent (px of 64) per frame, measured.
DUST_MEAN = [1.5, 3.2, 5.5, 8.4, 16.1, 13.9, 12.4, 11.3, 7.3, 7.0, 3.1, 3.5, 2.4, 1.8, 1.5, 1.1,
             3.0, 2.2, 1.9, 1.7, 1.6, 1.4, 1.2, 1.2, 1.3, 1.2, 1.0, 0.9, 1.3, 1.1, 0.9, 0.7]
DUST_EXT = [32, 40, 43, 49, 55, 57, 54, 56, 55, 57, 56, 53, 57, 57, 52, 51]
DUST_OPACITY = 0.7        # source clouds are near opaque; stock peak alpha is 0.29
DUST_RGB = np.array([190.0, 180.0, 164.0])   # warm neutral; stock is an untinted grey

PORTAL_GAIN = 1.0
SRC_DIR = Path('C:/Users/iestu/Documents/CR_fx_gen')

# Stock rpuff.png (128x128, 32 px cells): per-frame mean alpha and max alpha, measured.
PUFF_MEAN = [71.2, 60.2, 50.7, 42.5, 35.4, 29.4, 24.3, 19.9, 16.2, 13.0, 10.4, 8.2, 6.4, 4.9, 3.6, 3.6]
PUFF_MAX = [245, 232, 202, 171, 143, 120, 100, 84, 70, 58, 48, 40, 33, 27, 22, 22]
PUFF_COV = [.58, .63, .63, .63, .62, .59, .55, .52, .47, .43, .38, .33, .29, .25, .20, .20]
# Stock alpha -> (G, B) ramp of the red puff (R stays 255); the blue puff swaps R and B.
RAMP_A = [0, 22, 27, 33, 40, 48, 58, 70, 84, 100, 120, 143, 171, 202, 232, 245, 255]
RAMP_G = [0, 6, 7, 9, 11, 14, 17, 23, 30, 40, 56, 80, 117, 164, 215, 237, 245]


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def noise3(shape, sigmas, seed):
    rng = np.random.default_rng(seed)
    n = gaussian_filter(rng.standard_normal(shape), sigmas, mode="wrap")
    return n / n.std()


def load_cells(path, grid=4):
    """Cut the 4x4 source into per-cell luminance arrays (0..1) with a small black point (JPG noise)."""
    L = np.array(Image.open(path).convert("L"), np.float32)
    L = np.clip((L - 6.0) / (255.0 - 6.0), 0, 1)
    n = L.shape[0] // grid
    return [L[(i // grid) * n:(i // grid + 1) * n, (i % grid) * n:(i % grid + 1) * n] for i in range(grid * grid)]


def blob_bbox(v, thr=0.05):
    """Bounding box of the blob (not the fixed cell): where the lightly blurred cell exceeds thr."""
    m = gaussian_filter(v, 3) > thr
    ys, xs = np.nonzero(m)
    if len(ys) == 0:
        return None
    return ys.min(), ys.max() + 1, xs.min(), xs.max() + 1


def recentre(cells, cell, fill=0.94, ystretch=1.0, grow=1.0):
    """Centre every blob on its bounding box and resample. grow=1 keeps the source growth (one common scale);
    grow<1 compresses it (size ~ span**grow) so small early frames still read; ystretch makes wide clouds taller."""
    boxes = [blob_bbox(v) for v in cells]
    spans = [max((b[1] - b[0]) * ystretch, b[3] - b[2]) if b else 0 for b in boxes]
    top = max(spans)
    sizes = [top * (sp / top) ** grow if sp else 0 for sp in spans]
    k_all = cell * fill / top
    out = []
    for v, b, sp, sz in zip(cells, boxes, spans, sizes):
        canvas = np.zeros((cell, cell), np.float32)
        if b:
            k = k_all * sz / sp
            crop = v[b[0]:b[1], b[2]:b[3]]
            h, w = max(1, round(crop.shape[0] * k * ystretch)), max(1, round(crop.shape[1] * k))
            im = np.array(Image.fromarray((crop * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), np.float32) / 255.0
            y0, x0 = (cell - h) // 2, (cell - w) // 2
            ys, xs = max(0, y0), max(0, x0)
            ye, xe = min(cell, y0 + h), min(cell, x0 + w)
            canvas[ys:ye, xs:xe] = im[ys - y0:ye - y0, xs - x0:xe - x0]
        out.append(canvas)
    return out


def build_dust(src, cell=128, frames=32, cols=4):
    """Source clouds -> soft alpha puffs: recentred, contrast lowered, silhouette broken up by noise, flat
    bottom feathered, opacity reduced. The 16 source frames are cross-faded to the stock 32."""
    f16 = recentre(load_cells(src), cell, ystretch=1.5, grow=0.45)
    nz = noise3((cell, cell, 16), (cell / 9, cell / 9, 2.0), 401)
    nz2 = noise3((cell, cell, 16), (cell / 20, cell / 20, 1.5), 402)
    soft = []
    for i, v in enumerate(f16):
        v = 0.55 * v + 0.45 * gaussian_filter(v, cell * 0.025)
        edge = 1.0 - smoothstep(0.35, 0.85, v)
        v = v * np.clip(1.0 + (0.55 * nz[..., i] + 0.25 * nz2[..., i]) * (0.35 + 0.65 * edge), 0.2, 1.4)
        m = v > 0.02
        if m.any():
            rows = np.nonzero(m.any(1))[0]
            top, bot = rows.min(), rows.max()
            t = (np.arange(cell) - top) / max(1, bot - top)
            v = v * (1.0 - 0.7 * smoothstep(0.78, 1.02, t))[:, None]
        soft.append(np.clip(v, 0, 1))
    big = np.zeros((frames // cols * cell, cols * cell, 4), np.float32)
    for j in range(frames):
        u = min(15.0, j * 15 / 22)   # stock dust is visible over roughly its first 22 frames
        i0 = int(u)
        i1 = min(15, i0 + 1)
        w = u - i0
        a = (soft[i0] * (1 - w) + soft[i1] * w) * DUST_OPACITY
        r, c = divmod(j, cols)
        sl = (slice(r * cell, (r + 1) * cell), slice(c * cell, (c + 1) * cell))
        big[sl][..., :3] = DUST_RGB * (0.82 + 0.18 * soft[i0][..., None])
        big[sl][..., 3] = a * 255.0
    return big


def ramp(a, blue):
    g = np.interp(a, RAMP_A, RAMP_G)
    full = np.full_like(a, 255.0)
    return (g, g, full) if blue else (full, g, g)


def build_portal(src, blue, cell=128, frames=16, cols=4):
    """Grey swirl frames -> additive tinted sheet: alpha = luminance, colour from the stock red/blue puff ramp."""
    f = recentre(load_cells(src), cell, fill=1.0)
    big = np.zeros((frames // cols * cell, cols * cell, 4), np.float32)
    for i, v in enumerate(f):
        a = np.clip(v * PORTAL_GAIN * 255.0, 0, 255)
        rch, gch, bch = ramp(a, blue)
        r, c = divmod(i, cols)
        sl = (slice(r * cell, (r + 1) * cell), slice(c * cell, (c + 1) * cell))
        big[sl][..., 0], big[sl][..., 1], big[sl][..., 2], big[sl][..., 3] = rch, gch, bch, a
    return big


def to_image(arr):
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA")


def composite(im, additive, bg):
    base = np.zeros(im.size[::-1] + (3,), np.float32) + np.array(bg, np.float32)
    a = np.array(im, np.float32)
    al = a[..., 3:4] / 255.0
    out = base + a[..., :3] * al if additive else base * (1 - al) + a[..., :3] * al
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def contact_sheet(dest, sheets):
    """sheets: list of (title, stock_path, new_image, additive, bg). Stock left, CR right, same display scale."""
    panels = []
    for title, stock_path, new, additive, bg in sheets:
        stock = Image.open(stock_path).convert("RGBA")
        h = 512
        s = composite(stock, additive, bg).resize((int(stock.width * h / stock.height), h), Image.LANCZOS)
        n = composite(new, additive, bg).resize((int(new.width * h / new.height), h), Image.LANCZOS)
        panels.append((title, s, n))
    pad, top = 16, 28
    w = sum(s.width + n.width + 3 * pad for _, s, n in panels) + pad
    out = Image.new("RGB", (w, 512 + top + 2 * pad), (24, 24, 28))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(out)
    x = pad
    for title, s, n in panels:
        dr.text((x, 6), f"{title}: stock (left)  CR (right)", fill=(230, 230, 230))
        out.paste(s, (x, top + pad)); x += s.width + pad
        out.paste(n, (x, top + pad)); x += n.width + 2 * pad
    out.save(dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contact-sheet", type=Path)
    ap.add_argument("--src-dir", type=Path, default=SRC_DIR)
    ap.add_argument("--no-dds", action="store_true")
    args = ap.parse_args()
    dust = to_image(build_dust(args.src_dir / "dust_src.jpg"))
    pr = to_image(build_portal(args.src_dir / "portal_src.jpg", False))
    pb = to_image(build_portal(args.src_dir / "portal_src.jpg", True))
    if not args.no_dds:
        for name, im in (("cr_fx_dust", dust), ("cr_fx_port_r", pr), ("cr_fx_port_b", pb)):
            save_bc(im, TEX / f"{name}.dds", "BC3_UNORM")
            print("wrote", TEX / f"{name}.dds", im.size)
    if args.contact_sheet:
        contact_sheet(args.contact_sheet, [
            ("dust", STOCK_DIR / "dust.png", dust, False, (96, 90, 82)),
            ("portal red", STOCK_DIR / "rpuff.png", pr, True, (0, 0, 0)),
            ("portal blue", STOCK_DIR / "bpuff.png", pb, True, (0, 0, 0)),
        ])
        print("contact sheet", args.contact_sheet)


if __name__ == "__main__":
    main()
