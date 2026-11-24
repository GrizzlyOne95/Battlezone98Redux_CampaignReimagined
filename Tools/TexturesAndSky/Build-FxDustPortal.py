"""Build CR's ground-dust and portal-blob sprite sheets (procedural, no third-party art).

Writes Assets/Textures/cr_fx_dust.dds, cr_fx_portal_r.dds and cr_fx_portal_b.dds (BC3, full mips) and,
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
DUST_GAIN = 1.7          # a little denser than stock so the new soft edges still read
DUST_RGB = np.array([196.0, 184.0, 166.0])   # warm neutral; stock is an untinted grey

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


def build_dust(cell=128, frames=32, cols=4):
    rows = frames // cols
    big = np.zeros((rows * cell, cols * cell, 4), np.float32)
    big[..., :3] = DUST_RGB
    n1 = noise3((cell, cell, frames), (cell / 7, cell / 7, 3.0), 101)
    n2 = noise3((cell, cell, frames), (cell / 16, cell / 16, 2.0), 102)
    n3 = noise3((cell, cell, frames), (cell / 40, cell / 40, 1.5), 103)
    Y, X = (np.mgrid[0:cell, 0:cell] + 0.5) / cell - 0.5
    for i in range(frames):
        R = (DUST_EXT[i] / 64.0 / 2.0) if i < len(DUST_EXT) else 0.40 * max(0.25, 1 - (i - 16) / 24.0)
        warp = 0.07 * n1[..., i] + 0.03 * n2[..., i]
        d = np.hypot(X, Y) / max(R, 0.05) + warp
        body = smoothstep(1.0, 0.15, d)
        lumps = np.clip(0.62 + 0.28 * n2[..., i] + 0.12 * n3[..., i], 0.15, 1.2)
        a = body * lumps
        a *= DUST_MEAN[i] * DUST_GAIN / max(a.mean() * 255.0, 1e-6)
        a = np.clip(a, 0, 0.47)   # stock peak alpha is 73/255; keep the puff translucent
        shade = 1.0 + 0.10 * n1[..., i] * body       # volume: lumps slightly lighter / darker
        r, c = divmod(i, cols)
        sl = (slice(r * cell, (r + 1) * cell), slice(c * cell, (c + 1) * cell))
        big[sl][..., :3] = np.clip(DUST_RGB * shade[..., None], 0, 255)
        big[sl][..., 3] = a * 255.0
    return big


def ramp(a, blue):
    g = np.interp(a, RAMP_A, RAMP_G)
    full = np.full_like(a, 255.0)
    return (g, g * 0 + g, full) if blue else (full, g, g)


def build_portal(blue, cell=128, frames=16, cols=4):
    rows = frames // cols
    big = np.zeros((rows * cell, cols * cell, 4), np.float32)
    seed = 202 if blue else 201
    # Both colours share the structure so a portal pair looks like one phenomenon.
    n1 = noise3((cell, cell, frames), (cell / 9, cell / 9, 2.5), 301)
    n2 = noise3((cell, cell, frames), (cell / 22, cell / 22, 1.5), 302)
    Y, X = (np.mgrid[0:cell, 0:cell] + 0.5) / cell - 0.5
    rr = np.hypot(X, Y)
    th = np.arctan2(Y, X)
    for i in range(frames):
        R = float(np.sqrt(PUFF_COV[i] / np.pi)) * 1.15           # stock coverage -> disc radius (cell units)
        d = rr / R
        glow = np.exp(-2.2 * d * d)                        # soft body
        core = np.exp(-(d / 0.28) ** 2)                    # hot core
        # Counter-rotating spiral arms: angle advances per frame, twist grows with radius.
        phase = 0.55 * i
        arms = 0.5 + 0.5 * np.cos(3 * th - 7.0 * d + phase + 0.9 * n2[..., i])
        arms2 = 0.5 + 0.5 * np.cos(5 * th + 5.0 * d - 0.8 * phase + n1[..., i])
        swirl = 0.15 + 0.75 * arms ** 1.5 + 0.35 * arms2 * smoothstep(1.1, 0.3, d)
        turb = np.clip(1.0 + 0.30 * n1[..., i], 0.4, 1.6)
        a = (0.9 * glow * swirl * turb + 0.25 * core) * smoothstep(1.3, 0.8, d)
        # Match the stock energy: mean alpha and a peak ceiling per frame.
        a *= PUFF_MEAN[i] / max(a.mean() * 255.0, 1e-6)
        a = np.clip(a * 255.0, 0, PUFF_MAX[i])
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
    ap.add_argument("--no-dds", action="store_true")
    args = ap.parse_args()
    dust = to_image(build_dust())
    pr = to_image(build_portal(False))
    pb = to_image(build_portal(True))
    if not args.no_dds:
        for name, im in (("cr_fx_dust", dust), ("cr_fx_portal_r", pr), ("cr_fx_portal_b", pb)):
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
