"""Build 4x stock-faithful replacements for BZ98R's low-res Tier 1 sprite sheets.

Each texture keeps the stock cell layout. The engine stores sprite UVs normalised
by the row's REF size, so a 4x sheet drops in with no spritea.st change.

Per texture:
  sprite_a           every cell rebuilt from its own radial RGBA profile (smooth,
                     round, no stair-steps); sun.0 also gets soft rays.
  r/g/b puff, smoke  radial alpha rebuild plus a soft billow pattern; colour from
                     the stock alpha->RGB palette.
  shock              cell-local smooth upscale (stock is a plain gradient).
  r/g/b flame        cell-local smooth upscale plus flow-aligned streaks; colour
                     from the stock palette.
  magballs           radial glow rebuild plus crisp spikes redrawn at the angles,
                     lengths and strengths of the stock cell's own spikes.
Paletted cells are rescaled to the stock cell's mean alpha, so in-game brightness
and fade timing stay as shipped.

Usage: python Tools/Build-HiResSprites.py [--stock DIR] [--st FILE] [--out DIR] [--only NAME ...]
"""
import argparse, os, re
import numpy as np
from PIL import Image

N = 4  # upscale factor
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
GOG = r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"

PALETTED = {"rpuff", "gpuff", "bpuff", "smoke", "shock", "rflame", "gflame", "bflame"}
MATERIAL_TEXTURE = {"crsun": "sprite_a"}  # CR's sun material samples sprite_a.png
TEXTURES = ["sprite_a", "rpuff", "gpuff", "bpuff", "smoke", "shock", "magballs",
            "rflame", "gflame", "bflame"]


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64)


def cells_for(st_path, tex):
    """Unique cell rects for a texture (several names can share a cell), in
    sheet reading order, which is also the stock frame order."""
    out, seen = [], set()
    for line in open(st_path, encoding="latin1"):
        f = line.split()
        if len(f) >= 9 and f[0].startswith('"'):
            rect = tuple(map(int, f[2:6]))
            if MATERIAL_TEXTURE.get(f[1], f[1]) == tex and rect not in seen:
                seen.add(rect); out.append((f[0].strip('"'), *rect))
    return sorted(out, key=lambda c: (c[2], c[1]))


def palette(img):
    """Stock alpha->RGB lookup (every paletted sheet has residual 0)."""
    a = img.reshape(-1, 4)
    al = a[:, 3].round().astype(int)
    keys = np.unique(al)
    vals = np.array([a[al == k, :3].mean(0) for k in keys])
    x = np.arange(256)
    return np.stack([np.interp(x, keys, vals[:, c]) for c in range(3)], -1)


def apply_palette(alpha, lut):
    a = np.clip(alpha, 0, 255)
    lo = np.floor(a).astype(int); hi = np.minimum(lo + 1, 255); t = (a - lo)[..., None]
    return np.concatenate([lut[lo] * (1 - t) + lut[hi] * t, a[..., None]], -1)


def smooth_up(ch, n=N):
    """Bicubic upscale of one float channel, edge-padded so cells don't bleed."""
    p = np.pad(ch, 2, mode="edge")
    im = Image.fromarray(p.astype(np.float32), "F")
    big = np.asarray(im.resize((p.shape[1] * n, p.shape[0] * n), Image.BICUBIC), np.float64)
    return big[2 * n:-2 * n, 2 * n:-2 * n]


