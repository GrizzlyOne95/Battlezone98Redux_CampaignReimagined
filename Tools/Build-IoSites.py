#!/usr/bin/env python3
"""Generate Scripts/CRIoSites<NN>.lua for an Io mission (misn10 "The Race is On").

The Io weather director (Scripts/CRIoWeather.lua) cannot ask the engine which
terrain material lies under a point, and it must not read a 128 KB .mat in Lua
at every launch. This tool reads the mission's .trn / .mat / .bzn once and
writes the facts the director needs as plain Lua data:

  * bounds   the playable box, from the BZN's `edge_path` (two corner points)
  * lava     run-length encoded .mat cells whose base or next material is one of
             the requested TextureType indices, PLUS pool anchors placed over
             them (see below) and the connected clusters they belong to
  * vents    every geyser object (ODF eggeizr1 by default) with its label;
             labels starting with --major-prefix ("geyser", the relic sites) are
             marked major

Which TextureType is lava is decided from the .trn and the shipped art, not
guessed. misn10 labels: 0 Lava, 1 Lava Pool, 3 Sulphur Deposits, 4 Hardened Lava,
5 Base (unused). The io_detail_atlas emissive map (IO_ATLAS_E.dds) says which
tiles actually glow: the Lava Pool tile (IO11SA0) is the strongest emitter, the
Lava tiles (IO00*) carry faint glowing cracks, and the Sulphur / Hardened tiles
glow not at all. Type 0 is also 58 % of the map, so, like Venus's "Sulphur
Deposits", it cannot mark a place: the default is --types 1.

Pool anchors are placed HERE rather than at run time because misn10 is 29 %
lava pool (18,944 solid cells): flood-filling and thinning that in Lua at every
launch would hitch the load frame. The greedy pass is deterministic: score each
lava cell by the lava fraction of its (2k+1)^2 neighbourhood, take the densest
first, keep a candidate only if it is at least --pool-spacing from every pool
already kept, and stop at --max-pools. Pools are kept inside the playable box.

MAT layout (battlezone/terrain/mat.py in the modding toolbox): one little-endian
uint16 per tile, 64x64 tiles per zone, zones row-major, each zone row-major,
south (low z) first. Bits 15-12 are the base material and 11-8 the next
material (same layout and orientation as Tools/Build-VenusSites.py).

Sources. misn10 is not shipped in Missions/ (it is the stock Redux map), so the
inputs come from either:

  --source-dir DIR   a folder holding misn10.trn, misn10.mat, misn10.bzn
  --zfs FILE         Redux's bzone.zfs; the three files are read straight out of
                     it with the Modding Toolbox's battlezone.archives.zfs

A binary BZN is converted to text with the Toolbox's version_convert module.

Usage:
    python Tools/Build-IoSites.py misn10 [--zfs "<Redux>/bzone.zfs"] [--types 1]
"""

from __future__ import annotations

import argparse
import importlib.util
import math
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", ROOT.parent / "Battlezone98_Modding_Toolbox"))
DEFAULT_ZFS = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\bzone.zfs")


