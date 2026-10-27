"""Bake the Achilles sky maps read by CR_achillessky (Shaders/CR_achillessky.hlsl).

  crsky_achilles_clouds.png  1024x1024 RGB, tileable:
                             R  cumulus field, rank-normalised so a threshold
                                of 1 - x covers a share x of the sky;
                             G  fine detail that frays the cloud edges;
                             B  rain curtains: streaks stretched along v.
  crsky_uranus.png           512x512 RGB, the face of Uranus that Achilles
                             sees, square on (north up, x across): Achilles
                             keeps one face to Uranus, so nothing else shows.
                             Outside the disc the rim colour carries on, for
                             clean filtering at the limb.
  crsky_uranus_rings.png     4096x4 RGBA, the rings' radial profile from 1.45 to
                             4.10 Uranus equatorial radii (37,060 to 104,790 km):
                             rgb the ring material's colour, a its opacity.

Everything is synthesised; nothing is downloaded. Uranus follows the Voyager
and Keck/JWST views: a pale cyan, nearly bland globe with faint zonal bands, a
bright north polar cap with a darker collar, and a few small bright methane
clouds. The ring radii are the published radii of the 6, 5, 4, alpha, beta,
eta, gamma, delta, lambda and epsilon rings and the dusty zeta, nu and mu
rings. The narrow rings are a few kilometres wide, far under one map texel
(16 km), so each is drawn one to three texels wide with the opacity raised to
read at a distance; the epsilon ring stays the brightest, as it is. As
Tools/Build-TitanSky.py, the cloud fields are made in the frequency domain and
warped with wrap-around, so the map tiles exactly.

Usage: python Tools/Build-AchillesSky.py [--out-dir DIR] [--seed N]
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter1d, map_coordinates

ROOT = Path(__file__).resolve().parent.parent
URANUS_RADIUS_KM = 25559.0
RING_INNER_RU = 1.45
RING_OUTER_RU = 4.10


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


def rank(field):
    """Map a field to its percentile, so a threshold reads as a cover share."""
    order = np.argsort(field, axis=None)
    out = np.empty(field.size)
    out[order] = (np.arange(field.size) + 0.5) / field.size
    return out.reshape(field.shape)


def build_clouds(seed, size=1024):
    rng = np.random.default_rng(seed)
    scale = size / 1024.0
    # Cumulus: rounded heaps from billow noise over a broad base, warped so they
    # bunch into streets along the wind.
    base = spectral(rng, size, 2.2, 1, 10)
    heaps = 1.0 - np.abs(spectral(rng, size, 1.9, 3, 40))
    puffs = 1.0 - np.abs(spectral(rng, size, 1.6, 10, 120))
    field = 0.55 * base + 0.9 * heaps + 0.35 * puffs
    field = warp(field, spectral(rng, size, 2.3, 1, 8) * 26 * scale, spectral(rng, size, 2.3, 1, 8) * 26 * scale)
    cumulus = rank(field)
    detail = spectral(rng, size, 1.2, 24, 260)
    detail = np.clip(0.5 + 0.18 * detail, 0, 1)
    # Curtains: thin vertical streaks, long in v, slowly varying strength in u.
    streak = spectral(rng, size, 1.3, 6, 220, stretch=(1.0, 14.0))
    strength = 0.5 + 0.5 * spectral(rng, size, 2.5, 1, 6, stretch=(1.0, 6.0))
    curtains = np.clip((streak * 0.35 + 0.5) * np.clip(strength, 0, 1.4), 0, 1)
    rgb = np.stack([cumulus, detail, curtains], axis=-1)
    return Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


# Uranus's bands: planetographic latitude (degrees) and sRGB colour,
# interpolated in between. The north is in its long summer: a bright polar
# cap above 62 N inside a darker collar.
URANUS_BANDS = [
    (-90, (0.55, 0.75, 0.81)), (-70, (0.57, 0.77, 0.82)), (-50, (0.60, 0.80, 0.85)),
    (-38, (0.63, 0.82, 0.86)), (-28, (0.59, 0.79, 0.84)), (-15, (0.62, 0.82, 0.86)),
    (0, (0.58, 0.79, 0.83)), (12, (0.61, 0.81, 0.85)), (25, (0.64, 0.83, 0.87)),
    (38, (0.62, 0.82, 0.86)), (50, (0.60, 0.80, 0.85)), (56, (0.56, 0.76, 0.82)),
    (60, (0.62, 0.81, 0.86)), (64, (0.78, 0.91, 0.93)), (75, (0.83, 0.93, 0.95)),
    (90, (0.85, 0.94, 0.95)),
]

# Bright methane clouds: latitude, longitude (degrees), size (degrees), strength.
URANUS_SPOTS = [(31, -40, 3.0, 0.22), (34, 25, 2.2, 0.16), (-24, 70, 2.6, 0.12), (42, 120, 1.8, 0.14)]


def build_uranus(seed, size=512):
    rng = np.random.default_rng(seed + 1)
    z, x = np.mgrid[0:size, 0:size].astype(np.float64)
    x = (x + 0.5) / size * 2 - 1
    z = 1 - (z + 0.5) / size * 2
    rim = np.maximum(np.hypot(x, z) / 0.999, 1)
    x, z = x / rim, z / rim
    y = np.sqrt(np.clip(1 - x * x - z * z, 0, 1))
    la = np.degrees(np.arcsin(z))
    lo = np.degrees(np.arctan2(x, y))
    keys = np.array([b[0] for b in URANUS_BANDS], dtype=np.float64)
    cols = np.array([b[1] for b in URANUS_BANDS], dtype=np.float64)
    img = np.stack([np.interp(la, keys, cols[:, c]) for c in range(3)], axis=-1)
    # Faint fine banding and slow longitudinal mottling.
    img *= (1 + 0.012 * np.sin(np.radians(la) * 37.0 + 0.4))[:, :, None]
    rows = 256
    phases = [gaussian_filter1d(rng.uniform(0, 2 * np.pi, size=rows), 2.0, mode="nearest") for _ in range(3)]
    row = np.clip(((90 - la) / 180 * rows).astype(int), 0, rows - 1)
    n = np.zeros_like(la)
    for (k, amp), phase in zip(((3, 0.5), (8, 0.3), (19, 0.2)), phases):
        n += amp * np.sin(np.radians(lo) * k + phase[row])
    img *= (1 + 0.012 * n)[:, :, None]
    # Bright spots, stretched along longitude by the zonal winds.
    for slat, slon, size_deg, strength in URANUS_SPOTS:
        dlon = (lo - slon + 180) % 360 - 180
        blob = np.exp(-((la - slat) / size_deg) ** 2 - (dlon * np.cos(np.radians(slat)) / (size_deg * 2.5)) ** 2)
        img += (np.array([0.95, 0.98, 0.98]) - img) * (strength * blob)[:, :, None]
    return Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


# Narrow rings: (radius km, drawn width km, opacity as drawn, sRGB colour).
NARROW_RINGS = [
    (41837, 30, 0.30, (0.42, 0.42, 0.42)),    # 6
    (42234, 30, 0.30, (0.42, 0.42, 0.42)),    # 5
    (42571, 30, 0.32, (0.42, 0.42, 0.42)),    # 4
    (44718, 40, 0.45, (0.44, 0.44, 0.44)),    # alpha
    (45661, 40, 0.45, (0.44, 0.44, 0.44)),    # beta
    (47176, 30, 0.30, (0.42, 0.42, 0.42)),    # eta
    (47627, 30, 0.50, (0.44, 0.44, 0.44)),    # gamma
    (48300, 35, 0.45, (0.44, 0.44, 0.44)),    # delta
    (50023, 30, 0.18, (0.46, 0.46, 0.48)),    # lambda, dusty
    (51149, 60, 0.95, (0.52, 0.52, 0.52)),    # epsilon, the brightest
]
# Dusty rings: (inner km, outer km, peak km, peak opacity, sRGB colour).
DUST_RINGS = [
    (37850, 41350, 40500, 0.035, (0.45, 0.45, 0.45)),   # zeta
    (66100, 69900, 67300, 0.045, (0.70, 0.46, 0.36)),   # nu, reddish
    (86000, 103000, 97700, 0.060, (0.42, 0.62, 1.00)),  # mu, blue, at Mab's orbit
]


def build_rings(seed, width=4096, height=4):
    rng = np.random.default_rng(seed + 2)
    km = (RING_INNER_RU + (np.arange(width) + 0.5) * (RING_OUTER_RU - RING_INNER_RU) / width) * URANUS_RADIUS_KM
    texel = (RING_OUTER_RU - RING_INNER_RU) * URANUS_RADIUS_KM / width
    opacity = np.zeros(width)
    colour = np.full((width, 3), 0.42)
    for inner, outer, peak, a, c in DUST_RINGS:
        m = (km >= inner) & (km < outer)
        span = np.where(km < peak, (km - inner) / (peak - inner), (outer - km) / (outer - peak))
        profile = np.clip(span, 0, 1) ** 1.5 * m
        opacity += a * profile
        colour += (np.array(c) - colour) * np.minimum(profile * 3, 1)[:, None]
    for radius, drawn, a, c in NARROW_RINGS:
        sigma = max(drawn / texel, 0.6) * 0.5
        profile = np.exp(-0.5 * ((km - radius) / texel / sigma) ** 2)
        opacity = 1 - (1 - opacity) * (1 - a * profile)
        colour += (np.array(c) - colour) * np.minimum(profile * 2, 1)[:, None]
    # A faint sheet of dust between the narrow rings, as Voyager saw backlit.
    sheet = (km > 41000) & (km < 51400)
    opacity += sheet * 0.012 * (1 + 0.5 * gaussian_filter1d(rng.standard_normal(width), 4.0, mode="nearest"))
    opacity = np.clip(opacity, 0, 1)
    rgba = np.concatenate([colour, opacity[:, None]], axis=-1)
    rgba = np.repeat(rgba[None, :, :], height, axis=0)
    return Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out-dir", type=Path, default=ROOT / "Assets" / "Textures")
    parser.add_argument("--seed", type=int, default=17)
    args = parser.parse_args()
    for name, image in (("crsky_achilles_clouds.png", build_clouds(args.seed)),
                        ("crsky_uranus.png", build_uranus(args.seed)),
                        ("crsky_uranus_rings.png", build_rings(args.seed))):
        path = args.out_dir / name
        image.save(path, optimize=True)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
