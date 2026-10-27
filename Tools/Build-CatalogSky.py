"""Bake the catalog sky's star index and Milky Way textures.

Stars are not painted into a texture. Each star lands in a cell of a six-face
grid (512 cells a face, faces stacked vertically in one 512x3072 RGBA8 PNG),
and the texel stores where in the cell the star sits, its magnitude and its
colour. Shaders/CR_catalogsky-sm4.hlsl reads one texel per pixel and draws the
star as a fixed-size point, so stars stay sharp at any resolution for a few
hundred KB.

Face f = 2*axis + (component < 0); face coordinates are the next two
components (cyclic) over the major one, both in [-1, 1]:
x -> (y, z), y -> (z, x), z -> (x, y). The shader repeats this exactly.

A star is also written into neighbouring cells, including across face edges,
with its offset measured from that cell's centre (at most OFFSET_RANGE
cells), so its point is not clipped at a cell border. A cell keeps the star
that contributes most to it.

Sources (not stored in the repository):
  --bsc5      Yale Bright Star Catalogue binary (tdc-www.harvard.edu/catalogs/BSC5)
  --milkyway  NASA/GSFC SVS Deep Star Maps 2020 milkyway_2020_4k (svs.gsfc.nasa.gov/4851),
              converted to a 16-bit PNG or float .npy, equatorial J2000
  --random N  placeholder field for plumbing tests
"""
import argparse
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CELLS = 512
OFFSET_RANGE = 2.0      # stored offsets cover [-2, 2] cells
SPLAT_RADIUS = 1.5      # cells a star reaches beyond its own
MAG_LIMIT = 8.0         # code 1 is this magnitude; brighter stars count up
MAG_STEP = 24.0         # codes per magnitude
BV_MIN, BV_SPAN = -0.5, 2.5

# B-V by spectral class letter and subclass 0 (Allen's Astrophysical Quantities, main sequence).
SPECTRAL_BV = {"O": -0.32, "B": -0.30, "A": 0.00, "F": 0.30, "G": 0.58, "K": 0.81, "M": 1.40,
               "C": 2.00, "N": 2.00, "R": 1.50, "S": 1.60, "W": -0.30}
SPECTRAL_NEXT = "OBAFGKM"


def spectral_bv(code):
    letter = code[:1].upper()
    if letter not in SPECTRAL_BV:
        return 0.60
    bv = SPECTRAL_BV[letter]
    if letter in SPECTRAL_NEXT[:-1] and code[1:2].isdigit():
        nxt = SPECTRAL_BV[SPECTRAL_NEXT[SPECTRAL_NEXT.index(letter) + 1]]
        bv += (nxt - bv) * int(code[1]) / 10.0
    return bv


def read_bsc5(path):
    data = Path(path).read_bytes()
    star0, star1, starn, stnum, mprop, nmag, nbent = struct.unpack_from("<7i", data, 0)
    count = abs(starn)
    stars = []
    for i in range(count):
        offset = 28 + i * nbent
        _, ra, dec = struct.unpack_from("<fdd", data, offset)
        spectral = data[offset + 20:offset + 22].decode("ascii", "replace")
        mag = struct.unpack_from("<h", data, offset + 22)[0] / 100.0
        if ra == 0.0 and dec == 0.0:
            continue  # the catalogue's few non-stellar placeholders
        stars.append((ra, dec, mag, spectral_bv(spectral)))
    return stars


def random_stars(count, seed=7):
    rng = np.random.default_rng(seed)
    z = rng.uniform(-1, 1, count)
    ra = rng.uniform(0, 2 * math.pi, count)
    # Star counts grow about 10^(0.6 m); sample that between -1.5 and the limit.
    lo, hi = 10 ** (0.6 * -1.5), 10 ** (0.6 * MAG_LIMIT)
    mag = np.log10(rng.uniform(lo, hi, count)) / 0.6
    bv = rng.normal(0.6, 0.45, count)
    return list(zip(ra, np.arcsin(z), mag, bv))


