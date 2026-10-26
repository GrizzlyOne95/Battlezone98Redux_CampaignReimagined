"""Bake the Venus sky cloud map (Assets/Textures/crsky_venus_clouds.png).

One tileable 1024x1024 RGB density map read by CR_venussky (Shaders/CR_venussky.hlsl):
  R  the sulphuric-acid deck's bands: long, soft streaks along +u, the direction
     the clouds super-rotate;
  G  convective cells: rounded, lumpy billows that break the bands up;
  B  fine breakup noise that erodes both edges.
As Tools/Build-MarsSkyClouds.py, every field is synthesised in the frequency
domain and warped with wrap-around, so the map tiles exactly. The map holds
densities only; the shader does the colouring.

Usage: python Tools/Build-VenusSkyClouds.py [--out PATH] [--size N] [--seed N]
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates

ROOT = Path(__file__).resolve().parent.parent


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


def build(size, seed):
    rng = np.random.default_rng(seed)
    scale = size / 1024.0

    # Bands: strongly anisotropic noise along u, sheared by a slow warp so the
    # streaks wave and fork (the "Y" chevrons of the real deck, loosely).
    wu = spectral(rng, size, 2.2, 1, 10) * 40 * scale
    wv = spectral(rng, size, 2.2, 1, 10) * 18 * scale
    streaks = warp(spectral(rng, size, 1.8, 2, 90, stretch=(6.0, 1.0)), wu, wv)
    fine = warp(spectral(rng, size, 1.3, 8, 260, stretch=(8.0, 1.0)), wu, wv)
    bands = soft(streaks + 0.35 * fine, -1.4, 1.6)

    # Cells: billow noise (the absolute value of two octaves) gives rounded
    # humps with dark creases between them; a little warp keeps them irregular.
    lumps = np.abs(spectral(rng, size, 1.8, 5, 40)) + 0.5 * np.abs(spectral(rng, size, 1.4, 14, 120))
    lumps = warp(lumps, spectral(rng, size, 2.2, 1, 8) * 16 * scale, spectral(rng, size, 2.2, 1, 8) * 16 * scale)
    cells = soft(lumps, 0.25, 1.7)

    breakup = soft(spectral(rng, size, 1.0, 24, 400), -1.6, 1.6)

    rgb = np.stack([bands, cells, breakup], axis=-1)
    return Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=ROOT / "Assets" / "Textures" / "crsky_venus_clouds.png")
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    build(args.size, args.seed).save(args.out, optimize=True)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
