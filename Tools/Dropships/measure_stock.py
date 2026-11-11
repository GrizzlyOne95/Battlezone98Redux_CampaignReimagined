"""Measure the stock Redux faction diffuse DDS (reference only; nothing is copied into the output).
Prints, per texture: k-means palette (weight, RGB), plate/dark medians, thin dark-line weight,
panel-edge density, low-frequency grime variation, fine scratch energy and lamp colours.
Run: python measure_stock.py   (needs numpy + Pillow; DXGI 72 BC1 headers are patched to 71)"""
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths

ROOT = paths.STOCK_TEX
SETS = {
    "CCA": {"svrecy": "DIFF/svrecy_D.dds", "svmuf": "DIFF/svmuf_D.dds", "svtank": "DIFF/svtank_D.dds",
            "svfigh": "DIFF/svfigh_D.dds", "sbspow": "DIFF/sbspow_d.dds"},
    "CRA": {"cvrecy": "TRO/DIFF/cvrecy_d.dds", "cvmuf": "TRO/DIFF/cvmuf_d.dds", "cvtnk": "TRO/DIFF/CVTNK_D.dds",
            "cvfigh": "TRO/DIFF/cvfigh_d.dds", "cvhraz": "TRO/DIFF/cvhraz_d.dds"},
}


def load(path):
    data = bytearray(open(path, "rb").read())
    if bytes(data[84:88]) == b"DX10" and int.from_bytes(data[128:132], "little") == 72:
        data[128:132] = (71).to_bytes(4, "little")
    return Image.open(io.BytesIO(bytes(data))).convert("RGB")


def kmeans(px, k, it=12, seed=1):
    r = np.random.default_rng(seed)
    cen = px[r.choice(len(px), k, replace=False)].astype(np.float32)
    for _ in range(it):
        d = ((px[:, None, :] - cen[None]) ** 2).sum(-1)
        lab = d.argmin(1)
        for j in range(k):
            if (lab == j).any():
                cen[j] = px[lab == j].mean(0)
    w = np.bincount(lab, minlength=k) / len(px)
    o = np.argsort(-w)
    return cen[o], w[o]


def measure(name, path):
    im = load(path)
    s = im.size[0] / 1024.0
    a = np.asarray(im, np.float32)
    lum = a @ np.array([0.299, 0.587, 0.114], np.float32)
    px = a.reshape(-1, 3)
    sub = px[np.random.default_rng(0).choice(len(px), 40000, replace=False)]
    cen, w = kmeans(sub, 7)
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    plate = (lum > 70) & (sat < 0.45)
    dark = lum < 50
    out = [f"{name} {im.size[0]}px  mean lum {lum.mean():.0f}"]
    out.append("  palette: " + "  ".join(f"{wi * 100:.0f}% ({c[0]:.0f},{c[1]:.0f},{c[2]:.0f})" for c, wi in zip(cen, w)))
    out.append(f"  paint-plate median (lum>70, low sat, {plate.mean() * 100:.0f}% px): "
               f"{np.median(a[plate], 0).round(0) if plate.any() else 'n/a'}   dark-slab median ({dark.mean() * 100:.0f}% px): "
               f"{np.median(a[dark], 0).round(0)}")
    # thin dark lines: runs of pixels darker than 0.62 x the 15px local mean, along rows
    loc = np.asarray(Image.fromarray(lum.astype(np.uint8)).filter(ImageFilter.BoxBlur(7)), np.float32)
    thin = (lum < loc * 0.62) & (loc > 60)
    runs = []
    for row in thin[::7]:
        d = np.diff(np.concatenate(([0], row.astype(np.int8), [0])))
        st, en = np.where(d == 1)[0], np.where(d == -1)[0]
        runs += list(en - st)
    runs = np.array([r for r in runs if r <= 10])
    # panel-edge density: strong luminance steps per 256 px scanline (per-1024 scale)
    gx = np.abs(np.diff(lum, axis=1))
    edges = (gx > 28).sum(1).mean() * 256 / lum.shape[1] / s
    low = np.asarray(Image.fromarray(lum.astype(np.uint8)).filter(ImageFilter.GaussianBlur(12)), np.float32)
    hi = np.abs(lum - np.asarray(Image.fromarray(lum.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32))
    pm = plate if plate.any() else np.ones_like(plate)
    out.append(f"  thin dark line weight (median, per-1024 px): {np.median(runs) / s:.1f} (n={len(runs)})   "
               f"edge steps per 256 px (per-1024): {edges:.1f}   grime lowfreq std on plate: {low[pm].std():.1f}   "
               f"fine grain/scratch mean abs: {hi[pm].mean():.2f}")
    # lamps: bright saturated pixels, grouped by hue
    lamp = (mx > 190) & (sat > 0.55)
    if lamp.sum() > 30:
        l = a[lamp]
        hue = np.degrees(np.arctan2(np.sqrt(3) * (l[:, 1] - l[:, 2]), 2 * l[:, 0] - l[:, 1] - l[:, 2])) % 360
        groups = {"red": (hue < 15) | (hue > 340), "amber": (hue >= 15) & (hue < 55), "yellow": (hue >= 55) & (hue < 75),
                  "green": (hue >= 75) & (hue < 170), "cyan": (hue >= 170) & (hue < 215), "blue": (hue >= 215) & (hue < 270)}
        ls = [f"{g} n={m.sum()} ({np.median(l[m], 0).round(0).astype(int).tolist()})" for g, m in groups.items() if m.sum() > 40]
        out.append("  lamp/saturated-bright colours: " + ", ".join(ls))
    print("\n".join(out))


if __name__ == "__main__":
    for fac, d in SETS.items():
        print("==", fac)
        for n, f in d.items():
            p = os.path.join(ROOT, f)
            if os.path.exists(p):
                measure(n, p)
            else:
                print(n, "missing", p)
