"""Bake the Elysium sky map (Assets/Textures/crsky_elysium_clouds.png).

One tileable 1024x1024 RGB density map read by CR_elysiumsky (Shaders/CR_elysiumsky.hlsl):
  R  torn high cloud: long, ragged strands along +u, rank-normalised so a
     threshold of 1 - x covers a share x of the sky (the sky is mostly open);
  G  dust and ash veils: broad, soft, slowly varying sheets;
  B  fine breakup noise that frays the edges of both.
As Tools/Build-VenusSkyClouds.py, every field is synthesised in the frequency
domain and warped with wrap-around, so the map tiles exactly. The map holds
densities only; the shader does the colouring. Nothing is downloaded.

Usage: python Tools/Build-ElysiumSky.py [--out-dir DIR] [--size N] [--seed N]
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


def rank(field):
    """Map a field to its percentile, so a threshold reads as a cover share."""
    order = np.argsort(field, axis=None)
    out = np.empty(field.size)
    out[order] = (np.arange(field.size) + 0.5) / field.size
    return out.reshape(field.shape)


def soft(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def build(size, seed):
    rng = np.random.default_rng(seed)
    scale = size / 1024.0

    # Torn strands: strongly anisotropic noise along u, sheared hard by a
    # warp so the strands split, hook and tear instead of running parallel.
    wu = spectral(rng, size, 2.0, 1, 12) * 70 * scale
    wv = spectral(rng, size, 2.0, 1, 12) * 34 * scale
    strands = spectral(rng, size, 1.7, 2, 110, stretch=(5.0, 1.0))
    # Rolled off by ~120 cycles a tile across the strands (~8 texels): the shader thresholds this channel, and
    # texel-scale speckle turns into stair-stepped cloud edges when the dome
    # magnifies the map overhead. Finer fraying comes from the shader's detail tap.
    ragged = spectral(rng, size, 1.2, 10, 120, stretch=(4.0, 1.0))
    torn = warp(strands + 0.55 * ragged, wu, wv)
    cloud = rank(torn)

    # Veils: broad low-frequency sheets, warped a little so they are not round.
    veil = warp(spectral(rng, size, 2.4, 1, 14), spectral(rng, size, 2.2, 1, 8) * 20 * scale,
                spectral(rng, size, 2.2, 1, 8) * 20 * scale)
    veils = soft(veil, -1.5, 1.8)

    breakup = soft(spectral(rng, size, 1.0, 24, 140), -1.6, 1.6)

    rgb = np.stack([cloud, veils, breakup], axis=-1)
    return Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out-dir", type=Path, default=ROOT / "Assets" / "Textures")
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--seed", type=int, default=20)
    args = parser.parse_args()
    out = args.out_dir / "crsky_elysium_clouds.png"
    build(args.size, args.seed).save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
