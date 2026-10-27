"""Bake terrain shape masks (hollows / ridges) for the weather worlds.

  python Tools/Build-TerrainShape.py [--atlas eu_detail_atlas,ma_detail_atlas] [--dry]

For every Missions/*.trn whose [Atlases] MaterialName is in --atlas, reads the
map's HG2 and computes how far each 10 m texel sits below (hollow) or above
(ridge) its surroundings at two scales (30 m and 90 m Gaussian). The maps of
one atlas are packed side by side into <atlas>_shape.dds (BGRA8, R = hollow,
G = ridge, row 0 = min Z), so the texture is fixed per terrain material and
only the uniform changes per map. Writes:

  Assets/Textures/<atlas>_shape.dds, cr_terrain_shape_none.dds (neutral)
  Scripts/CRTerrainShape.lua   map -> surfaceTerrain uv transform
  Shipping/shipping.lock.json  new entries

The shader maps world XZ to uv as (x*su + ou, z*sv + ov). Run from the CR
root; set BZ_MODDING_TOOLBOX if the toolbox is not a sibling checkout.
"""

import json
import os
import re
import struct
import sys
from pathlib import Path

import numpy as np
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parents[1]
TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", ROOT.parent / "Battlezone98_Modding_Toolbox"))
DEFAULT_ATLASES = ("eu_detail_atlas", "ma_detail_atlas")
SAMPLE_M = 5.0          # HG2 sample spacing
HEIGHT_M = 0.1          # HG2 height unit
TEXEL_M = 10.0          # baked texel
BS = chr(92)


def trn_info(path):
    text = path.read_bytes().decode("latin-1")
    atlas = re.search(r"^\s*MaterialName\s*=\s*(\S+)", text, re.M | re.I)
    size = re.search(r"^\[Size\](.*?)(?=^\[)", text, re.M | re.S | re.I)
    if not atlas or not size:
        return None
    keys = {k.lower(): float(v) for k, v in re.findall(r"^\s*(\w+)\s*=\s*(-?[\d.]+)", size.group(1), re.M)}
    return atlas.group(1).lower(), keys["minx"], keys["minz"], keys["width"], keys["depth"]


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def shape(heights):
    """(rows=z, cols=x) heights in metres at TEXEL_M -> (hollow, ridge) in 0..1."""
    near = heights - gaussian_filter(heights, 30.0 / TEXEL_M, mode="nearest")
    wide = heights - gaussian_filter(heights, 90.0 / TEXEL_M, mode="nearest")
    rel = 0.6 * near / 2.0 + 0.4 * wide / 6.0
    return smoothstep(0.25, 1.2, -rel), smoothstep(0.25, 1.2, rel)


def write_dds(path, rgba):
    h, w = rgba.shape[:2]
    header = struct.pack("<4s7I44x8I5I", b"DDS ", 124, 0x100F, h, w, w * 4, 0, 1,
                         32, 0x41, 0, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000,
                         0x1000, 0, 0, 0, 0)
    bgra = rgba[..., [2, 1, 0, 3]]
    path.write_bytes(header + np.ascontiguousarray(bgra, dtype=np.uint8).tobytes())


