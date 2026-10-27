"""Bake the Mars sky cloud map (Assets/Textures/crsky_mars_clouds.png).

One tileable 1024x1024 RGB density map read by CR_marssky (Shaders/CR_marssky*.hlsl):
  R  thin water-ice cirrus: long, curled streaks along +u;
  G  dust veils: broad, soft billows;
  B  fine breakup noise that erodes the edges of both.
Every field is synthesised in the frequency domain, so the map tiles exactly; the
domain warp samples periodic fields with wrap-around for the same reason. The shader
does the colouring, so the map holds densities only (0 = clear sky).

Usage: python Tools/Build-MarsSkyClouds.py [--out PATH] [--size N] [--seed N]
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

    # Cirrus: ridged anisotropic noise gives thin fibres along u; a slow warp
    # curls them and a broad mask gathers them into bands.
    wu = spectral(rng, size, 2.2, 1, 12) * 30 * scale
    wv = spectral(rng, size, 2.2, 1, 12) * 14 * scale
    fibres = 1 - np.abs(warp(spectral(rng, size, 1.3, 3, 160, stretch=(7.0, 1.0)), wu, wv))
    fine = 1 - np.abs(warp(spectral(rng, size, 1.1, 12, 320, stretch=(9.0, 1.0)), wu, wv))
    body = warp(spectral(rng, size, 2.0, 1, 30, stretch=(3.0, 1.0)), wu, wv)
    cover = soft(body, -0.6, 1.3)
    cirrus = cover * (0.45 * cover + 0.3 * soft(fibres, 0.0, 0.9) + 0.25 * soft(fibres * fine, 0.3, 0.9))

    # Dust veils: broad and soft, gently warped.
    dust = spectral(rng, size, 2.1, 1, 45)
    dust = warp(dust, spectral(rng, size, 2.2, 1, 8) * 24 * scale, spectral(rng, size, 2.2, 1, 8) * 24 * scale)
    veil = soft(dust, -0.9, 2.4)

    breakup = soft(spectral(rng, size, 1.0, 24, 400), -1.6, 1.6)

    rgb = np.stack([cirrus, veil, breakup], axis=-1)
    return Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=ROOT / "Assets" / "Textures" / "crsky_mars_clouds.png")
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--seed", type=int, default=4)
    args = parser.parse_args()
    build(args.size, args.seed).save(args.out, optimize=True)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