def load_venus_helpers():
    """Reuse the Venus tool's trn / mat / bzn readers instead of copying them."""
    spec = importlib.util.spec_from_file_location("build_venus_sites", Path(__file__).with_name("Build-VenusSites.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fetch_sources(args) -> dict[str, bytes]:
    names = [f"{args.mission}.trn", f"{args.mission}.mat", f"{args.mission}.bzn"]
    if args.source_dir:
        folder = Path(args.source_dir)
        return {n: (folder / n).read_bytes() for n in names}
    sys.path.insert(0, str(args.toolbox))
    from battlezone.archives.zfs import ZFSArchive  # noqa: E402

    archive = ZFSArchive(args.zfs)
    return {n: archive.read(n) for n in names}


def to_text_bzn(raw: bytes, toolbox: Path) -> bytes:
    if b"binarySave [1] =\ntrue" not in raw[:200].replace(b"\r", b""):
        return raw
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.version_convert import convert_bzn  # noqa: E402

    return convert_bzn(raw, "redux").data


def lava_weights(grid, types, transition_weight):
    rows, cols = len(grid), len(grid[0])
    weights = [[0.0] * cols for _ in range(rows)]
    for r in range(rows):
        for c in range(cols):
            v = grid[r][c]
            base, nxt = (v >> 12) & 15, (v >> 8) & 15
            if base in types:
                weights[r][c] = 1.0
            elif nxt in types:
                weights[r][c] = transition_weight
    return weights


def runs_from_weights(weights):
    runs = []
    for r, row in enumerate(weights):
        c, n = 0, len(row)
        while c < n:
            w = row[c]
            if w <= 0.0:
                c += 1
                continue
            start = c
            c += 1
            while c < n and row[c] == w:
                c += 1
            runs.append((r, start, c - start, w))
    return runs


def clusters_from_weights(weights, gap, cell, origin_x, origin_z, min_cells):
    rows, cols = len(weights), len(weights[0])
    seen = [[False] * cols for _ in range(rows)]
    clusters = []
    reach = 1 + gap
    for r0 in range(rows):
        for c0 in range(cols):
            if weights[r0][c0] <= 0.0 or seen[r0][c0]:
                continue
            seen[r0][c0] = True
            stack, members = [(r0, c0)], []
            while stack:
                r, c = stack.pop()
                members.append((r, c))
                for dr in range(-reach, reach + 1):
                    for dc in range(-reach, reach + 1):
                        nr, nc = r + dr, c + dc
                        if 0 <= nr < rows and 0 <= nc < cols and weights[nr][nc] > 0.0 and not seen[nr][nc]:
                            seen[nr][nc] = True
                            stack.append((nr, nc))
            if len(members) < min_cells:
                continue
            sw = sum(weights[r][c] for r, c in members)
            cx = sum((origin_x + (c + 0.5) * cell) * weights[r][c] for r, c in members) / sw
            cz = sum((origin_z + (r + 0.5) * cell) * weights[r][c] for r, c in members) / sw
            radius = max(math.hypot(origin_x + (c + 0.5) * cell - cx, origin_z + (r + 0.5) * cell - cz) for r, c in members)
            clusters.append({"count": len(members), "weight": sw, "cx": cx, "cz": cz, "radius": radius, "members": members})
    clusters.sort(key=lambda k: (-k["count"], k["cx"], k["cz"]))
    for i, k in enumerate(clusters, 1):
        k["id"] = i
    return clusters


def place_pools(weights, clusters, bounds, cell, origin_x, origin_z, window, spacing, max_pools, min_score, inset):
    rows, cols = len(weights), len(weights[0])
    # Integral image for the neighbourhood fraction.
    integral = [[0.0] * (cols + 1) for _ in range(rows + 1)]
    for r in range(rows):
        run = 0.0
        for c in range(cols):
            run += weights[r][c]
            integral[r + 1][c + 1] = integral[r][c + 1] + run

    def box(r, c, k):
        r0, r1 = max(0, r - k), min(rows - 1, r + k)
        c0, c1 = max(0, c - k), min(cols - 1, c + k)
        total = integral[r1 + 1][c1 + 1] - integral[r0][c1 + 1] - integral[r1 + 1][c0] + integral[r0][c0]
        return total, (r1 - r0 + 1) * (c1 - c0 + 1)

    member_cluster = {}
    for k in clusters:
        for rc in k["members"]:
            member_cluster[rc] = k["id"]

    min_x, max_x, min_z, max_z = bounds
    candidates = []
    for r in range(rows):
        for c in range(cols):
            if weights[r][c] < 1.0:
                continue
            x = origin_x + (c + 0.5) * cell
            z = origin_z + (r + 0.5) * cell
            if not (min_x + inset <= x <= max_x - inset and min_z + inset <= z <= max_z - inset):
                continue
            total, area = box(r, c, window)
            score = total / area
            if score >= min_score:
                candidates.append((-score, r, c, x, z, total))
    candidates.sort()

    pools = []
    for neg, r, c, x, z, _ in candidates:
        if len(pools) >= max_pools:
            break
        if all(math.hypot(x - p["x"], z - p["z"]) >= spacing for p in pools):
            pools.append({"x": x, "z": z, "weight": -neg, "cluster": member_cluster.get((r, c), 0)})
    return pools


def fmt(v: float) -> str:
    return ("%.2f" % v).rstrip("0").rstrip(".")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mission")
    ap.add_argument("--types", default="1", help="comma list of TextureType indices that count as glowing lava")
    ap.add_argument("--transition-weight", type=float, default=0.5)
    ap.add_argument("--vent-odf", default="eggeizr1")
    ap.add_argument("--major-prefix", default="geyser")
    ap.add_argument("--window", type=int, default=3, help="neighbourhood radius in cells for the density score")
    ap.add_argument("--pool-spacing", type=float, default=110.0)
    ap.add_argument("--max-pools", type=int, default=400)
    ap.add_argument("--min-score", type=float, default=0.55, help="smallest lava fraction around a pool anchor")
    ap.add_argument("--inset", type=float, default=40.0, help="keep pools this far inside the playable box")
    ap.add_argument("--source-dir", default=None)
    ap.add_argument("--zfs", type=Path, default=DEFAULT_ZFS)
    ap.add_argument("--toolbox", type=Path, default=DEFAULT_TOOLBOX)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    venus = load_venus_helpers()
    name = args.mission
    sources = fetch_sources(args)

    # The Venus helpers read from disk; stage the three files in a scratch folder
    # next to the output so no source data is ever written into Missions/.
    import tempfile

    with tempfile.TemporaryDirectory(prefix="io_sites_") as scratch:
        scratch = Path(scratch)
        (scratch / f"{name}.trn").write_bytes(sources[f"{name}.trn"])
        (scratch / f"{name}.mat").write_bytes(sources[f"{name}.mat"])
        (scratch / f"{name}.bzn").write_bytes(to_text_bzn(sources[f"{name}.bzn"], args.toolbox))
        trn = venus.read_trn(scratch / f"{name}.trn")
        mat = (scratch / f"{name}.mat").read_bytes()
        objects, paths = venus.parse_bzn(scratch / f"{name}.bzn")

    size = trn["size"]
    min_x, min_z = size.get("MinX", 0.0), size.get("MinZ", 0.0)
    width = size.get("Width", 5120.0)
    cells = int((len(mat) // 2) ** 0.5)
    if cells * cells * 2 != len(mat) or cells % venus.ZONE:
        print("unexpected .mat size", len(mat), file=sys.stderr)
        return 1
    zones = cells // venus.ZONE
    grid = venus.unzone(mat, zones, zones)
    cell_size = width / cells
    types = {int(t) for t in args.types.split(",") if t.strip()}

    weights = lava_weights(grid, types, args.transition_weight)
    runs = runs_from_weights(weights)

    edge = paths.get("edge_path")
    if edge and len(edge) >= 2:
        xs, zs = [p[0] for p in edge], [p[1] for p in edge]
        bounds = (min(xs), max(xs), min(zs), max(zs))
    else:
        depth = size.get("Depth", 5120.0)
        bounds = (min_x, min_x + width, min_z, min_z + depth)

    clusters = clusters_from_weights(weights, 1, cell_size, min_x, min_z, 4)
    pools = place_pools(weights, clusters, bounds, cell_size, min_x, min_z, args.window,
                        args.pool_spacing, args.max_pools, args.min_score, args.inset)

    vents = [o for o in objects if o["odf"].lower() == args.vent_odf.lower()]

    digits = re.sub(r"\D", "", name) or name
    module = f"CRIoSites{digits}"
    out = Path(args.out) if args.out else ROOT / "Scripts" / f"{module}.lua"

    solid = sum(1 for row in weights for w in row if w >= 1.0)
    lines = [
        f"-- {module}.lua",
        f"-- GENERATED by Tools/Build-IoSites.py {name}. Do not edit by hand.",
        f"-- Source: {name}.trn, {name}.mat, {name}.bzn (stock Redux bzone.zfs)",
        "-- Consumed by CRIoWeather (lava fog pools, volcanic vents, playable bounds).",
        "",
        "return {",
        f'    mission = "{name}",',
        f"    bounds  = {{ minX = {fmt(bounds[0])}, maxX = {fmt(bounds[1])}, minZ = {fmt(bounds[2])}, maxZ = {fmt(bounds[3])} }},",
        f"    terrain = {{ minX = {fmt(min_x)}, minZ = {fmt(min_z)}, width = {fmt(width)}, depth = {fmt(size.get('Depth', 5120.0))} }},",
        "    materialLabels = {",
    ]
    for idx in sorted(trn["labels"]):
        lines.append(f'        [{idx}] = "{trn["labels"][idx]}",')
    lines.append("    },")
    lines.append("    lava = {")
    lines.append(f"        types = {{ {', '.join(str(t) for t in sorted(types))} }},")
    lines.append(f"        cols = {cells}, rows = {cells}, cell = {fmt(cell_size)},")
    lines.append(f"        originX = {fmt(min_x)}, originZ = {fmt(min_z)},")
    lines.append(f"        solidCells = {solid},")
    lines.append("        -- { row, firstCol, length, weight }: weight 1 = molten, partial = transition cell")
    lines.append("        runs = {")
    for r, c0, n, w in runs:
        lines.append(f"            {{ {r}, {c0}, {n}, {fmt(w)} }},")
    lines.append("        },")
    lines.append("        -- connected lava expanses (8-connected, one empty cell bridged)")
    lines.append("        clusters = {")
    for k in clusters:
        lines.append(
            f"            {{ id = {k['id']}, count = {k['count']}, cx = {fmt(k['cx'])}, cz = {fmt(k['cz'])}, "
            f"radius = {fmt(k['radius'])} }},"
        )
    lines.append("        },")
    lines.append("        -- fog / glow anchors, densest lava first, kept apart and inside the playable box")
    lines.append("        pools = {")
    for p in pools:
        lines.append(
            f"            {{ x = {fmt(p['x'])}, z = {fmt(p['z'])}, weight = {fmt(p['weight'])}, cluster = {p['cluster']} }},"
        )
    lines.append("        },")
    lines.append("    },")
    lines.append("    vents = {")
    for o in vents:
        major = o["label"].lower().startswith(args.major_prefix.lower())
        lines.append(
            f'        {{ x = {fmt(o["x"])}, y = {fmt(o["y"])}, z = {fmt(o["z"])}, '
            f'label = "{o["label"]}", major = {"true" if major else "false"} }},'
        )
    lines.append("    },")
    lines.append("}")
    out.write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))
    print(f"wrote {out} ({len(runs)} runs, {solid} molten cells, {len(clusters)} clusters, "
          f"{len(pools)} pools, {len(vents)} vents, bounds {bounds})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
