"""Author an editable Moon crater height map into a local HD preview bundle.

Diffuse/normal/specular/emissive artwork is untouched. The small, separate
geometry lookup uses the existing CSV UVs, including native rotations.
"""
import argparse
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def fade(t):
    t = np.clip(t, 0, 1)
    return t**3 * (t * (6*t - 15) + 10)


def crater_tile(size, settings):
    """Signed unit height: compact bowls/rims, exactly flat intervening ground."""
    uv = (np.arange(size, dtype=np.float64) + .5) / size
    u, v = np.meshgrid(uv, uv)
    result = np.zeros((size, size), np.float64)
    for crater in settings["craters"]:
        cx, cy = crater["center"]
        radius, depth = crater["radiusMeters"], crater["depth"]
        if not all(math.isfinite(x) for x in (cx, cy, radius, depth)) or not (0 < radius <= 8 and 0 < depth <= 1):
            raise ValueError("invalid crater dimensions")
        dx, dy = (u-cx)*settings["tileMeters"], (v-cy)*settings["tileMeters"]
        angle = np.arctan2(dy, dx)
        # Small angular variation wears the rim without adding terrain noise.
        r = np.hypot(dx, dy) / (radius * (1 + .045*np.cos(3*angle) + .025*np.sin(7*angle)))
        bowl = -depth * np.maximum(0, 1-r*r)**2
        rim_t = (r-1.01) / settings["rimWidth"]
        rim = depth * settings["rimHeight"] * np.maximum(0, 1-rim_t*rim_t)**2
        result += bowl + rim
    return np.clip(result, -1, 1).astype(np.float32)


def build(settings, layout, edited=None):
    size = settings["size"]
    if type(size) is not int or size < 256 or size > 4096 or size & (size-1):
        raise ValueError("height size must be power-of-two 256..4096")
    if not (1 <= settings["tileMeters"] <= 100 and .25 <= settings["edgeMeters"] <= 5
            and 0 < settings["rimHeight"] <= .5 and .05 <= settings["rimWidth"] <= .5):
        raise ValueError("invalid crater profile")
    result = np.zeros((size, size), np.float32)
    for row in csv.reader(layout.read_text().splitlines()):
        alias = row[0].lower()
        if not alias:
            continue
        gain = settings["tileGains"].get(alias, 0.0)
        if not math.isfinite(gain) or not 0 <= gain <= 1:
            raise ValueError("tile gain outside 0..1")
        if not gain:
            continue  # paving and its transition tiles stay exactly flat
        x, y, w, h = [round(float(value)*size) for value in row[1:5]]
        if w != h or min(x, y) < 0 or x+w > size or y+h > size:
            raise ValueError("invalid square layout rectangle")
        tile = edited[y:y+h, x:x+w] if edited is not None else crater_tile(w, settings)
        if edited is None and alias == "mn00sc0.map":
            tile = np.rot90(tile)
        # Redux quantizes atlas endpoints. Keep a hard zero band before the
        # quintic blend, covering that inset and the DS bilinear footprint.
        guard = math.ceil(size/160)+2
        edge = settings["edgeMeters"] / settings["tileMeters"] * w
        dist = np.minimum(np.arange(w), np.arange(w)[::-1])
        envelope = fade((dist-guard)/edge)
        result[y:y+h, x:x+w] = tile * envelope[:, None] * envelope[None, :] * (gain if edited is None else 1.0)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True, help="Existing local Moon HD bundle")
    parser.add_argument("--openshim", type=Path, required=True, help="OpenShim checkout with the R32 height writer")
    parser.add_argument("--recipe", type=Path, default=ROOT/"Tools/TerrainHD/Moon/craters.json")
    parser.add_argument("--height-image", type=Path, help="Use an edited grayscale 16-bit height PNG instead of regenerating crater art")
    args = parser.parse_args()
    settings = json.loads(args.recipe.read_text())
    if settings.get("schema") != "cr-moon-crater-art-v1":
        raise ValueError("unknown crater art schema")
    manifest_path = args.bundle/"terrain_hd_tiles.json"
    manifest = json.loads(manifest_path.read_text())
    binding = manifest["materials"]["MN_DETAIL_ATLAS"]
    if binding["diffuseResource"] != "moon_atlas_d.dds":
        raise ValueError("Moon diffuse identity mismatch")
    edited = None
    if args.height_image:
        with Image.open(args.height_image) as image:
            if image.size != (settings["size"], settings["size"]) or image.mode not in ("I;16", "I;16L", "I"):
                raise ValueError("edited height must be a matching grayscale 16-bit PNG")
            samples = np.array(image, dtype=np.float32)
            if samples.min() < 0 or samples.max() > 65535:
                raise ValueError("edited height outside 16-bit range")
            edited = samples/32767.5-1
            edited[np.abs(edited) < 2/65535] = 0
    heights = build(settings, args.bundle/"layout.csv", edited)
    spec = importlib.util.spec_from_file_location("surface", args.openshim/"scripts/Build-TerrainSurfacePack.py")
    writer = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = writer
    spec.loader.exec_module(writer)
    resource = "resources/crhd_moon_craters_h.dds"
    target = args.bundle/resource
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(writer.height_dds_bytes(settings["size"], heights.ravel().tolist()))
    png = args.bundle/"moon_craters_height.png"
    Image.fromarray(np.rint((heights+1)*32767.5).astype(np.uint16)).save(png)
    # This augments the local candidate only, leaving canonical shipping art
    # untouched until the new crater morphology is visually accepted.
    binding["heightTexture"] = resource
    binding["heightEncoding"] = "signed-unit-r32"
    manifest_path.write_text(json.dumps(manifest, indent=2)+"\n")
    report = {"schema": settings["schema"], "minimum": float(heights.min()), "maximum": float(heights.max()),
              "flatFraction": float((heights == 0).mean()), "ddsSha256": hashlib.sha256(target.read_bytes()).hexdigest(),
              "depthScale": binding.get("microReliefScale", 1), "geometryHeight": True,
              "normalMapsChanged": False, "recipe": settings}
    (args.bundle/"crater_height_report.json").write_text(json.dumps(report, indent=2)+"\n")
    print(f"Crater height: {target}\nEditable height: {png}\nSigned unit range: {heights.min():.4f}..{heights.max():.4f}")


if __name__ == "__main__":
    main()