def radial(cell, n=N):
    """Rebuild a round cell from its angular-mean radial profile at n x."""
    h, w = cell.shape[:2]; cy, cx = (h - 1) / 2, (w - 1) / 2
    yy, xx = np.mgrid[0:h, 0:w]; r = np.hypot(yy - cy, xx - cx).ravel()
    step = 0.35
    bins = np.arange(0, r.max() + 0.5, step); idx = np.digitize(r, bins)
    flat = cell.reshape(-1, cell.shape[2]); prof, rc = [], []
    for b in range(1, len(bins) + 1):
        m = idx == b
        if m.any():
            prof.append(flat[m].mean(0)); rc.append(bins[b - 1] + step / 2)
    prof, rc = np.array(prof), np.array(rc)
    k = np.exp(-0.5 * (np.arange(-4, 5) * step / 0.55) ** 2); k /= k.sum()
    pad = np.pad(prof, ((4, 4), (0, 0)), mode="edge")
    prof = np.stack([np.convolve(pad[:, j], k, "valid") for j in range(prof.shape[1])], -1)
    Y, X = np.mgrid[0:h * n, 0:w * n]
    R = np.hypot((Y + 0.5) / n - 0.5 - cy, (X + 0.5) / n - 0.5 - cx)
    out = np.stack([np.interp(R, rc, prof[:, j], right=prof[-1, j]) for j in range(prof.shape[1])], -1)
    # Round off the corners of tiny cells (a 5x5 ping is otherwise a square).
    edge = np.clip((min(w, h) / 2 - R) / 0.75, 0, 1)
    return out * edge[..., None], R


def value_noise(h, w, cell_y, cell_x, rng):
    """Smooth noise in [-1,1] with features about cell_y x cell_x output pixels."""
    gy, gx = int(np.ceil(h / cell_y)) + 3, int(np.ceil(w / cell_x)) + 3
    g = rng.standard_normal((gy, gx)).astype(np.float32)
    big = np.asarray(Image.fromarray(g, "F").resize((gx * cell_x, gy * cell_y), Image.BICUBIC))
    oy, ox = cell_y, cell_x
    z = big[oy:oy + h, ox:ox + w].astype(np.float64)
    return z / (np.abs(z).max() + 1e-9)


def fbm(h, w, base, octaves, rng, aniso=1.0):
    z = np.zeros((h, w)); amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(base / 2 ** o))
        z += amp * value_noise(h, w, s, max(2, int(s * aniso)), rng); tot += amp; amp *= 0.5
    return z / tot


def draw_rays(cell, angs, lens, strs, color, core, n=N):
    """Add soft-edged rays (sun flare / plasma spikes) to an n x cell.
    color: (h,w,3) or (3,) ray colour; core: radius (n x px) where rays start."""
    h, w = cell.shape[:2]; cy, cx = (h - 1) / 2, (w - 1) / 2
    Y, X = np.mgrid[0:h, 0:w]; dy, dx = Y - cy, X - cx
    R = np.hypot(dy, dx) + 1e-6; T = np.arctan2(dy, dx)
    ray = np.zeros_like(R); Rmax = w / 2
    for t, L, s in zip(angs, lens, strs):
        d = np.angle(np.exp(1j * (T - t)))
        perp = np.abs(np.sin(d)) * R
        width = 0.6 * n * (1 + R / Rmax)
        ray += s * (np.cos(d) > 0) * np.exp(-(perp / width) ** 2) * np.clip(1 - R / (L * Rmax), 0, 1) ** 1.6
    ray *= np.clip((R - core) / (6 * n), 0, 1)
    out = cell.copy()
    out[..., :3] = np.clip(out[..., :3] + ray[..., None] * np.asarray(color, float) * 0.55, 0, 255)
    out[..., 3] = np.clip(out[..., 3] + ray * 255 * 0.55, 0, 255)
    return out


def sun_rays(cell, n=N):
    rng = np.random.default_rng(7)
    angs = (np.arange(14) + rng.uniform(-0.3, 0.3, 14)) * 2 * np.pi / 14
    lens = rng.uniform(0.55, 1.0, 14); strs = rng.uniform(0.35, 1.0, 14)
    # Rays start outside the white core, tinted the stock halo's pink-white.
    return draw_rays(cell, angs, lens, strs, [255, 215, 225], 4 * n, n)


