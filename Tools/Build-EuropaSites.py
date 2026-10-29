#!/usr/bin/env python3
"""Generate Scripts/CREuropaSites<NN>.lua for a Europa mission (misn12 "Flying Solo").

The Europa weather director (Scripts/CREuropaWeather.lua) cannot ask the engine
which terrain material lies under a point, and it must not read a 128 KB .mat in
Lua at every launch. This tool reads the mission's .trn / .mat / .bzn once and
writes the facts the director needs as plain Lua data:

  * bounds   the playable box, from the BZN's edge path (two corner points;
             stock misn12 names it `path_edge`, Io's misn10 `edge_path`)
  * frost    anchors for low frost-haze sheets (Europa's analogue of Io's lava
             fog pools), placed over the requested TextureType indices, plus the
             connected patches they belong to. misn12 labels: 0 Thin Ice,
             1 Frozen Tundra, 2 Snowy Rock, 3 Glacial, 4 Base. Frozen Tundra
             (--types 1) is the default: it is only 3 % of the map and is where
             the geysers stand (12 of 16), i.e. the frost the vents deposit.
             Snowy Rock is 89 % of the map, so, like Io's "Lava" type 0, it
             cannot mark a place.
  * vents    every geyser object (ODF eggeizr1 by default) with its label;
             labels that do NOT start with --minor-prefix ("eggeizr") are the
             mission's named landmark geysers (spawn_geyser, choke_geyser, ...)
             and are marked major. NOTE: a BZN object's y is often 0 (the
             editor did not snap it); the director snaps plumes to the terrain
             height at stream-in, so y is only a fallback.

The frost pass is deterministic: score each frost cell by the frost fraction of
its (2k+1)^2 neighbourhood, take the densest first, keep a candidate only if it
is at least --pool-spacing from every anchor already kept, stop at --max-pools.
Anchors stay inside the playable box.

MAT layout (battlezone/terrain/mat.py in the modding toolbox): one little-endian
uint16 per tile, 64x64 tiles per zone, zones row-major, each zone row-major,
south (low z) first. Bits 15-12 are the base material and 11-8 the next material
(same layout and orientation as Tools/Build-IoSites.py / Build-VenusSites.py).

Sources. Each of <mission>.trn / .mat / .bzn comes from, in order:

  --source-dir DIR   a folder holding any of the three (so the converted co-op
                     Missions/ folder can supply misn12cr.bzn while the stock
                     .trn/.mat still come from the archive)
  --zfs FILE         Redux's bzone.zfs, read with the Modding Toolbox's
                     battlezone.archives.zfs

--geysers-json FILE replaces the vents read from the BZN with a list of
{label, x, y, z, odf} rows (the map conversion writes one), for when the
converted map moved or added geysers. A binary BZN is converted to text with the
Toolbox's version_convert module.

Usage:
    python -I Tools/Build-EuropaSites.py misn12 [--source-dir Missions] [--types 1]
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", ROOT.parent / "Battlezone98_Modding_Toolbox"))
DEFAULT_ZFS = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\bzone.zfs")


def load_module(filename: str, name: str):
    """Reuse the Io / Venus tools' readers and placement code instead of copying them."""
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fetch_sources(args) -> dict[str, bytes]:
    names = [f"{args.mission}.trn", f"{args.mission}.mat", f"{args.mission}.bzn"]
    found: dict[str, bytes] = {}
    if args.source_dir:
        folder = Path(args.source_dir)
        for n in names:
            # A Missions/ folder holds the co-op BZN as <stem>cr.bzn; a stock folder holds <stem>.bzn.
            for p in (folder / n.replace(".bzn", "cr.bzn"), folder / n):
                if p.is_file():
                    found[n] = p.read_bytes()
                    break
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mission")
    ap.add_argument("--types", default="1", help="comma list of TextureType indices that count as frost")
    ap.add_argument("--transition-weight", type=float, default=0.5)
    ap.add_argument("--vent-odf", default="eggeizr1")
    ap.add_argument("--minor-prefix", default="eggeizr",
                    help="geyser labels starting with this are minor; every other label is a named landmark (major)")
    ap.add_argument("--geysers-json", default=None, help="[{label,x,y,z,odf}] overriding the BZN's geysers")
    ap.add_argument("--window", type=int, default=2, help="neighbourhood radius in cells for the density score")
    ap.add_argument("--pool-spacing", type=float, default=70.0)
    ap.add_argument("--max-pools", type=int, default=120)
    ap.add_argument("--min-score", type=float, default=0.45, help="smallest frost fraction around an anchor")
    ap.add_argument("--inset", type=float, default=40.0, help="keep anchors this far inside the playable box")
    ap.add_argument("--source-dir", default=None)
    ap.add_argument("--zfs", type=Path, default=DEFAULT_ZFS)
    ap.add_argument("--toolbox", type=Path, default=DEFAULT_TOOLBOX)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    io = load_module("Build-IoSites.py", "build_io_sites")
    venus = io.load_venus_helpers()
    name = args.mission
    sources = fetch_sources(args)

    # The Venus helpers read from disk; stage the three files in a scratch folder
    # so no source data is ever written into Missions/.
    with tempfile.TemporaryDirectory(prefix="europa_sites_") as scratch:
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

    weights = io.lava_weights(grid, types, args.transition_weight)

    edge = paths.get("edge_path") or paths.get("path_edge")
    if edge and len(edge) >= 2:
        xs, zs = [p[0] for p in edge], [p[1] for p in edge]
        bounds = (min(xs), max(xs), min(zs), max(zs))
    else:
        depth = size.get("Depth", 5120.0)
        bounds = (min_x, min_x + width, min_z, min_z + depth)

    clusters = io.clusters_from_weights(weights, 1, cell_size, min_x, min_z, 4)
    pools = io.place_pools(weights, clusters, bounds, cell_size, min_x, min_z, args.window,
                           args.pool_spacing, args.max_pools, args.min_score, args.inset)

    if args.geysers_json:
        rows = json.loads(Path(args.geysers_json).read_text(encoding="utf-8"))
        vents = [{"x": float(r["x"]), "y": float(r.get("y", 0.0)), "z": float(r["z"]),
                  "label": str(r.get("label", "")), "odf": str(r.get("odf", args.vent_odf))} for r in rows
                 if str(r.get("odf", args.vent_odf)).lower() == args.vent_odf.lower()]
        vent_source = f"geysers json {Path(args.geysers_json).name}"
    else:
        vents = [o for o in objects if o["odf"].lower() == args.vent_odf.lower()]
        vent_source = f"{name}.bzn"

    digits = re.sub(r"\D", "", name) or name
    module = f"CREuropaSites{digits}"
    out = Path(args.out) if args.out else ROOT / "Scripts" / f"{module}.lua"

    solid = sum(1 for row in weights for w in row if w >= 1.0)
    lines = [
        f"-- {module}.lua",
        f"-- GENERATED by Tools/Build-EuropaSites.py {name}. Do not edit by hand.",
        f"-- Source: {name}.trn, {name}.mat, vents from {vent_source}",
        "-- Consumed by CREuropaWeather (cryovolcanic vents, frost-haze anchors, playable bounds).",
        "",
        "return {",
        f'    mission = "{name}",',
        f"    bounds  = {{ minX = {io.fmt(bounds[0])}, maxX = {io.fmt(bounds[1])}, minZ = {io.fmt(bounds[2])}, maxZ = {io.fmt(bounds[3])} }},",
        f"    terrain = {{ minX = {io.fmt(min_x)}, minZ = {io.fmt(min_z)}, width = {io.fmt(width)}, depth = {io.fmt(size.get('Depth', 5120.0))} }},",
        "    materialLabels = {",
    ]
    for idx in sorted(trn["labels"]):
        lines.append(f'        [{idx}] = "{trn["labels"][idx]}",')
    lines.append("    },")
    lines.append("    frost = {")
    lines.append(f"        types = {{ {', '.join(str(t) for t in sorted(types))} }},")
    lines.append(f"        cols = {cells}, rows = {cells}, cell = {io.fmt(cell_size)},")
    lines.append(f"        originX = {io.fmt(min_x)}, originZ = {io.fmt(min_z)},")
    lines.append(f"        solidCells = {solid},")
    lines.append("        -- connected frosted patches (8-connected, one empty cell bridged)")
    lines.append("        clusters = {")
    for k in clusters:
        lines.append(
            f"            {{ id = {k['id']}, count = {k['count']}, cx = {io.fmt(k['cx'])}, cz = {io.fmt(k['cz'])}, "
            f"radius = {io.fmt(k['radius'])} }},"
        )
    lines.append("        },")
    lines.append("        -- frost-haze anchors, densest frost first, kept apart and inside the playable box")
    lines.append("        pools = {")
    for p in pools:
        lines.append(
            f"            {{ x = {io.fmt(p['x'])}, z = {io.fmt(p['z'])}, weight = {io.fmt(p['weight'])}, cluster = {p['cluster']} }},"
        )
    lines.append("        },")
    lines.append("    },")
    lines.append("    -- y is the BZN's value and is often 0 (unsnapped); the director snaps to the terrain")
    lines.append("    vents = {")
    for o in vents:
        major = not o["label"].lower().startswith(args.minor_prefix.lower())
        lines.append(
            f'        {{ x = {io.fmt(o["x"])}, y = {io.fmt(o["y"])}, z = {io.fmt(o["z"])}, '
            f'label = "{o["label"]}", major = {"true" if major else "false"} }},'
        )
    lines.append("    },")
    lines.append("}")
    out.write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))
    print(f"wrote {out} ({solid} frost cells, {len(clusters)} patches, "
          f"{len(pools)} anchors, {len(vents)} vents, bounds {bounds})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
