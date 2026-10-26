"""Bake the Titan sky maps read by CR_titansky (Shaders/CR_titansky.hlsl).

  crsky_titan_haze.png    1024x1024 RGB, tileable haze densities:
                          R  broad zonal haze bands, long and soft along +u (the
                             wind direction), that roll slowly overhead;
                          G  billowing haze banks: rounded, lumpy masses;
                          B  fine methane-cloud streaks, rare and stretched.
  crsky_saturn.png        512x256 RGB, Saturn's cloud tops in plate carree
                          (north up, longitude 0 at the centre, so the wrap is
                          on the far side of the globe the shader draws).
  crsky_saturn_rings.png  2048x4 RGBA, the rings' radial profile from 1.110 to
                          2.331 Saturn equatorial radii (66,900 to 140,500 km):
                          rgb the ring material's colour, a its opacity.

Everything is synthesised; nothing is downloaded. Saturn's bands follow the
zones and belts of the Cassini-era true-colour views (pale gold equatorial
zone, tan belts, a bluish-grey high north with the polar hexagon at 78 N); the
ring radii are the published edges of the C, B and A rings, the Cassini
Division, the Encke and Keeler gaps and the F ring, with seeded ringlet noise.
As Tools/Build-VenusSkyClouds.py, the haze fields are made in the frequency
domain and warped with wrap-around, so the map tiles exactly.

Usage: python Tools/Build-TitanSky.py [--out-dir DIR] [--seed N]
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter1d, map_coordinates

ROOT = Path(__file__).resolve().parent.parent
SATURN_RADIUS_KM = 60268.0
RING_INNER_KM = 66900.0
RING_OUTER_KM = 140500.0


def spectral(rng, size, beta, low, high, stretch=(1.0, 1.0)):
    """Periodic noise with a k^-beta spectrum between low and high cycles per tile."""
    ky = np.fft.fftfreq(size)[:, None] * size
    kx = np.fft.rfftfreq(size)[None, :] * size
    k = np.sqrt((kx * stretch[0]) ** 2 + (ky * stretch[1]) ** 2)
    band = np.clip((k - low) / max(low, 1e-6), 0, 1) * np.exp(-((k / high) ** 2))
    amp = np.where(k > 0, band / np.maximum(k, 1e-6) ** beta, 0)
    phase = rng.standard_normal(amp.shape) + 1j * rng.standard_normal(amp.shape)
    field = np.fft.irfft2(amp * phase, s=(size, size))
    return (field - field.mean()) / field.std()


def warp(field, du, dv):
    size = field.shape[0]
    v, u = np.mgrid[0:size, 0:size].astype(np.float64)
    return map_coordinates(field, [v + dv, u + du], order=1, mode="grid-wrap")


def soft(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def build_haze(seed, size=1024):
    rng = np.random.default_rng(seed)
    scale = size / 1024.0
    wu = spectral(rng, size, 2.4, 1, 8) * 60 * scale
    wv = spectral(rng, size, 2.4, 1, 8) * 22 * scale
    # Bands: very broad, smooth and zonal; Titan's haze has no sharp edges.
    bands = soft(warp(spectral(rng, size, 2.4, 1, 24, stretch=(5.0, 1.0)), wu, wv), -1.6, 1.6)
    # Banks: billow noise, softer than Venus's cells.
    lumps = np.abs(spectral(rng, size, 2.0, 2, 24)) + 0.4 * np.abs(spectral(rng, size, 1.6, 8, 70))
    lumps = warp(lumps, spectral(rng, size, 2.2, 1, 6) * 30 * scale, spectral(rng, size, 2.2, 1, 6) * 30 * scale)
    banks = soft(lumps, 0.2, 1.8)
    # Streaks: rare methane cloud, thin and stretched, mostly empty.
    streak = warp(spectral(rng, size, 1.5, 4, 180, stretch=(10.0, 1.0)), wu * 0.5, wv * 0.5)
    streaks = soft(streak, 0.9, 2.6)
    rgb = np.stack([bands, banks, streaks], axis=-1)
    return Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


# Saturn's zones and belts: planetographic latitude (degrees) and linear-ish
# sRGB colour, interpolated in between. North is the later-Cassini season, its
# high latitudes bluish-grey to gold; south a duller tan.
SATURN_BANDS = [
    (-90, (0.56, 0.50, 0.42)), (-75, (0.62, 0.55, 0.44)), (-62, (0.70, 0.62, 0.48)),
    (-48, (0.76, 0.67, 0.51)), (-38, (0.71, 0.61, 0.46)), (-30, (0.80, 0.70, 0.53)),
    (-20, (0.74, 0.63, 0.47)), (-12, (0.82, 0.73, 0.56)), (-5, (0.90, 0.82, 0.64)),
    (0, (0.92, 0.85, 0.67)), (5, (0.90, 0.82, 0.64)), (12, (0.80, 0.70, 0.52)),
    (19, (0.72, 0.61, 0.45)), (27, (0.82, 0.73, 0.56)), (36, (0.75, 0.66, 0.50)),
    (46, (0.80, 0.73, 0.58)), (56, (0.70, 0.67, 0.60)), (66, (0.62, 0.63, 0.62)),
    (74, (0.56, 0.58, 0.60)), (78, (0.40, 0.42, 0.44)), (82, (0.52, 0.54, 0.56)),
    (90, (0.44, 0.44, 0.46)),
]


def build_saturn(seed, width=512, height=256):
    rng = np.random.default_rng(seed + 1)
    lat = 90.0 - (np.arange(height) + 0.5) * 180.0 / height
    keys = np.array([b[0] for b in SATURN_BANDS], dtype=np.float64)
    cols = np.array([b[1] for b in SATURN_BANDS], dtype=np.float64)
    base = np.stack([np.interp(lat, keys, cols[:, c]) for c in range(3)], axis=-1)
    # Fine banding on top of the zones, weaker toward the poles.
    fine = 1 + 0.035 * np.sin(np.radians(lat) * 41.0 + 0.7) + 0.02 * np.sin(np.radians(lat) * 97.0 + 2.1)
    fine = 1 + (fine - 1) * np.cos(np.radians(lat)) ** 0.5
    img = base[:, None, :] * fine[:, None, None] * np.ones((1, width, 1))
    # Turbulence along the bands: a wrapped noise sheared in longitude only.
    lon = (np.arange(width) + 0.5) / width
    n = np.zeros((height, width))
    for k, amp in ((6, 0.5), (14, 0.3), (33, 0.2)):
        phase = rng.uniform(0, 2 * np.pi, size=height)
        phase = gaussian_filter1d(phase, 1.5, mode="nearest")
        n += amp * np.sin(2 * np.pi * k * lon[None, :] + phase[:, None])
    img *= (1 + 0.025 * n)[:, :, None]
    # The north polar hexagon: a dark six-sided jet at 78 N, longitude 0 at the centre.
    lon_r = (lon - 0.5) * 2 * np.pi
    hexlat = 78.0 + 1.6 * np.cos(6 * lon_r)[None, :] / np.cos(np.pi / 6)
    hexd = np.abs(lat[:, None] - hexlat)
    img *= (1 - 0.22 * np.exp(-(hexd / 1.2) ** 2))[:, :, None]
    return Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


# Ring regions: (inner km, outer km, opacity, colour).
RING_REGIONS = [
    (66900, 74490, 0.015, (0.45, 0.42, 0.40)),    # D ring, barely there
    (74490, 91980, 0.11, (0.58, 0.53, 0.47)),     # C ring
    (91980, 99000, 0.62, (0.84, 0.76, 0.62)),     # inner B ring
    (99000, 117580, 0.93, (0.90, 0.82, 0.68)),    # B ring core
    (117580, 122170, 0.07, (0.52, 0.49, 0.46)),   # Cassini Division
    (122170, 133423, 0.55, (0.84, 0.78, 0.67)),   # A ring
    (133423, 133745, 0.0, (0.84, 0.78, 0.67)),    # Encke gap
    (133745, 136485, 0.50, (0.82, 0.76, 0.66)),   # outer A ring
    (136485, 136527, 0.0, (0.82, 0.76, 0.66)),    # Keeler gap
    (136527, 136775, 0.45, (0.82, 0.76, 0.66)),   # A ring edge
    (136775, 140500, 0.0, (0.80, 0.76, 0.70)),    # Roche division (F ring added below)
]


def build_rings(seed, width=2048, height=4):
    rng = np.random.default_rng(seed + 2)
    km = RING_INNER_KM + (np.arange(width) + 0.5) * (RING_OUTER_KM - RING_INNER_KM) / width
    opacity = np.zeros(width)
    colour = np.zeros((width, 3))
    for inner, outer, a, c in RING_REGIONS:
        m = (km >= inner) & (km < outer)
        opacity[m] = a
        colour[m] = c
    # The Huygens ringlet in the Cassini Division and the narrow F ring.
    opacity += 0.45 * np.exp(-((km - 117820) / 90.0) ** 2)
    opacity += 0.35 * np.exp(-((km - 140180) / 120.0) ** 2)
    colour[km > 136775] = (0.80, 0.76, 0.70)
    # Ringlets: seeded multi-scale structure, strongest in the B and C rings.
    noise = np.zeros(width)
    for sigma, amp in ((1.0, 0.5), (3.0, 0.35), (9.0, 0.25)):
        noise += amp * gaussian_filter1d(rng.standard_normal(width), sigma, mode="nearest")
    noise /= noise.std()
    strength = np.where((km > 74490) & (km < 117580), 0.18, 0.08)
    opacity = np.clip(opacity * (1 + strength * noise), 0, 1)
    # Edges soften by a pixel so the gaps do not alias at a distance.
    opacity = gaussian_filter1d(opacity, 0.6, mode="nearest")
    rgba = np.concatenate([colour, opacity[:, None]], axis=-1)
    rgba = np.repeat(rgba[None, :, :], height, axis=0)
    return Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out-dir", type=Path, default=ROOT / "Assets" / "Textures")
    parser.add_argument("--seed", type=int, default=14)
    args = parser.parse_args()
    for name, image in (("crsky_titan_haze.png", build_haze(args.seed)),
                        ("crsky_saturn.png", build_saturn(args.seed)),
                        ("crsky_saturn_rings.png", build_rings(args.seed))):
        path = args.out_dir / name
        image.save(path, optimize=True)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