def stock_spikes(cell):
    """Angles, lengths (fraction of half-width) and strengths of the star
    spikes in a stock cell: peaks of its brightness minus its radial mean."""
    h, w = cell.shape[:2]; cy, cx = (h - 1) / 2, (w - 1) / 2
    lum = (cell[..., :3] * cell[..., 3:] / 255).sum(-1)
    base, R = radial(lum[..., None], 1)
    res = np.clip(lum - base[..., 0], 0, None)
    Y, X = np.mgrid[0:h, 0:w]; T = np.arctan2(Y - cy, X - cx)
    ring = (R > w * 0.08) & (R < w * 0.45)
    nb = 72; b = ((T + np.pi) / (2 * np.pi) * nb).astype(int) % nb
    prof = np.bincount(b[ring], res[ring], nb) / np.maximum(np.bincount(b[ring], None, nb), 1)
    prof = np.convolve(np.r_[prof[-1:], prof, prof[:1]], [0.25, 0.5, 0.25], "valid")
    thr = prof.mean() + 0.5 * prof.std()
    peaks = [k for k in range(nb) if prof[k] > thr and prof[k] >= prof[k - 1] and prof[k] >= prof[(k + 1) % nb]]
    angs, lens, strs = [], [], []
    for k in peaks:
        t = (k + 0.5) / nb * 2 * np.pi - np.pi
        sel = (b == k) & (res > 0.15 * res[b == k].max())
        angs.append(t); strs.append(prof[k] / prof.max())
        lens.append(min(1.0, (R[sel].max() if sel.any() else w * 0.3) / (w / 2) + 0.1))
    return angs, lens, strs


def upscale_rest(stock, out, cells):
    """Texels outside listed cells: plain smooth upscale."""
    H, W = stock.shape[:2]; mask = np.zeros((H, W), bool)
    for _, u, v, w, h in cells: mask[v:v + h, u:u + w] = True
    big = np.stack([smooth_up(stock[..., c]) for c in range(4)], -1)
    m = np.kron(mask, np.ones((N, N))).astype(bool)
    out[~m] = big[~m]


def build_sprite_a(stock, cells):
    out = np.zeros((stock.shape[0] * N, stock.shape[1] * N, 4))
    upscale_rest(stock, out, cells)
    for name, u, v, w, h in cells:
        src = stock[v:v + h, u:u + w]
        c, _ = radial(src)
        if name == "sun.0":
            c = sun_rays(c)
        elif c[..., 3].mean() > 0:
            # Rounding/smoothing loses coverage on tiny pings and rings; keep stock brightness.
            c[..., 3] = np.clip(c[..., 3] * src[..., 3].mean() / c[..., 3].mean(), 0, 255)
        out[v * N:(v + h) * N, u * N:(u + w) * N] = c
    return out


def build_puff(stock, cells, tex, lut):
    amp = 0.28 if tex == "smoke" else 0.20
    seed = {"smoke": 11, "rpuff": 21, "gpuff": 22, "bpuff": 23}[tex]
    out = np.zeros((stock.shape[0] * N, stock.shape[1] * N, 4))
    upscale_rest(stock, out, cells)
    w0, h0 = cells[0][3], cells[0][4]
    # Billows ~8-10 stock px across: soft lumps, not grain.
    base = fbm(h0 * N * 2, w0 * N * 2, 40, 3, np.random.default_rng(seed))
    for i, (name, u, v, w, h) in enumerate(cells):
        ref = stock[v:v + h, u:u + w, 3]
        a, R = radial(ref[..., None])
        a = a[..., 0]
        # One billow field that slowly expands over the frame sequence, so the
        # sheet animates as one puff growing rather than flickering.
        z = 1 + 0.35 * i / max(1, len(cells) - 1)
        Y, X = np.mgrid[0:h * N, 0:w * N]
        cy, cx = (h * N - 1) / 2, (w * N - 1) / 2
        sy = np.clip(((Y - cy) / z + h * N).astype(int), 0, base.shape[0] - 1)
        sx = np.clip(((X - cx) / z + w * N).astype(int), 0, base.shape[1] - 1)
        n = base[sy, sx]
        # Keep the hot core and the soft rim; billow the body.
        rn = R / (min(w, h) / 2)
        body = np.clip(rn / 0.25, 0, 1) * np.clip((1.0 - rn) / 0.25, 0, 1)
        a = a * (1 + amp * n * (0.4 + 0.6 * body))
        a = np.clip(a * ref.mean() / max(a.mean(), 1e-6), 0, 255)
        out[v * N:(v + h) * N, u * N:(u + w) * N, 3] = a
    out = apply_palette(out[..., 3], lut)
    return out


