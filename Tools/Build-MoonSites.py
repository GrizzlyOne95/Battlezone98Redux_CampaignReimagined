#!/usr/bin/env python3
"""Generate Scripts/CRMoonSites<NN>.lua for a Moon mission.

The Moon weather director (Scripts/CRMoonWeather.lua) draws a thin pale mist that
pools on LOW ground: crater floors and basins hold it, ridges shed it. It cannot
read the terrain in bulk at run time, and it must not scan hundreds of thousands
of height samples in Lua at every launch, so this tool reads the mission's .hg2
height field (plus the .trn and .bzn) once and writes the facts the director needs
as plain Lua data:

  * bounds   the playable box: the BZN's objects and AI path points, padded
  * terrain  the terrain's own box and the height scale that was measured
  * relief   min / max / mean height, so a doc or a test can sanity-check the map
  * mist     anchors for ground-mist pools, ranked by how deep the ground is
             below its surroundings and how flat it is

Basin analysis (deterministic, pure Python, no third-party modules):

  1. Read the .hg2 (header <HHHHI, zone bits 8 -> 256x256 samples per zone,
     little-endian uint16 with the height in the low 13 bits, stored zone by
     zone, south (low z) first). One sample is 5 world units (3 zones = 3840 on
     misn02b; 2 zones = 2560 on misn03) and one raw count is 0.1 world units
     (measured: correlating the BZN's object heights against the raw field gives
     r = 0.999 on misn03 at 5 units/sample and a slope of 0.099).
  2. Average the samples into coarse cells (--cell, 20 units).
  3. depth = (mean height within --radius, 180 units) - (the cell's own height).
     Positive depth is a bowl; negative is a ridge or a hill.
  4. flatness = 1 - smoothstep(slope, --slope-start, --slope-end): a pool must lie
     on near-level ground or its flat sheet would float off the hillside.
  5. score = clamp(depth / --depth-full, 0, 1) * flatness.
  6. Greedy pick, best first, keeping a candidate only if it is at least
     --pool-spacing from every anchor already kept and inside the playable box.

The runtime also samples the terrain around the player (a "local mist" layer that
follows them), so this file only has to describe the pools that are further away
than the player can see. The output is byte-reproducible.

Usage:
    python -I Tools/Build-MoonSites.py misn02b
    python -I Tools/Build-MoonSites.py misn03 --depth-full 30   # misn03's craters are deep; 16 saturates
"""

from __future__ import annotations

import argparse
import math
import os
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", ROOT.parent / "Battlezone98_Modding_Toolbox"))

SAMPLE_UNITS = 5.0     # world units per height sample
HEIGHT_PER_COUNT = 0.1  # world units per raw count (measured, see the docstring)
HG2_MASK = 0x1FFF


def read_trn(path: Path) -> dict:
    text = path.read_bytes().decode("latin-1").replace("\r", "")
    size, view = {}, {}
    section = None
    for line in text.split("\n"):
        m = re.match(r"\[([^\]]+)\]", line.strip())
        if m:
            section = m.group(1)
            continue
        kv = re.match(r"(\w+)\s*=\s*(-?\d+(?:\.\d+)?)", line.strip())
        if kv and section == "Size":
            size[kv.group(1)] = float(kv.group(2))
        elif kv and section == "NormalView":
            view[kv.group(1)] = float(kv.group(2))
    return {"size": size, "view": view}


def read_hg2(path: Path):
    raw = path.read_bytes()
    version, zone_bits, zones_x, zones_z, map_version = struct.unpack("<HHHHI", raw[:12])
    zone = 1 << zone_bits
    count = zones_x * zones_z * zone * zone
    if len(raw) - 12 != count * 2:
        raise ValueError(f"{path.name}: payload is {len(raw) - 12} bytes, expected {count * 2}")
    samples = struct.unpack("<%dH" % count, raw[12:])
    rows, cols = zones_z * zone, zones_x * zone
    grid = [[0] * cols for _ in range(rows)]
    cursor = 0
    for zz in range(zones_z):
        for zx in range(zones_x):
            for r in range(zone):
                base = cursor + r * zone
                grid[zz * zone + r][zx * zone:(zx + 1) * zone] = [s & HG2_MASK for s in samples[base:base + zone]]
            cursor += zone * zone
    return grid


def to_text_bzn(raw: bytes, toolbox: Path) -> bytes:
    if b"binarySave [1] =\ntrue" not in raw[:200].replace(b"\r", b""):
        return raw
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.version_convert import convert_bzn  # noqa: E402

    return convert_bzn(raw, "redux").data


