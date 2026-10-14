#!/usr/bin/env python3
"""Generate Scripts/CRTitanSites<NN>.lua for a Titan mission (first user: misn14).

The Titan weather director (Scripts/CRTitanWeather.lua) draws wet methane
pools -- a sky-tinted sheen, low evaporation mist, drizzle ripples -- and
splashes craft that cross them. It cannot ask the engine which terrain material
lies under a point, and it must not read a 128 KB .mat in Lua at every launch,
so this tool reads the mission's .trn / .mat / .hg2 / .bzn once and writes the
facts the director needs as plain Lua data.

Where the methane is (the "MAT painting" rule)
----------------------------------------------
Every stock Titan .trn labels TextureType 0 "Methane Ocean" (atlas tiles TI00*),
1 "Base" and 3 "Rock". On misn14 type 0 covers 95 % of the cells, so the type
alone cannot mark a lake: the elevated orange ground round the bases is type 0
too. What the painting really encodes is the methane SEA: type-0 cells lying on
the map's flat sea floor (misn14: raw height 50 = 5.0 units, the median and the
minimum of the whole heightfield; the islands rise out of it). So a cell is wet
when

  * it is a PURE methane cell (Base and Next nibble both in --types), so a
    methane-to-rock transition tile (a shore tile) is never wet, and
  * its four HG2 samples all sit within --tolerance of the sea level, where the
    sea level is the most common type-0 cell height (the flat floor).

The connected wet components are then split into the open SEA (any component
touching the map's outer edge) and enclosed LAKES (the ponds and channels
trapped between the rock islands), and anchors are placed for the director:

  * pools   anchors over wet ground, inside the playable box, scored by how wet
            the 5x5 neighbourhood is and how close the anchor is to a shore
            (that is where the eye goes and where the craft drive); lakes are
            weighted up. Greedy, best first, at least --pool-spacing apart.
  * wet     the wet mask itself, as run-length rows (start column, length) for
            the rows that overlap the playable box (padded by --mask-pad), so
            the director can answer "is this craft over methane?" with a table
            lookup instead of a terrain query.
  * bounds  the playable box from the BZN's edge path (misn14: edge_path).

MAT layout: one little-endian uint16 per tile, 64x64 tiles per zone, zones
row-major, each zone row-major, south (low z) first; bits 15-12 Base, 11-8 Next
(Tools/Build-VenusSites.py `unzone`, shared with the Io and Europa tools).
HG2 layout: header <HHHHI (version, zone bits, zones x, zones z, map version),
then uint16 samples zone by zone in the same order, low 13 bits = height in
0.1-unit counts, 5 units per sample, so one 20-unit material cell covers 4x4
samples (battlezone/terrain/hg2.py in the modding toolbox).

Sources. Each of <mission>.trn / .mat / .hg2 / .bzn comes from, in order:
  --source-dir DIR   a folder holding any of them
  --zfs FILE         Redux's bzone.zfs, read with the Modding Toolbox

Usage:
    python -I Tools/Build-TitanSites.py misn14 [--zfs <bzone.zfs>]
    python -I Tools/Build-TitanSites.py misn14 --check     # exit 1 if the checked-in file differs
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import struct
import sys
import tempfile
from collections import Counter, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", ROOT.parent / "Battlezone98_Modding_Toolbox"))
DEFAULT_ZFS = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\bzone.zfs")
HG2_HEADER = struct.Struct("<HHHHI")
HG2_MASK = 0x1FFF
HEIGHT_SCALE = 0.1   # world units per raw HG2 count (as Build-Misn11Lava.py / Build-MoonSites.py)


def load_module(filename: str, name: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fetch_sources(args) -> dict[str, bytes]:
    names = [f"{args.mission}.{ext}" for ext in ("trn", "mat", "hg2", "bzn")]
    found: dict[str, bytes] = {}
    if args.source_dir:
        folder = Path(args.source_dir)
        for n in names:
            if (folder / n).is_file():
                found[n] = (folder / n).read_bytes()
    missing = [n for n in names if n not in found]
    if missing:
        sys.path.insert(0, str(args.toolbox))
        from battlezone.archives.zfs import ZFSArchive  # noqa: E402

        archive = ZFSArchive(args.zfs)
        for n in missing:
            found[n] = archive.read(n)
    return found


def to_text_bzn(raw: bytes, toolbox: Path) -> bytes:
    if b"binarySave [1] =\ntrue" not in raw[:200].replace(b"\r", b""):
        return raw
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.version_convert import convert_bzn  # noqa: E402

    return convert_bzn(raw, "redux").data


def read_hg2(raw: bytes) -> tuple[int, list[list[int]]]:
    version, zone_bits, zones_x, zones_z, _map_version = HG2_HEADER.unpack_from(raw, 0)
    if version != 1:
        raise ValueError(f"unexpected HG2 structure version {version}")
    zone = 1 << zone_bits
    count = zones_x * zones_z * zone * zone
    samples = struct.unpack_from("<%dH" % count, raw, HG2_HEADER.size)
    cols, rows = zones_x * zone, zones_z * zone
    grid = [[0] * cols for _ in range(rows)]
    p = 0
    for zz in range(zones_z):
        for zx in range(zones_x):
            for r in range(zone):
                row = grid[zz * zone + r]
                base = zx * zone
                for c in range(zone):
                    row[base + c] = samples[p] & HG2_MASK
                    p += 1
    return zone, grid


def cell_extremes(hg2: list[list[int]], cells: int) -> tuple[list[list[int]], list[list[int]]]:
    """Min and max raw height of the HG2 samples under each material cell."""
    per = len(hg2) // cells
    lo = [[0] * cells for _ in range(cells)]
    hi = [[0] * cells for _ in range(cells)]
    for r in range(cells):
        rows = hg2[r * per:(r + 1) * per]
        for c in range(cells):
            vals = [v for row in rows for v in row[c * per:(c + 1) * per]]
            lo[r][c] = min(vals)
            hi[r][c] = max(vals)
    return lo, hi


def fmt(v: float) -> str:
    return ("%.2f" % v).rstrip("0").rstrip(".")


def label_components(wet: list[list[bool]]):
    rows, cols = len(wet), len(wet[0])
    comp = [[0] * cols for _ in range(rows)]
    info = {}
    next_id = 0
    for r0 in range(rows):
        for c0 in range(cols):
            if not wet[r0][c0] or comp[r0][c0]:
                continue
            next_id += 1
            comp[r0][c0] = next_id
            queue = deque([(r0, c0)])
            count = 0
            while queue:
                r, c = queue.popleft()
                count += 1
                for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    rr, cc = r + dr, c + dc
                    if 0 <= rr < rows and 0 <= cc < cols and wet[rr][cc] and not comp[rr][cc]:
                        comp[rr][cc] = next_id
                        queue.append((rr, cc))
            info[next_id] = {"count": count}
    return comp, info


def shore_distance(wet: list[list[bool]], limit: int) -> list[list[int]]:
    """Chebyshev distance (cells) from each wet cell to the nearest dry cell, capped at limit."""
    rows, cols = len(wet), len(wet[0])
    far = limit + 1
    dist = [[0 if not wet[r][c] else far for c in range(cols)] for r in range(rows)]
    queue = deque((r, c) for r in range(rows) for c in range(cols) if not wet[r][c])
    while queue:
        r, c = queue.popleft()
        d = dist[r][c] + 1
        if d > limit:
            continue
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                rr, cc = r + dr, c + dc
                if 0 <= rr < rows and 0 <= cc < cols and dist[rr][cc] > d:
                    dist[rr][cc] = d
                    queue.append((rr, cc))
    return dist


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mission")
    ap.add_argument("--types", default="0", help="TextureType indices that are methane (misn14: 0 Methane Ocean)")
    ap.add_argument("--tolerance", type=float, default=0.3, help="units above the sea floor still counted as sea")
    ap.add_argument("--pool-spacing", type=float, default=80.0)
    ap.add_argument("--max-pools", type=int, default=160)
    ap.add_argument("--min-wet", type=float, default=0.6, help="smallest wet fraction of an anchor's 5x5 cells")
    ap.add_argument("--shore-reach", type=int, default=8, help="cells from a shore an anchor still scores for it")
    ap.add_argument("--lake-weight", type=float, default=1.35, help="score multiplier for enclosed lakes")
    ap.add_argument("--inset", type=float, default=40.0, help="keep anchors this far inside the playable box")
    ap.add_argument("--mask-pad", type=float, default=600.0, help="wet-mask rows/cols kept beyond the playable box")
    ap.add_argument("--source-dir", default=None)
    ap.add_argument("--zfs", type=Path, default=DEFAULT_ZFS)
    ap.add_argument("--toolbox", type=Path, default=DEFAULT_TOOLBOX)
    ap.add_argument("--out", default=None)
    ap.add_argument("--check", action="store_true", help="compare with the existing output instead of writing")
    args = ap.parse_args()

    venus = load_module("Build-VenusSites.py", "build_venus_sites")
    name = args.mission
    sources = fetch_sources(args)

    with tempfile.TemporaryDirectory(prefix="titan_sites_") as scratch:
        scratch = Path(scratch)
        (scratch / f"{name}.trn").write_bytes(sources[f"{name}.trn"])
        (scratch / f"{name}.bzn").write_bytes(to_text_bzn(sources[f"{name}.bzn"], args.toolbox))
        trn = venus.read_trn(scratch / f"{name}.trn")
        _objects, paths = venus.parse_bzn(scratch / f"{name}.bzn")

    mat = sources[f"{name}.mat"]
    size = trn["size"]
    min_x, min_z = size.get("MinX", 0.0), size.get("MinZ", 0.0)
    width, depth = size.get("Width", 5120.0), size.get("Depth", 5120.0)
    cells = int((len(mat) // 2) ** 0.5)
    if cells * cells * 2 != len(mat) or cells % venus.ZONE:
        print("unexpected .mat size", len(mat), file=sys.stderr)
        return 1
    zones = cells // venus.ZONE
    grid = venus.unzone(mat, zones, zones)
    cell = width / cells
    types = {int(t) for t in args.types.split(",") if t.strip()}

    _zone, hg2 = read_hg2(sources[f"{name}.hg2"])
    if len(hg2) % cells:
        print("HG2 does not tile the material grid", file=sys.stderr)
        return 1
    lo, hi = cell_extremes(hg2, cells)

    pure = [[((grid[r][c] >> 12) & 15) in types and ((grid[r][c] >> 8) & 15) in types
             for c in range(cells)] for r in range(cells)]
    floor_counts = Counter(lo[r][c] for r in range(cells) for c in range(cells) if pure[r][c])
    if not floor_counts:
        print("no methane cells of the requested types", file=sys.stderr)
        return 1
    sea_raw = floor_counts.most_common(1)[0][0]
    tol_raw = int(round(args.tolerance / HEIGHT_SCALE))
    wet = [[pure[r][c] and lo[r][c] >= sea_raw - tol_raw and hi[r][c] <= sea_raw + tol_raw
            for c in range(cells)] for r in range(cells)]

    comp, info = label_components(wet)
    # The open sea is the biggest wet component (on misn14 the map's outermost
    # cells are a dry apron, so "touches the edge" cannot identify it); every
    # other component is an enclosed lake or channel between the islands.
    sea_id = max(info, key=lambda cid: info[cid]["count"]) if info else None
    lake_ids = {cid for cid in info if cid != sea_id}
    shore = shore_distance(wet, args.shore_reach + 2)

    edge = paths.get("edge_path") or paths.get("path_edge")
    if edge and len(edge) >= 2:
        xs, zs = [p[0] for p in edge], [p[1] for p in edge]
        bounds = (min(xs), max(xs), min(zs), max(zs))
    else:
        bounds = (min_x, min_x + width, min_z, min_z + depth)

    # ---- anchors ------------------------------------------------------------------------------
    candidates = []
    for r in range(2, cells - 2):
        for c in range(2, cells - 2):
            if not wet[r][c]:
                continue
            x, z = min_x + (c + 0.5) * cell, min_z + (r + 0.5) * cell
            if not (bounds[0] + args.inset <= x <= bounds[1] - args.inset
                    and bounds[2] + args.inset <= z <= bounds[3] - args.inset):
                continue
            n = sum(1 for dr in range(-2, 3) for dc in range(-2, 3) if wet[r + dr][c + dc])
            frac = n / 25.0
            if frac < args.min_wet:
                continue
            d = shore[r][c]
            shore_score = max(0.0, 1.0 - (max(0, d - 1) / float(args.shore_reach)))
            lake = comp[r][c] in lake_ids
            score = frac * (0.35 + 0.65 * shore_score) * (args.lake_weight if lake else 1.0)
            candidates.append((-score, r, c, x, z, lake, frac, d))
    candidates.sort()
    top = -candidates[0][0] if candidates else 1.0
    pools = []
    spacing2 = args.pool_spacing * args.pool_spacing
    for neg, r, c, x, z, lake, frac, d in candidates:
        if len(pools) >= args.max_pools:
            break
        if any(((p["x"] - x) ** 2 + (p["z"] - z) ** 2) < spacing2 for p in pools):
            continue
        pools.append({"x": x, "z": z, "weight": -neg / top, "lake": lake, "shore": d})

    # ---- wet mask (run-length rows near the playable box) ---------------------------------------
    r_lo = max(0, int((bounds[2] - args.mask_pad - min_z) // cell))
    r_hi = min(cells - 1, int((bounds[3] + args.mask_pad - min_z) // cell))
    c_lo = max(0, int((bounds[0] - args.mask_pad - min_x) // cell))
    c_hi = min(cells - 1, int((bounds[1] + args.mask_pad - min_x) // cell))
    mask_rows = []
    mask_cells = 0
    for r in range(r_lo, r_hi + 1):
        runs = []
        c = c_lo
        while c <= c_hi:
            if wet[r][c]:
                start = c
                while c <= c_hi and wet[r][c]:
                    c += 1
                runs.extend((start, c - start))
                mask_cells += c - start
            else:
                c += 1
        mask_rows.append((r, runs))

    wet_total = sum(1 for r in range(cells) for c in range(cells) if wet[r][c])
    pure_total = sum(1 for r in range(cells) for c in range(cells) if pure[r][c])
    lake_cells = sum(info[i]["count"] for i in lake_ids)

    digits = re.sub(r"\D", "", name) or name
    module = f"CRTitanSites{digits}"
    out = Path(args.out) if args.out else ROOT / "Scripts" / f"{module}.lua"

    lines = [
        f"-- {module}.lua",
        f"-- GENERATED by Tools/Build-TitanSites.py {name}. Do not edit by hand.",
        f"-- Source: {name}.trn, {name}.mat, {name}.hg2, {name}.bzn",
        "-- Consumed by CRTitanWeather (methane pools, wet mask, playable bounds).",
        "",
        "return {",
        f'    mission = "{name}",',
        f"    bounds  = {{ minX = {fmt(bounds[0])}, maxX = {fmt(bounds[1])}, minZ = {fmt(bounds[2])}, maxZ = {fmt(bounds[3])} }},",
        f"    terrain = {{ minX = {fmt(min_x)}, minZ = {fmt(min_z)}, width = {fmt(width)}, depth = {fmt(depth)} }},",
        "    materialLabels = {",
    ]
    for idx in sorted(trn["labels"]):
        lines.append(f'        [{idx}] = "{trn["labels"][idx]}",')
    lines += [
        "    },",
        "    -- A wet cell is a PURE methane cell lying on the flat sea floor (see the generator).",
        "    sea = {",
        f"        types = {{ {', '.join(str(t) for t in sorted(types))} }},",
        f"        level = {fmt(sea_raw * HEIGHT_SCALE)}, tolerance = {fmt(tol_raw * HEIGHT_SCALE)},",
        f"        cols = {cells}, rows = {cells}, cell = {fmt(cell)},",
        f"        originX = {fmt(min_x)}, originZ = {fmt(min_z)},",
        f"        methaneCells = {pure_total}, wetCells = {wet_total}, lakeCells = {lake_cells}, lakes = {len(lake_ids)},",
        "    },",
        "    -- pool anchors, best first: x, z, weight 0..1, lake (enclosed) or open sea, shore distance in cells",
        "    pools = {",
    ]
    for p in pools:
        lines.append(
            f"        {{ x = {fmt(p['x'])}, z = {fmt(p['z'])}, weight = {fmt(p['weight'])}, "
            f"lake = {'true' if p['lake'] else 'false'}, shore = {p['shore']} }},"
        )
    lines += [
        "    },",
        "    -- wet mask: rows[row] = { startCol, length, ... } (0-based cells; row = (z - originZ) / cell)",
        "    wet = {",
        f"        firstRow = {r_lo}, lastRow = {r_hi}, firstCol = {c_lo}, lastCol = {c_hi}, cells = {mask_cells},",
        "        rows = {",
    ]
    for r, runs in mask_rows:
        if runs:
            lines.append(f"            [{r}] = {{ {', '.join(str(v) for v in runs)} }},")
    lines += [
        "        },",
        "    },",
        "}",
    ]
    data = ("\r\n".join(lines) + "\r\n").encode("ascii")

    if args.check:
        current = out.read_bytes() if out.is_file() else b""
        if current != data:
            print(f"{out} is stale; rerun Tools/Build-TitanSites.py {name}", file=sys.stderr)
            return 1
        print(f"{out} is current")
        return 0

    out.write_bytes(data)
    print(f"wrote {out}: sea level {fmt(sea_raw * HEIGHT_SCALE)}, {wet_total} wet of {pure_total} methane cells, "
          f"{len(lake_ids)} lakes ({lake_cells} cells), {len(pools)} anchors "
          f"({sum(1 for p in pools if p['lake'])} on lakes), mask {mask_cells} cells, bounds {bounds}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
