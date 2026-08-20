#!/usr/bin/env python3
"""Build a deterministic CR Enhanced Material V2 RGBA8 DDS.

The output is numerical material DATA, not display colour:

    RGB = linear specular reflectance / F0
    A   = perceptual roughness (0 = sharp, 1 = broad)

No channel is gamma converted, normalized, resized, or inferred. Inputs may be
8-bit images or explicit normalized constants. The output is uncompressed
A8R8G8B8 DDS so the values survive packing exactly; a later DDS compression
step is optional and must be chosen deliberately by the asset author.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path
from typing import Iterable

from PIL import Image


def normalized_triplet(value: str) -> tuple[float, float, float]:
    try:
        fields = tuple(float(item.strip()) for item in value.split(","))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("F0 must be three comma-separated numbers") from exc
    if len(fields) != 3 or any(item < 0.0 or item > 1.0 for item in fields):
        raise argparse.ArgumentTypeError("F0 must contain exactly three values in [0, 1]")
    return fields


def normalized_scalar(value: str) -> float:
    try:
        result = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("roughness must be a number in [0, 1]") from exc
    if result < 0.0 or result > 1.0:
        raise argparse.ArgumentTypeError("roughness must be in [0, 1]")
    return result


def image_size(value: str) -> tuple[int, int]:
    try:
        width_text, height_text = value.lower().split("x", 1)
        width, height = int(width_text), int(height_text)
    except (ValueError, AttributeError) as exc:
        raise argparse.ArgumentTypeError("size must be WIDTHxHEIGHT") from exc
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("size dimensions must be positive")
    return width, height


def _reject_profile(image: Image.Image, path: Path) -> None:
    ambiguous = sorted(key for key in ("icc_profile", "srgb", "gamma") if key in image.info)
    if ambiguous:
        joined = ", ".join(ambiguous)
        raise ValueError(
            f"{path} contains colour-management metadata ({joined}); Material V2 is linear DATA. "
            "Export an untagged data texture explicitly."
        )


def load_specular(path: Path) -> Image.Image:
    with Image.open(path) as source:
        source.load()
        _reject_profile(source, path)
        if source.mode not in ("RGB", "RGBA"):
            raise ValueError(f"{path} must be an 8-bit RGB or RGBA image, not mode {source.mode!r}")
        channels = source.split()
        return Image.merge("RGB", channels[:3])


def load_roughness(path: Path) -> Image.Image:
    with Image.open(path) as source:
        source.load()
        _reject_profile(source, path)
        if source.mode != "L":
            raise ValueError(f"{path} must be an 8-bit single-channel L image, not mode {source.mode!r}")
        return source.copy()


def quantize(value: float) -> int:
    # Half-up is explicit and stable (Python's built-in round uses bankers'
    # rounding). Image channels already arrive as exact 8-bit integers.
    return int(value * 255.0 + 0.5)


def dds_header_rgba8(width: int, height: int) -> bytes:
    ddsd_caps = 0x1
    ddsd_height = 0x2
    ddsd_width = 0x4
    ddsd_pitch = 0x8
    ddsd_pixel_format = 0x1000
    ddpf_alpha_pixels = 0x1
    ddpf_rgb = 0x40
    dds_caps_texture = 0x1000

    flags = ddsd_caps | ddsd_height | ddsd_width | ddsd_pitch | ddsd_pixel_format
    pixel_format = (
        32,
        ddpf_rgb | ddpf_alpha_pixels,
        0,
        32,
        0x00FF0000,
        0x0000FF00,
        0x000000FF,
        0xFF000000,
    )
    header = struct.pack("<I", 124)
    header += struct.pack("<IIIIII", flags, height, width, width * 4, 0, 0)
    header += struct.pack("<11I", *([0] * 11))
    header += struct.pack("<8I", *pixel_format)
    header += struct.pack("<IIIII", dds_caps_texture, 0, 0, 0, 0)
    if len(header) != 124:
        raise AssertionError("internal DDS header size error")
    return b"DDS " + header


def _constant_rgb(size: tuple[int, int], value: Iterable[float]) -> Image.Image:
    rgb = tuple(quantize(channel) for channel in value)
    return Image.new("RGB", size, rgb)


def _constant_l(size: tuple[int, int], value: float) -> Image.Image:
    return Image.new("L", size, quantize(value))


def build_material_image(
    specular: Image.Image | None,
    roughness: Image.Image | None,
    f0: tuple[float, float, float] | None,
    roughness_value: float | None,
    size: tuple[int, int] | None,
) -> Image.Image:
    sizes = [image.size for image in (specular, roughness) if image is not None]
    if size is not None:
        sizes.append(size)
    if not sizes:
        raise ValueError("--size is required when both inputs are constants")
    if any(candidate != sizes[0] for candidate in sizes[1:]):
        raise ValueError(f"input dimensions do not match: {sizes}")
    resolved_size = sizes[0]

    if specular is None:
        if f0 is None:
            raise ValueError("provide exactly one of --specular or --f0")
        specular = _constant_rgb(resolved_size, f0)
    elif f0 is not None:
        raise ValueError("provide exactly one of --specular or --f0")

    if roughness is None:
        if roughness_value is None:
            raise ValueError("provide exactly one of --roughness or --roughness-value")
        roughness = _constant_l(resolved_size, roughness_value)
    elif roughness_value is not None:
        raise ValueError("provide exactly one of --roughness or --roughness-value")

    if specular.size != roughness.size:
        raise ValueError(f"input dimensions do not match: {specular.size} and {roughness.size}")
    red, green, blue = specular.split()
    return Image.merge("RGBA", (red, green, blue, roughness))


def write_dds(path: Path, image: Image.Image, force: bool = False) -> None:
    if path.suffix.lower() != ".dds":
        raise ValueError("output filename must end in .dds")
    if path.exists() and not force:
        raise FileExistsError(f"refusing to overwrite {path}; pass --force deliberately")
    path.parent.mkdir(parents=True, exist_ok=True)
    red, green, blue, alpha = image.split()
    bgra = Image.merge("RGBA", (blue, green, red, alpha)).tobytes()
    path.write_bytes(dds_header_rgba8(*image.size) + bgra)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    spec_group = parser.add_mutually_exclusive_group(required=True)
    spec_group.add_argument("--specular", type=Path, help="8-bit RGB/RGBA linear F0 image")
    spec_group.add_argument("--f0", type=normalized_triplet, help="constant linear F0 as R,G,B in [0,1]")
    rough_group = parser.add_mutually_exclusive_group(required=True)
    rough_group.add_argument("--roughness", type=Path, help="8-bit L perceptual-roughness image")
    rough_group.add_argument("--roughness-value", type=normalized_scalar, help="constant roughness in [0,1]")
    parser.add_argument("--size", type=image_size, help="WIDTHxHEIGHT; required for two constants")
    parser.add_argument("--output", type=Path, required=True, help="uncompressed RGBA8 .dds output")
    parser.add_argument("--force", action="store_true", help="replace an existing output deliberately")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    specular = load_specular(args.specular) if args.specular else None
    roughness = load_roughness(args.roughness) if args.roughness else None
    material = build_material_image(specular, roughness, args.f0, args.roughness_value, args.size)
    write_dds(args.output, material, args.force)
    print(
        f"Wrote {args.output} ({material.width}x{material.height}, RGBA8 DATA: "
        "RGB=linear F0, A=perceptual roughness)."
    )


if __name__ == "__main__":
    main()
