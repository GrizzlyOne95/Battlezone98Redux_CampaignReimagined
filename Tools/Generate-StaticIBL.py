#!/usr/bin/env python3
"""Generate the neutral static IBL reference set for Campaign Reimagined.

Outputs:
  cr_ibl_neutral_irradiance.dds   32px BC1 cubemap
  cr_ibl_neutral_prefilter.dds   128px BC1 cubemap with 8 GGX-prefiltered mips
  cr_ibl_brdf_lut.dds             64x64 uncompressed RG split-sum GGX BRDF LUT

The environment itself is procedural and deliberately neutral/LDR. It exists as
an immediately testable fallback and as a reference for replacing the aliases
with planet/theme-specific authored cubemaps later.

Requires NumPy. No game/runtime dependency is introduced.
"""
from __future__ import annotations

import argparse
import math
import struct
from pathlib import Path

import numpy as np

PI = math.pi


def normalize(v: np.ndarray) -> np.ndarray:
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def radical_inverse_vdc(bits: np.ndarray) -> np.ndarray:
    bits = bits.astype(np.uint32)
    bits = ((bits << 16) | (bits >> 16)) & np.uint32(0xFFFFFFFF)
    bits = (((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1)) & np.uint32(0xFFFFFFFF)
    bits = (((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2)) & np.uint32(0xFFFFFFFF)
    bits = (((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4)) & np.uint32(0xFFFFFFFF)
    bits = (((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8)) & np.uint32(0xFFFFFFFF)
    return bits.astype(np.float64) * 2.3283064365386963e-10


def hammersley(count: int) -> np.ndarray:
    i = np.arange(count, dtype=np.uint32)
    return np.stack((i.astype(np.float64) / float(count), radical_inverse_vdc(i)), axis=-1)


def cube_directions(face: int, size: int) -> np.ndarray:
    # D3D cubemap convention. v grows downward in texture memory.
    uv = (np.arange(size, dtype=np.float64) + 0.5) / size * 2.0 - 1.0
    u, v = np.meshgrid(uv, uv)
    if face == 0:       # +X
        d = np.stack((np.ones_like(u), -v, -u), axis=-1)
    elif face == 1:     # -X
        d = np.stack((-np.ones_like(u), -v, u), axis=-1)
    elif face == 2:     # +Y
        d = np.stack((u, np.ones_like(u), v), axis=-1)
    elif face == 3:     # -Y
        d = np.stack((u, -np.ones_like(u), -v), axis=-1)
    elif face == 4:     # +Z
        d = np.stack((u, -v, np.ones_like(u)), axis=-1)
    else:               # -Z
        d = np.stack((-u, -v, -np.ones_like(u)), axis=-1)
    return normalize(d)


def environment(direction: np.ndarray) -> np.ndarray:
    d = normalize(direction)
    y = np.clip(d[..., 1], -1.0, 1.0)
    up = np.clip(y, 0.0, 1.0)
    down = np.clip(-y, 0.0, 1.0)

    sky = np.array([0.31, 0.38, 0.48]) + up[..., None] ** 0.55 * np.array([0.20, 0.24, 0.28])
    ground = np.array([0.105, 0.095, 0.085]) + down[..., None] ** 0.65 * np.array([0.07, 0.055, 0.04])
    base = np.where((y >= 0.0)[..., None], sky, ground)

    horizon = np.exp(-np.square(np.abs(y) / 0.18))[..., None]
    base += horizon * np.array([0.18, 0.16, 0.14])

    # Broad soft celestial/environment lobe: visible in reflections without
    # duplicating the direct sun as a pin-sharp highlight.
    key_dir = normalize(np.array([0.42, 0.58, 0.69], dtype=np.float64))
    key = np.clip(np.sum(d * key_dir, axis=-1), 0.0, 1.0) ** 24.0
    base += key[..., None] * np.array([0.40, 0.36, 0.30])

    # Low-frequency azimuth structure makes camera-stable reflection motion easy
    # to validate while staying neutral enough for multiple planets.
    az = 0.5 + 0.5 * (0.65 * d[..., 0] + 0.35 * d[..., 2])
    base *= (0.92 + 0.12 * az)[..., None]
    return np.clip(base, 0.0, 1.0)


def tangent_basis(n: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    up = np.where((np.abs(n[..., 2]) < 0.999)[..., None],
                  np.array([0.0, 0.0, 1.0]),
                  np.array([1.0, 0.0, 0.0]))
    t = normalize(np.cross(up, n))
    b = np.cross(n, t)
    return t, b


def local_to_world(local: np.ndarray, n: np.ndarray) -> np.ndarray:
    t, b = tangent_basis(n)
    return normalize(t[:, None, :] * local[None, :, 0:1]
                     + b[:, None, :] * local[None, :, 1:2]
                     + n[:, None, :] * local[None, :, 2:3])


def cosine_samples(count: int) -> np.ndarray:
    xi = hammersley(count)
    phi = 2.0 * PI * xi[:, 0]
    r = np.sqrt(xi[:, 1])
    return np.stack((r * np.cos(phi),
                     r * np.sin(phi),
                     np.sqrt(np.maximum(1.0 - xi[:, 1], 0.0))), axis=-1)


def ggx_half_vectors(count: int, roughness: float) -> np.ndarray:
    xi = hammersley(count)
    a = max(roughness * roughness, 1e-4)
    a2 = a * a
    phi = 2.0 * PI * xi[:, 0]
    cos_theta = np.sqrt((1.0 - xi[:, 1]) /
                        np.maximum(1.0 + (a2 - 1.0) * xi[:, 1], 1e-8))
    sin_theta = np.sqrt(np.maximum(1.0 - cos_theta * cos_theta, 0.0))
    return np.stack((np.cos(phi) * sin_theta,
                     np.sin(phi) * sin_theta,
                     cos_theta), axis=-1)


def generate_irradiance(size: int, samples: int) -> list[np.ndarray]:
    local = cosine_samples(samples)
    faces = []
    for face in range(6):
        n = cube_directions(face, size).reshape(-1, 3)
        l = local_to_world(local, n)
        # Cosine-weighted estimator of integral/pi is simply the sample average.
        c = environment(l).mean(axis=1)
        faces.append(c.reshape(size, size, 3))
    return faces


def generate_prefilter(base_size: int, samples: int) -> list[list[np.ndarray]]:
    mip_count = int(math.log2(base_size)) + 1
    all_faces: list[list[np.ndarray]] = [[] for _ in range(6)]
    for mip in range(mip_count):
        size = max(1, base_size >> mip)
        roughness = mip / max(mip_count - 1, 1)
        for face in range(6):
            r = cube_directions(face, size).reshape(-1, 3)
            if roughness <= 1e-6:
                c = environment(r)
            else:
                h_local = ggx_half_vectors(samples, roughness)
                h = local_to_world(h_local, r)
                # Prefilter convention uses V=R=N for the lookup integration.
                vdoth = np.sum(r[:, None, :] * h, axis=-1, keepdims=True)
                l = normalize(2.0 * vdoth * h - r[:, None, :])
                ndotl = np.clip(np.sum(r[:, None, :] * l, axis=-1), 0.0, 1.0)
                colors = environment(l)
                weight = ndotl[..., None]
                c = np.sum(colors * weight, axis=1) / np.maximum(np.sum(weight, axis=1), 1e-8)
            all_faces[face].append(c.reshape(size, size, 3))
    return all_faces


def geometry_schlick_ggx(ndotx: np.ndarray, roughness: float) -> np.ndarray:
    r = roughness + 1.0
    k = r * r * 0.125
    return ndotx / np.maximum(ndotx * (1.0 - k) + k, 1e-8)


def integrate_brdf(size: int, samples: int) -> np.ndarray:
    out = np.zeros((size, size, 2), dtype=np.float64)
    for y in range(size):
        roughness = (y + 0.5) / size
        h_local = ggx_half_vectors(samples, roughness)
        for x in range(size):
            ndotv = max((x + 0.5) / size, 1e-4)
            v = np.array([math.sqrt(max(1.0 - ndotv * ndotv, 0.0)), 0.0, ndotv])
            vdoth = np.clip(h_local @ v, 0.0, 1.0)
            l = 2.0 * vdoth[:, None] * h_local - v[None, :]
            ndotl = np.clip(l[:, 2], 0.0, 1.0)
            ndoth = np.clip(h_local[:, 2], 0.0, 1.0)
            valid = ndotl > 0.0
            if not np.any(valid):
                continue
            g = (geometry_schlick_ggx(np.full(samples, ndotv), roughness)
                 * geometry_schlick_ggx(ndotl, roughness))
            g_vis = (g * vdoth) / np.maximum(ndoth * ndotv, 1e-8)
            fc = np.power(1.0 - vdoth, 5.0)
            out[y, x, 0] = np.where(valid, (1.0 - fc) * g_vis, 0.0).mean()
            out[y, x, 1] = np.where(valid, fc * g_vis, 0.0).mean()
    return np.clip(out, 0.0, 1.0)


def rgb565(c: np.ndarray) -> int:
    r, g, b = np.clip(np.round(c * 255.0), 0, 255).astype(np.int32)
    return int(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))


def unpack565(v: int) -> np.ndarray:
    return np.array([((v >> 11) & 31) / 31.0,
                     ((v >> 5) & 63) / 63.0,
                     (v & 31) / 31.0])


def bc1_compress(image: np.ndarray) -> bytes:
    h, w, _ = image.shape
    ph = max(4, ((h + 3) // 4) * 4)
    pw = max(4, ((w + 3) // 4) * 4)
    padded = np.empty((ph, pw, 3), dtype=np.float64)
    for yy in range(ph):
        for xx in range(pw):
            padded[yy, xx] = image[min(yy, h - 1), min(xx, w - 1)]

    out = bytearray()
    lum_w = np.array([0.299, 0.587, 0.114])
    for by in range(0, ph, 4):
        for bx in range(0, pw, 4):
            block = padded[by:by + 4, bx:bx + 4].reshape(16, 3)
            lum = block @ lum_w
            v0 = rgb565(block[int(np.argmax(lum))])
            v1 = rgb565(block[int(np.argmin(lum))])
            if v0 == v1:
                if v0 < 0xFFFF:
                    v0 += 1
                elif v1 > 0:
                    v1 -= 1
            if v0 < v1:
                v0, v1 = v1, v0
            p0, p1 = unpack565(v0), unpack565(v1)
            palette = np.stack((p0, p1,
                                (2.0 * p0 + p1) / 3.0,
                                (p0 + 2.0 * p1) / 3.0))
            dist = np.sum((block[:, None, :] - palette[None, :, :]) ** 2, axis=-1)
            idx = np.argmin(dist, axis=1)
            bits = 0
            for i, code in enumerate(idx):
                bits |= int(code) << (2 * i)
            out += struct.pack('<HHI', v0, v1, bits)
    return bytes(out)


def dds_header_bc1(width: int, height: int, mip_count: int) -> bytes:
    DDSD_CAPS = 0x1
    DDSD_HEIGHT = 0x2
    DDSD_WIDTH = 0x4
    DDSD_PIXELFORMAT = 0x1000
    DDSD_MIPMAPCOUNT = 0x20000
    DDSD_LINEARSIZE = 0x80000
    DDPF_FOURCC = 0x4
    DDSCAPS_COMPLEX = 0x8
    DDSCAPS_TEXTURE = 0x1000
    DDSCAPS_MIPMAP = 0x400000
    DDSCAPS2_CUBEMAP_ALLFACES = 0x0000FE00

    top_blocks = max(1, (width + 3) // 4) * max(1, (height + 3) // 4)
    linear_size = top_blocks * 8
    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_LINEARSIZE | DDSD_MIPMAPCOUNT
    caps = DDSCAPS_TEXTURE | DDSCAPS_COMPLEX | DDSCAPS_MIPMAP
    fourcc = struct.unpack('<I', b'DXT1')[0]
    reserved = [0] * 11
    pf = (32, DDPF_FOURCC, fourcc, 0, 0, 0, 0, 0)
    header = struct.pack('<I', 124)
    header += struct.pack('<IIIIII', flags, height, width, linear_size, 0, mip_count)
    header += struct.pack('<11I', *reserved)
    header += struct.pack('<8I', *pf)
    header += struct.pack('<IIIII', caps, DDSCAPS2_CUBEMAP_ALLFACES, 0, 0, 0)
    assert len(header) == 124
    return b'DDS ' + header


def write_cube_dds(path: Path, faces_mips: list[list[np.ndarray]]) -> None:
    base_size = faces_mips[0][0].shape[0]
    mip_count = len(faces_mips[0])
    with path.open('wb') as f:
        f.write(dds_header_bc1(base_size, base_size, mip_count))
        # DDS cubemap payload order: +X, -X, +Y, -Y, +Z, -Z; all mips per face.
        for face in range(6):
            for mip in range(mip_count):
                f.write(bc1_compress(np.clip(faces_mips[face][mip], 0.0, 1.0)))


def dds_header_rgba8(width: int, height: int) -> bytes:
    DDSD_CAPS = 0x1
    DDSD_HEIGHT = 0x2
    DDSD_WIDTH = 0x4
    DDSD_PITCH = 0x8
    DDSD_PIXELFORMAT = 0x1000
    DDPF_ALPHAPIXELS = 0x1
    DDPF_RGB = 0x40
    DDSCAPS_TEXTURE = 0x1000

    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PITCH | DDSD_PIXELFORMAT
    pitch = width * 4
    reserved = [0] * 11
    pf = (32, DDPF_RGB | DDPF_ALPHAPIXELS, 0, 32,
          0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    header = struct.pack('<I', 124)
    header += struct.pack('<IIIIII', flags, height, width, pitch, 0, 0)
    header += struct.pack('<11I', *reserved)
    header += struct.pack('<8I', *pf)
    header += struct.pack('<IIIII', DDSCAPS_TEXTURE, 0, 0, 0, 0)
    assert len(header) == 124
    return b'DDS ' + header


def write_rg_dds(path: Path, rg: np.ndarray) -> None:
    h, w, _ = rg.shape
    quant = np.clip(np.round(rg * 255.0), 0, 255).astype(np.uint8)
    bgra = np.zeros((h, w, 4), dtype=np.uint8)
    bgra[..., 1] = quant[..., 1]
    bgra[..., 2] = quant[..., 0]
    bgra[..., 3] = 255
    path.write_bytes(dds_header_rgba8(w, h) + bgra.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path('Textures'))
    parser.add_argument('--prefilter-size', type=int, default=128)
    parser.add_argument('--irradiance-size', type=int, default=32)
    parser.add_argument('--brdf-size', type=int, default=64)
    parser.add_argument('--samples', type=int, default=64)
    parser.add_argument('--brdf-samples', type=int, default=256)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    print('Generating irradiance cubemap...')
    irradiance = generate_irradiance(args.irradiance_size, args.samples)
    write_cube_dds(args.output / 'cr_ibl_neutral_irradiance.dds', [[face] for face in irradiance])

    print('Generating GGX-prefiltered cubemap...')
    write_cube_dds(args.output / 'cr_ibl_neutral_prefilter.dds',
                   generate_prefilter(args.prefilter_size, args.samples))

    print('Generating split-sum BRDF LUT...')
    write_rg_dds(args.output / 'cr_ibl_brdf_lut.dds',
                 integrate_brdf(args.brdf_size, args.brdf_samples))

    for p in sorted(args.output.iterdir()):
        print(f'{p}: {p.stat().st_size} bytes')


if __name__ == '__main__':
    main()
