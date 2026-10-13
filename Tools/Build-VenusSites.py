#!/usr/bin/env python3
"""Generate Scripts/CRVenusSites<NN>.lua for a Venus mission.

The Venus weather director cannot ask the engine which terrain material lies
under a point, and it must not re-read a 128 KB .mat in Lua every launch. This
tool reads the mission's .trn / .mat / .bzn once and writes the three facts the
director needs as plain Lua data:

  * bounds   the playable box, from the BZN's `edge_path` (two corner points)
  * sulfur   run-length encoded .mat cells whose base or next material is one of
             the requested TextureType indices (default: Liquid Sulphur)
  * vents    every geyser/volcano object (ODF eggeizr1 by default) with its label

MAT layout (battlezone/terrain/mat.py in the modding toolbox): one little-endian
uint16 per tile, 64x64 tiles per zone, zones row-major, each zone row-major,
south (low z) first. Bits 15-12 are the base material and 11-8 the next
material. Verified on misn07 by correlating the zoned HG2 heights against the
BZN object elevations (r = 0.997 with x = col, z = minZ + row).

Usage:
    python Tools/Build-VenusSites.py misn07 [--types 1] [--vent-odf eggeizr1]
"""

from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ZONE = 64


def read_trn(path: Path) -> dict:
    text = path.read_bytes().decode("latin-1").replace("\r", "")
    size = {}
    labels = {}
    section = None
    for line in text.split("\n"):
        m = re.match(r"\[([^\]]+)\](.*)", line.strip())
        if m:
            section = m.group(1)
            tm = re.fullmatch(r"TextureType(\d+)", section)
            if tm:
                labels[int(tm.group(1))] = m.group(2).replace("//", "").strip()
            continue
        if section == "Size":
            kv = re.match(r"(\w+)\s*=\s*(-?\d+(?:\.\d+)?)", line.strip())
            if kv:
                size[kv.group(1)] = float(kv.group(2))
    return {"size": size, "labels": labels}