def parse_bzn_points(text: str):
    """Every object position and every AI path point in a text BZN."""
    points = []
    for block in text.split("[GameObject]")[1:]:
        pos = re.search(r"pos \[1\] =\n  x \[1\] =\n(\S+)\n  y \[1\] =\n(\S+)\n  z \[1\] =\n(\S+)", block)
        if pos:
            points.append((float(pos.group(1)), float(pos.group(3))))
    for m in re.finditer(r"points \[\d+\] =\n((?:  [xz] \[1\] =\n\S+\n)+)", text):
        cur = {}
        for axis, value in re.findall(r"  ([xz]) \[1\] =\n(\S+)", m.group(1)):
            cur[axis] = float(value)
            if "x" in cur and "z" in cur:
                points.append((cur["x"], cur["z"]))
                cur = {}
    return points


def smoothstep(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def fmt(v: float) -> str:
    return ("%.2f" % v).rstrip("0").rstrip(".")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mission")
    ap.add_argument("--source-dir", default=str(ROOT / "Missions"))
    ap.add_argument("--toolbox", type=Path, default=DEFAULT_TOOLBOX)
    ap.add_argument("--cell", type=float, default=20.0, help="coarse analysis cell, world units")
    ap.add_argument("--radius", type=float, default=180.0, help="the 'surroundings' for the depth measure")
    ap.add_argument("--depth-full", type=float, default=16.0, help="metres below the surroundings that score 1")
    ap.add_argument("--slope-start", type=float, default=4.0, help="degrees at which flatness starts to fall")
    ap.add_argument("--slope-end", type=float, default=14.0, help="degrees at which flatness reaches 0")
    ap.add_argument("--pool-spacing", type=float, default=64.0)
    ap.add_argument("--max-pools", type=int, default=120)
    ap.add_argument("--min-score", type=float, default=0.22)
    ap.add_argument("--inset", type=float, default=30.0, help="keep anchors this far inside the playable box")
    ap.add_argument("--pad", type=float, default=420.0, help="pad the objects' bounding box by this much")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    name = args.mission
    folder = Path(args.source_dir)
    trn = read_trn(folder / f"{name}.trn")
    grid = read_hg2(folder / f"{name}.hg2")
    bzn_text = to_text_bzn((folder / f"{name}.bzn").read_bytes(), args.toolbox).decode("latin-1").replace("\r", "")

    size = trn["size"]
    min_x, min_z = size.get("MinX", 0.0), size.get("MinZ", 0.0)
    rows, cols = len(grid), len(grid[0])
    width, depth_world = cols * SAMPLE_UNITS, rows * SAMPLE_UNITS

    # Playable box: the mission's own objects and AI paths, padded, inside the terrain.
    points = parse_bzn_points(bzn_text)
    if points:
        pxs, pzs = [p[0] for p in points], [p[1] for p in points]
        bounds = (
            max(min_x + 60.0, min(pxs) - args.pad), min(min_x + width - 60.0, max(pxs) + args.pad),
            max(min_z + 60.0, min(pzs) - args.pad), min(min_z + depth_world - 60.0, max(pzs) + args.pad),
        )
    else:
        bounds = (min_x + 60.0, min_x + width - 60.0, min_z + 60.0, min_z + depth_world - 60.0)

    # Coarse height grid, world units.
    step = max(1, int(round(args.cell / SAMPLE_UNITS)))
    cell = step * SAMPLE_UNITS
    ncols, nrows = cols // step, rows // step
    coarse = [[0.0] * ncols for _ in range(nrows)]
    for r in range(nrows):
        for c in range(ncols):
            total = 0
            for dr in range(step):
                row = grid[(r * step) + dr]
                total += sum(row[c * step:(c + 1) * step])
            coarse[r][c] = (total / (step * step)) * HEIGHT_PER_COUNT

    # Box mean of radius R via an integral image (edge cells average what exists).
    integral = [[0.0] * (ncols + 1) for _ in range(nrows + 1)]
    for r in range(nrows):
        run = 0.0
        for c in range(ncols):
            run += coarse[r][c]
            integral[r + 1][c + 1] = integral[r][c + 1] + run

    reach = max(1, int(round(args.radius / cell)))

    def box_mean(r: int, c: int) -> float:
        r0, r1 = max(0, r - reach), min(nrows, r + reach + 1)
        c0, c1 = max(0, c - reach), min(ncols, c + reach + 1)
        area = (r1 - r0) * (c1 - c0)
        total = integral[r1][c1] - integral[r0][c1] - integral[r1][c0] + integral[r0][c0]
        return total / area

    def slope_degrees(r: int, c: int) -> float:
        left, right = coarse[r][max(0, c - 1)], coarse[r][min(ncols - 1, c + 1)]
        down, up = coarse[max(0, r - 1)][c], coarse[min(nrows - 1, r + 1)][c]
        gx = (right - left) / (2.0 * cell)
        gz = (up - down) / (2.0 * cell)
        return math.degrees(math.atan(math.hypot(gx, gz)))

    candidates = []
    for r in range(nrows):
        for c in range(ncols):
            x = min_x + (c + 0.5) * cell
            z = min_z + (r + 0.5) * cell
            if not (bounds[0] + args.inset <= x <= bounds[1] - args.inset
                    and bounds[2] + args.inset <= z <= bounds[3] - args.inset):
                continue
            depth = box_mean(r, c) - coarse[r][c]
            if depth <= 0.0:
                continue
            flat = 1.0 - smoothstep((slope_degrees(r, c) - args.slope_start) / (args.slope_end - args.slope_start))
            score = max(0.0, min(1.0, depth / args.depth_full)) * flat
            if score >= args.min_score:
                candidates.append((score, r, c, x, z, depth, coarse[r][c]))

    # Best first; ties broken by position so the output is stable.
    candidates.sort(key=lambda t: (-round(t[0], 6), t[2], t[1]))
    pools = []
    for score, r, c, x, z, depth, h in candidates:
        if len(pools) >= args.max_pools:
            break
        if all(math.hypot(x - p["x"], z - p["z"]) >= args.pool_spacing for p in pools):
            pools.append({"x": x, "z": z, "weight": score, "depth": depth})

    flat_all = [v for row in coarse for v in row]
    mean_h = sum(flat_all) / len(flat_all)
    suffix = re.sub(r"^misn", "", name)
    module = f"CRMoonSites{suffix}"
    out = Path(args.out) if args.out else ROOT / "Scripts" / f"{module}.lua"

    lines = [
        f"-- {module}.lua",
        f"-- GENERATED by Tools/Build-MoonSites.py {name}. Do not edit by hand.",
        f"-- Source: {name}.hg2 (heights), {name}.trn (terrain box), {name}.bzn (playable box)",
        "-- Consumed by CRMoonWeather (ground-mist anchors in low ground, playable bounds).",
        f"-- Parameters: --cell {fmt(cell)} --radius {fmt(args.radius)} --depth-full {fmt(args.depth_full)} "
        f"--slope-start {fmt(args.slope_start)} --slope-end {fmt(args.slope_end)} --pool-spacing {fmt(args.pool_spacing)} "
        f"--max-pools {args.max_pools} --min-score {fmt(args.min_score)}",
        "",
        "return {",
        f'    mission = "{name}",',
        f"    bounds  = {{ minX = {fmt(bounds[0])}, maxX = {fmt(bounds[1])}, minZ = {fmt(bounds[2])}, maxZ = {fmt(bounds[3])} }},",
        f"    terrain = {{ minX = {fmt(min_x)}, minZ = {fmt(min_z)}, width = {fmt(width)}, depth = {fmt(depth_world)}, "
        f"sample = {fmt(SAMPLE_UNITS)}, heightPerCount = {fmt(HEIGHT_PER_COUNT)} }},",
        f"    relief  = {{ min = {fmt(min(flat_all))}, max = {fmt(max(flat_all))}, mean = {fmt(mean_h)} }},",
        "    mist = {",
        f"        cell = {fmt(cell)}, radius = {fmt(args.radius)}, depthFull = {fmt(args.depth_full)},",
        f"        candidates = {len(candidates)},",
        "        -- ground-mist anchors, deepest and flattest ground first, kept apart and inside the playable box",
        "        -- weight 0..1 is the score; depth is metres below the surroundings",
        "        pools = {",
    ]
    for p in pools:
        lines.append(f"            {{ x = {fmt(p['x'])}, z = {fmt(p['z'])}, weight = {fmt(p['weight'])}, depth = {fmt(p['depth'])} }},")
    lines.append("        },")
    lines.append("    },")
    lines.append("}")
    out.write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))
    print(f"wrote {out} ({len(candidates)} candidate cells, {len(pools)} anchors, "
          f"relief {min(flat_all):.1f}..{max(flat_all):.1f}, bounds "
          f"{tuple(round(b) for b in bounds)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