def main():
    sys.path.insert(0, str(TOOLBOX))
    from battlezone.terrain.hg2 import read_hg2

    dry = "--dry" in sys.argv
    atlases = DEFAULT_ATLASES
    if "--atlas" in sys.argv:
        atlases = tuple(a.strip().lower() for a in sys.argv[sys.argv.index("--atlas") + 1].split(","))
    os.chdir(ROOT)

    groups = {}
    for trn in sorted(Path("Missions").glob("*.trn")):
        info = trn_info(trn)
        hg2 = trn.with_suffix(".hg2")
        if info and info[0] in atlases and hg2.exists() and trn.stem.lower() != "crsetup":
            groups.setdefault(info[0], []).append((trn.stem.lower(), hg2) + info[1:])

    # Neutral default for the base material's unit: no hollows, no ridges.
    none = Path("Assets/Textures/cr_terrain_shape_none.dds")
    lua, made = [], [none]
    if not dry:
        flat = np.zeros((4, 4, 4), np.uint8)
        flat[..., 3] = 255
        write_dds(none, flat)
    for atlas, maps in sorted(groups.items()):
        tiles = []
        for name, hg2, minx, minz, width, depth in maps:
            header, raw = read_hg2(hg2)
            h = raw.astype(np.float32) * HEIGHT_M
            step = int(TEXEL_M / SAMPLE_M)
            h = h[: h.shape[0] // step * step, : h.shape[1] // step * step]
            h = h.reshape(h.shape[0] // step, step, h.shape[1] // step, step).mean(axis=(1, 3))
            hollow, ridge = shape(h)
            tiles.append((name, minx, minz, width, depth, hollow, ridge))
        tile = max(max(t[5].shape) for t in tiles)
        sheet = np.zeros((tile, tile * len(tiles), 4), np.uint8)
        sheet[..., 3] = 255
        for i, (name, minx, minz, width, depth, hollow, ridge) in enumerate(tiles):
            rows, cols = hollow.shape
            sheet[:rows, i * tile:i * tile + cols, 0] = np.round(hollow * 255)
            sheet[:rows, i * tile:i * tile + cols, 1] = np.round(ridge * 255)
            su = 1.0 / (TEXEL_M * tile * len(tiles))
            sv = 1.0 / (TEXEL_M * tile)
            lua.append((name, atlas.upper(), su, sv, i / len(tiles) - minx * su, -minz * sv))
            print(f"{atlas} {name}: tile {i}, {cols}x{rows}, hollow>0.5 {np.mean(hollow > 0.5):.1%}, "
                  f"ridge>0.5 {np.mean(ridge > 0.5):.1%}")
        out = Path("Assets/Textures") / f"{atlas}_shape.dds"
        made.append(out)
        if not dry:
            write_dds(out, sheet)

    body = ["-- Generated by Tools/Build-TerrainShape.py; do not edit.",
            "-- Map -> terrain atlas material and the surfaceTerrain uv transform",
            "-- (u = x*su + ou, v = z*sv + ov) into <atlas>_shape.dds.",
            "return {"]
    for name, atlas, su, sv, ou, ov in lua:
        body.append(f'    {name} = {{ "{atlas}", {su:.9g}, {sv:.9g}, {ou:.9g}, {ov:.9g} }},')
    body.append("}")
    script = Path("Scripts/CRTerrainShape.lua")
    if not dry:
        script.write_bytes(("\r\n".join(body) + "\r\n").encode("utf-8"))

    lock_path = Path("Shipping/shipping.lock.json")
    lock = json.loads(lock_path.read_bytes().decode("utf-8"))
    entries = lock["files"]
    runtimes = {f["runtime"].lower() for f in entries}
    wanted = [(BS.join(p.parts), p.name) for p in made + [script]]
    added = [(s, r) for s, r in wanted if r.lower() not in runtimes]
    if not dry and added:
        for source, runtime in added:
            prefix = source.lower().rsplit(BS, 1)[0] + BS
            idx = [i for i, f in enumerate(entries) if f["source"].lower().startswith(prefix)]
            e = {"source": source, "runtime": runtime}
            pos = next((i for i in idx if entries[i]["source"].lower() > source.lower()),
                       (idx[-1] + 1) if idx else len(entries))
            entries.insert(pos, e)
        lock["count"] = len(entries)
        lock_path.write_bytes((json.dumps(lock, indent=2, ensure_ascii=False) + "\n")
                              .replace("\n", "\r\n").encode("utf-8"))
    print(f"atlases {len(made)}, maps {len(lua)}, new lock entries {len(added)}")


if __name__ == "__main__":
    main()