def build_shock(stock, cells, lut):
    out = np.zeros((stock.shape[0] * N, stock.shape[1] * N, 4))
    upscale_rest(stock, out, cells)
    for _, u, v, w, h in cells:
        out[v * N:(v + h) * N, u * N:(u + w) * N, 3] = np.clip(smooth_up(stock[v:v + h, u:u + w, 3]), 0, 255)
    return apply_palette(out[..., 3], lut)


def build_flame(stock, cells, tex, lut):
    out = np.zeros((stock.shape[0] * N, stock.shape[1] * N, 4))
    upscale_rest(stock, out, cells)
    rng = np.random.default_rng({"rflame": 31, "gflame": 32, "bflame": 33}[tex])
    for name, u, v, w, h in cells:
        ref = stock[v:v + h, u:u + w, 3]
        a = np.clip(smooth_up(ref), 0, 255)
        if name.startswith("beam"):  # flat bands get stretched; keep them clean
            out[v * N:(v + h) * N, u * N:(u + w) * N, 3] = a
            continue
        # Streaks run along the flame (x); features ~1.5 stock px across, ~12 long.
        s = fbm(h * N, w * N, 6, 2, rng, aniso=8)
        t = a / 255
        a = a * (1 + 0.22 * s * 4 * t * (1 - t) / 1.0)
        a = np.clip(a * ref.mean() / max(a.mean(), 1e-6), 0, 255)
        out[v * N:(v + h) * N, u * N:(u + w) * N, 3] = a
    return apply_palette(out[..., 3], lut)


def build_magballs(stock, cells):
    out = np.zeros((stock.shape[0] * N, stock.shape[1] * N, 4))
    upscale_rest(stock, out, cells)
    for _, u, v, w, h in cells:
        ref = stock[v:v + h, u:u + w]
        c, _ = radial(ref)
        angs, lens, strs = stock_spikes(ref)
        # Spikes in the cell's own halo colour, pushed toward white like stock.
        col = c[..., :3] * 0.4 + 255 * 0.6
        c = draw_rays(c, angs, lens, strs, col, 2 * N)
        out[v * N:(v + h) * N, u * N:(u + w) * N] = c
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stock", default=os.path.join(GOG, r"BZ_ASSETS\common\textures\PNGS"))
    ap.add_argument("--st", default=os.path.join(REPO, "Config", "spritea.st"))
    ap.add_argument("--out", default=os.path.join(REPO, "Assets", "Textures"))
    ap.add_argument("--only", nargs="*", default=TEXTURES)
    args = ap.parse_args()
    for tex in args.only:
        stock = load(os.path.join(args.stock, tex + ".png"))
        cells = cells_for(args.st, tex)
        assert cells, f"no spritea.st rows for {tex}"
        lut = palette(stock) if tex in PALETTED else None
        if tex == "sprite_a":
            out = build_sprite_a(stock, cells)
        elif tex.endswith("puff") or tex == "smoke":
            out = build_puff(stock, cells, tex, lut)
        elif tex == "shock":
            out = build_shock(stock, cells, lut)
        elif tex.endswith("flame"):
            out = build_flame(stock, cells, tex, lut)
        else:
            out = build_magballs(stock, cells)
        assert out.shape[:2] == (stock.shape[0] * N, stock.shape[1] * N)
        path = os.path.join(args.out, tex + ".png")
        Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA").save(path, optimize=True)
        print(f"{tex}: {len(cells)} cells -> {path}")


if __name__ == "__main__":
    main()