def unzone(raw: bytes, zones_x: int, zones_z: int) -> list[list[int]]:
    entries = struct.unpack("<%dH" % (len(raw) // 2), raw)
    cols, rows = zones_x * ZONE, zones_z * ZONE
    grid = [[0] * cols for _ in range(rows)]
    p = 0
    for zz in range(zones_z):
        for zx in range(zones_x):
            for r in range(ZONE):
                base = (zz * ZONE + r)
                row = grid[base]
                for c in range(ZONE):
                    row[zx * ZONE + c] = entries[p]
                    p += 1
    return grid


def parse_bzn(path: Path):
    text = path.read_bytes().decode("latin-1").replace("\r", "")
    objects = []
    for block in text.split("[GameObject]")[1:]:
        prj = re.search(r"PrjID \[1\] =\n(\S+)", block)
        pos = re.search(r"pos \[1\] =\n  x \[1\] =\n(\S+)\n  y \[1\] =\n(\S+)\n  z \[1\] =\n(\S+)", block)
        label = re.search(r"label = (.*)", block)
        team = re.search(r"team \[1\] =\n(\S+)", block)
        if prj and pos:
            objects.append({
                "odf": prj.group(1),
                "x": float(pos.group(1)), "y": float(pos.group(2)), "z": float(pos.group(3)),
                "label": label.group(1).strip() if label else "",
                "team": int(team.group(1)) if team else 0,
            })
    paths = {}
    for m in re.finditer(r"\[AiPath\]\n[^\n]*\n(?:size \[1\] =\n\d+\n)?label = ([^\n]*)\npointCount \[1\] =\n(\d+)\npoints \[\d+\] =\n((?:  [xz] \[1\] =\n\S+\n)+)", text):
        vals = re.findall(r"  ([xz]) \[1\] =\n(\S+)", m.group(3))
        pts, cur = [], {}
        for axis, v in vals:
            cur[axis] = float(v)
            if "x" in cur and "z" in cur:
                pts.append((cur["x"], cur["z"]))
                cur = {}
        paths[m.group(1).strip()] = pts
    return objects, paths


def runs_for(grid, types, transition_weight):
    runs = []
    for r, row in enumerate(grid):
        c = 0
        n = len(row)
        while c < n:
            v = row[c]
            base, nxt = (v >> 12) & 15, (v >> 8) & 15
            if base in types:
                w = 1.0
            elif nxt in types:
                w = transition_weight
            else:
                c += 1
                continue
            start = c
            c += 1
            while c < n:
                v2 = row[c]
                b2, n2 = (v2 >> 12) & 15, (v2 >> 8) & 15
                w2 = 1.0 if b2 in types else (transition_weight if n2 in types else 0.0)
                if w2 != w:
                    break
                c += 1
            runs.append((r, start, c - start, w))
    return runs


def fmt(v: float) -> str:
    return ("%.2f" % v).rstrip("0").rstrip(".")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mission")
    ap.add_argument("--types", default="1", help="comma list of TextureType indices that count as sulfur pools")
    ap.add_argument("--transition-weight", type=float, default=0.5)
    ap.add_argument("--vent-odf", default="eggeizr1")
    ap.add_argument("--major-prefix", default="volcano")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    name = args.mission
    trn = read_trn(ROOT / "Missions" / f"{name}.trn")
    size = trn["size"]
    min_x, min_z = size.get("MinX", 0.0), size.get("MinZ", 0.0)
    width, depth = size.get("Width", 5120.0), size.get("Depth", 5120.0)
    mat = (ROOT / "Missions" / f"{name}.mat").read_bytes()
    cells = int((len(mat) // 2) ** 0.5)
    if cells * cells * 2 != len(mat) or cells % ZONE:
        print("unexpected .mat size", len(mat), file=sys.stderr)
        return 1
    zones = cells // ZONE
    grid = unzone(mat, zones, zones)
    cell_size = width / cells
    types = {int(t) for t in args.types.split(",") if t.strip()}
    runs = runs_for(grid, types, args.transition_weight)

    objects, paths = parse_bzn(ROOT / "Missions" / f"{name}.bzn")
    edge = paths.get("edge_path")
    if edge and len(edge) >= 2:
        xs = [p[0] for p in edge]
        zs = [p[1] for p in edge]
        bounds = (min(xs), max(xs), min(zs), max(zs))
    else:
        bounds = (min_x, min_x + width, min_z, min_z + depth)

    vents = [o for o in objects if o["odf"].lower() == args.vent_odf.lower()]
    major_labels = [o for o in objects if o["label"].lower().startswith(args.major_prefix)]

    digits = re.sub(r"\D", "", name) or name
    module = f"CRVenusSites{digits}"
    out = Path(args.out) if args.out else ROOT / "Scripts" / f"{module}.lua"

    lines = [
        f"-- {module}.lua",
        f"-- GENERATED by Tools/Build-VenusSites.py {name}. Do not edit by hand.",
        f"-- Source: Missions/{name}.trn, {name}.mat, {name}.bzn",
        "-- Consumed by CRVenusWeather (sulfur pools, volcanic vents, playable bounds).",
        "",
        "return {",
        f'    mission = "{name}",',
        f"    bounds  = {{ minX = {fmt(bounds[0])}, maxX = {fmt(bounds[1])}, minZ = {fmt(bounds[2])}, maxZ = {fmt(bounds[3])} }},",
        f"    terrain = {{ minX = {fmt(min_x)}, minZ = {fmt(min_z)}, width = {fmt(width)}, depth = {fmt(depth)} }},",
        "    materialLabels = {",
    ]
    for idx in sorted(trn["labels"]):
        lines.append(f'        [{idx}] = "{trn["labels"][idx]}",')
    lines.append("    },")
    lines.append("    sulfur = {")
    lines.append(f"        types = {{ {', '.join(str(t) for t in sorted(types))} }},")
    lines.append(f"        cols = {cells}, rows = {cells}, cell = {fmt(cell_size)},")
    lines.append(f"        originX = {fmt(min_x)}, originZ = {fmt(min_z)},")
    lines.append("        -- { row, firstCol, length, weight }: weight 1 = solid, partial = transition cell")
    lines.append("        runs = {")
    for r, c0, n, w in runs:
        lines.append(f"            {{ {r}, {c0}, {n}, {fmt(w)} }},")
    lines.append("        },")
    lines.append("    },")
    lines.append("    vents = {")
    major_keys = {(round(o["x"], 2), round(o["z"], 2)) for o in major_labels}
    for o in vents + [m for m in major_labels if m not in vents]:
        major = (round(o["x"], 2), round(o["z"], 2)) in major_keys
        lines.append(
            f'        {{ x = {fmt(o["x"])}, y = {fmt(o["y"])}, z = {fmt(o["z"])}, '
            f'label = "{o["label"]}", major = {"true" if major else "false"} }},'
        )
    lines.append("    },")
    lines.append("}")
    out.write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))
    print(f"wrote {out} ({len(runs)} runs, {len(vents)} vents, bounds {bounds})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