def direction(ra, dec):
    return np.array([math.cos(dec) * math.cos(ra), math.cos(dec) * math.sin(ra), math.sin(dec)])


def bake_index(stars):
    index = np.zeros((6 * CELLS, CELLS, 4), np.uint8)
    score = np.zeros((6 * CELLS, CELLS), np.float64)
    reach = int(math.ceil(SPLAT_RADIUS + 0.5))
    for ra, dec, mag, bv in stars:
        if mag > MAG_LIMIT:
            continue
        d = direction(ra, dec)
        flux = 10.0 ** (-0.4 * mag)
        mag_code = int(round(1 + (MAG_LIMIT - mag) * MAG_STEP))
        bv_code = int(round(np.clip((bv - BV_MIN) / BV_SPAN, 0, 1) * 255))
        for axis in range(3):
            if abs(d[axis]) < 0.5:
                continue  # beyond 60 degrees from this axis, the star cannot reach its faces
            face = 2 * axis + (1 if d[axis] < 0 else 0)
            u = d[(axis + 1) % 3] / abs(d[axis])
            v = d[(axis + 2) % 3] / abs(d[axis])
            cu, cv = (u * 0.5 + 0.5) * CELLS, (v * 0.5 + 0.5) * CELLS
            for y in range(int(cv) - reach, int(cv) + reach + 1):
                for x in range(int(cu) - reach, int(cu) + reach + 1):
                    if not (0 <= x < CELLS and 0 <= y < CELLS):
                        continue
                    ou, ov = cu - (x + 0.5), cv - (y + 0.5)
                    distance = math.hypot(ou, ov)
                    if distance > SPLAT_RADIUS + 0.71 or abs(ou) >= OFFSET_RANGE or abs(ov) >= OFFSET_RANGE:
                        continue
                    s = flux / (0.25 + distance * distance)
                    row = face * CELLS + y
                    if s <= score[row, x]:
                        continue
                    score[row, x] = s
                    index[row, x] = (round((ou / OFFSET_RANGE * 0.5 + 0.5) * 255),
                                     round((ov / OFFSET_RANGE * 0.5 + 0.5) * 255), mag_code, bv_code)
    return index


def bake_milkyway(source, size, exposure):
    path = Path(source)
    if path.suffix == ".npy":
        linear = np.load(path).astype(np.float32)
    else:
        image = np.asarray(Image.open(path)).astype(np.float32)
        linear = image / (65535.0 if image.max() > 255 else 255.0)
    linear = linear[..., :3]
    height, width = linear.shape[:2]
    # Box-filter down to the target width, then encode sRGB for an 8-bit texture.
    factor = width // size
    if factor > 1:
        linear = linear[:height // factor * factor, :width // factor * factor]
        linear = linear.reshape(height // factor, factor, width // factor, factor, 3).mean(axis=(1, 3))
    c = np.clip(linear * exposure, 0, 1)
    srgb = np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)
    return Image.fromarray(np.round(srgb * 255).astype(np.uint8), "RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--bsc5", type=Path)
    group.add_argument("--random", type=int)
    parser.add_argument("--milkyway", type=Path)
    parser.add_argument("--milkyway-width", type=int, default=2048)
    parser.add_argument("--milkyway-exposure", type=float, default=1.0)
    parser.add_argument("--out", type=Path, default=ROOT / "Assets/Textures")
    args = parser.parse_args()

    stars = read_bsc5(args.bsc5) if args.bsc5 else random_stars(args.random)
    index = bake_index(stars)
    Image.fromarray(index, "RGBA").save(args.out / "crsky_stars.png", optimize=True)
    used = int((index[..., 2] > 0).sum())
    print(f"crsky_stars.png: {len(stars)} stars, {used} cells used")
    if args.milkyway:
        bake_milkyway(args.milkyway, args.milkyway_width, args.milkyway_exposure).save(
            args.out / "crsky_milkyway.png", optimize=True)
        print("crsky_milkyway.png written")


if __name__ == "__main__":
    main()
