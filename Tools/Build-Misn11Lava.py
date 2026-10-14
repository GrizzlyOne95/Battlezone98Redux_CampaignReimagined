#!/usr/bin/env python3
"""Paint Io lava into misn11 ("Bring it Home") and write the matching .mat / .trn / preview.

Stock misn11 is 58 % cracked lava crust (TextureType 0) and 10 % sulphur (type 3); it never
paints the molten "Lava Pool" tile (TextureType 1) and its .trn has no `Lava=` key, so the
engine treats nowhere as lava and a player could simply drive from the start to the launch pad.
This tool is the reproducible fix. It never hand-edits a binary: every run starts from Redux's
own originals and writes

  Missions/misn11.mat   the original tile map plus the painted lava
  Missions/misn11.trn   the original terrain file plus `Lava=1` in [NormalView]
  <preview PNG>         top-down heightmap shading + lava + paths + key objects

How the engine treats lava (decompiled BZ 1.5 and cross-checked against Redux):
  * `[NormalView] Lava=N` names the TextureType index that is lava (CreateTerrainTextureNames
    reads it into `lavaMat`). Without it nothing is lava. misn10 uses `Lava=1` (Lava Pool).
  * Craft::UpdateTemperature damages a craft whose tile's BASE material is `lavaMat`, scaled by how
    many of the surrounding tiles are lava and by how low the craft hovers (only within ~5 m of
    the ground), and flashes the player's screen. So lava damages hovering craft; it does not
    stop them.
  * Pathing: lava cells cost `lavaFactor` and are cliff-like for walkers/soldiers/pilots, and the
    cells next to lava are "hazard", so AI units and tugs route around it. Scavengers skip it.

MAT layout (one little-endian uint16 per 20 m tile, 4x4 zones of 64x64, south first): bits 15-12
base material, 11-8 next material, 7 cap(0)/diagonal(1), 6 flip, 5-4 rotation, 3-0 variant. The
tile transitions were read empirically out of misn10's painted Io mat:
  * (base 0, next 1, cap=0) is a straight edge: the pool is the one orthogonal neighbour named by
    rotation (0 = lower-z row, 1 = higher-x column, 2 = higher-z row, 3 = lower-x column);
  * (base 0, next 1, cap=1) is a corner: the pool fills the two orthogonal neighbours and the
    diagonal between them (0 = lower-z/higher-x, 1 = higher-x/higher-z, 2 = higher-z/lower-x,
    3 = lower-x/lower-z).
Type 1 has no transitions of its own, and neither does a tile touch two different neighbours: a
shoreline tile is (crust, lava) and a sulphur-rim tile is (crust, sulphur). Sulphur (type 3) is the
whole walkable "continent" of this map, and lava is painted INSIDE it (the low basins), so each lava
lake gets a crust moat: the sulphur within MOAT_TILES of any lava is turned back into crust, then the
sulphur rim is re-derived with the same edge/corner rule (verified against all 3,168 stock (0,3)
rim tiles: the model reproduces every one).

Plan (see Docs/MISN11_COOP.md "Lava"):
  * lava fills the low basins (tile height below LAVA_HEIGHT_M with a little seeded noise so the
    shoreline is not a perfect contour);
  * everything the mission needs stays dry: a corridor along each escort/strike path, a pad around
    the start, the launch pads, the bases, the CCA outposts and every spawn point;
  * the shapes are tidied so every shoreline tile is one the tileset can draw;
  * the result is verified (see `verify`): all key points connected over dry ground, the dry route
    start -> launch pad close to the escort route, and the straight line to the pad crossing lava.

Usage:
    python Tools/Build-Misn11Lava.py [--preview Docs/MISN11_LAVA_PREVIEW.png] [--dry-run]
Sources: Redux's bzone.zfs (--zfs) for misn11.mat/.trn, Missions/misn11.hg2 and Missions/misn11.bzn.
"""

from __future__ import annotations

import argparse
import math
import os
import re
import sys
from pathlib import Path

import numpy as np
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", ROOT.parent / "Battlezone98_Modding_Toolbox"))
DEFAULT_ZFS = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux\bzone.zfs")

TILE_M = 20.0
GRID = 256                      # tiles per side (4x4 zones of 64)
WORLD_X0, WORLD_Z0 = 0.0, 97280.0
LAVA_TYPE = 1                   # TextureType1 "Lava Pool"
CRUST_TYPE = 0                  # TextureType0 "Lava" (cracked crust)
SULPHUR_TYPE = 3                # TextureType3 "Sulphur Deposits" (the walkable continent)

# --- the design ------------------------------------------------------------------------------
LAVA_HEIGHT_M = 21.0            # tiles lower than this (plus noise) hold molten lava
NOISE_AMPLITUDE_M = 2.4
NOISE_SIGMA_TILES = 3.0
SEED = 11
MOAT_TILES = 2                  # crust moat between a lava lake and the sulphur around it
MIN_LAVA_COMPONENT_TILES = 24
MIN_DRY_ISLAND_TILES = 10
# Keep-out radii (metres) around the things the mission needs on dry ground. Paths are corridors.
PATH_CORRIDOR_M = {
    "base1": 110.0, "base2": 110.0, "escape": 110.0, "openheimer": 90.0,
    "strike_path1": 75.0, "strike_path2": 75.0,
}
POINT_KEEPOUT_M = {
    "start": 150.0, "strike1": 70.0, "strike2": 70.0, "check2": 80.0, "launch_attack": 120.0,
    "last_camera": 100.0,
}
TEAM1_BUILDING_M = 90.0
LAUNCH_PAD_M = 170.0
CCA_OBJECT_M = 75.0
NAV_M = 80.0
KEEPOUT_EDGE_NOISE_M = 22.0     # the corridor edge wobbles by up to this much
# Dry causeways: spurs the mission needs that no authored path provides. Each is a least-cost walk over
# the terrain (it prefers high ground) kept dry LINK_CORRIDOR_M either side.
#   defector  the convoy waypoint where Oppenheimer's tug breaks off -> the head of the `openheimer` path
#   (owner decision) the start -> armory causeway was removed: the whole central area is lava and the
#   armory/geyser stand on an island pad that ground units cannot reach.
LINK_CORRIDOR_M = 70.0
ARMORY_ISLAND_M = 50.0          # the mid-map armory + geyser keep a minimal dry pad (unreachable over ground)
LINK_HEIGHT_PREFERENCE = 0.35


# --- reading the sources -----------------------------------------------------------------------
def load_toolbox(toolbox: Path):
    sys.path.insert(0, str(toolbox))
    from battlezone.archives.zfs import ZFSArchive  # noqa: E402
    from battlezone.terrain.hg2 import read_hg2  # noqa: E402
    from battlezone.terrain.mat import pack_mat_zones, unpack_mat_zones  # noqa: E402

    return ZFSArchive, read_hg2, pack_mat_zones, unpack_mat_zones


def read_bzn_features(bzn_path: Path):
    text = bzn_path.read_bytes().decode("latin-1").replace("\r\n", "\n")
    paths = {}
    start = text.find("[AiPaths]")
    for block in text[start:].split("[AiPath]\n")[1:]:
        label = re.search(r"^label = (.*)$", block, re.M).group(1)
        points = [(float(x), float(z)) for x, z in re.findall(r"x \[1\] =\n(\S+)\n  z \[1\] =\n(\S+)", block)]
        paths[label] = points
    objects = []
    for block in text.split("[GameObject]\n")[1:]:
        prj = re.search(r"^PrjID \[1\] =\n(\S+)", block, re.M).group(1)
        label = (re.search(r"^label = (.*)$", block, re.M) or [None, ""])[1]
        team = int(re.search(r"^team \[1\] =\n(\d+)", block, re.M).group(1))
        x, _y, z = re.search(r"^pos \[1\] =\n  x \[1\] =\n(\S+)\n  y \[1\] =\n(\S+)\n  z \[1\] =\n(\S+)",
                             block, re.M).groups()
        objects.append({"odf": prj, "label": label, "team": team, "x": float(x), "z": float(z)})
    return paths, objects


def to_tile(x: float, z: float):
    return int((z - WORLD_Z0) // TILE_M), int((x - WORLD_X0) // TILE_M)


def tile_center(r: int, c: int):
    return WORLD_X0 + (c + 0.5) * TILE_M, WORLD_Z0 + (r + 0.5) * TILE_M


# --- the plan ------------------------------------------------------------------------------------
def tile_heights(hg2: np.ndarray) -> np.ndarray:
    """Mean terrain height in metres per 20 m tile (hg2 is 5 m samples at 0.1 m per unit)."""
    return (hg2.astype(np.float64) * 0.1).reshape(GRID, 4, GRID, 4).mean(axis=(1, 3))


def seeded_noise(seed: int, sigma: float) -> np.ndarray:
    field = ndi.gaussian_filter(np.random.RandomState(seed).standard_normal((GRID, GRID)), sigma, mode="wrap")
    return field / np.abs(field).max()


def distance_to(mask: np.ndarray) -> np.ndarray:
    """Metres from each tile to the nearest True tile of mask (inf when mask is empty)."""
    if not mask.any():
        return np.full(mask.shape, np.inf)
    return ndi.distance_transform_edt(~mask) * TILE_M


def rasterize_polyline(points, width_tiles):
    out = np.zeros((GRID, GRID), bool)
    for (x0, z0), (x1, z1) in zip(points, points[1:]) if len(points) > 1 else []:
        steps = max(2, int(math.hypot(x1 - x0, z1 - z0) / (TILE_M * 0.5)))
        for i in range(steps + 1):
            r, c = to_tile(x0 + (x1 - x0) * i / steps, z0 + (z1 - z0) * i / steps)
            if 0 <= r < GRID and 0 <= c < GRID:
                out[r, c] = True
    for x, z in points:
        r, c = to_tile(x, z)
        if 0 <= r < GRID and 0 <= c < GRID:
            out[r, c] = True
    return out


def least_cost_walk(heights, a, b):
    """Dijkstra over tiles from tile a to tile b preferring high ground; returns the tile list."""
    import heapq

    cost = 1.0 + LINK_HEIGHT_PREFERENCE * np.maximum(0.0, 28.0 - heights)
    dist = np.full((GRID, GRID), np.inf)
    prev = {}
    dist[a] = 0.0
    heap = [(0.0, a)]
    while heap:
        d, (r, c) = heapq.heappop(heap)
        if (r, c) == b:
            break
        if d > dist[r, c]:
            continue
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                if not dr and not dc:
                    continue
                rr, cc = r + dr, c + dc
                if 0 <= rr < GRID and 0 <= cc < GRID:
                    nd = d + cost[rr, cc] * (1.4142 if dr and dc else 1.0)
                    if nd < dist[rr, cc]:
                        dist[rr, cc] = nd
                        prev[(rr, cc)] = (r, c)
                        heapq.heappush(heap, (nd, (rr, cc)))
    walk, node = [b], b
    while node != a:
        node = prev[node]
        walk.append(node)
    return walk[::-1]


def link_polylines(heights, paths, objects, start_xz):
    base1_waypoint = paths["base1"][3]                    # the waypoint beside cam1 (Waypoint 1)
    links = {
        "defector": (base1_waypoint, paths["openheimer"][0]),
    }
    out = {}
    for name, (p, q) in links.items():
        walk = least_cost_walk(heights, to_tile(*p), to_tile(*q))
        out[name] = [tile_center(r, c) for r, c in walk]
    return out


def keepout_field(paths, objects, start_xz, edge_noise, links):
    """Signed margin in metres: negative = this tile must stay dry (inside some keep-out)."""
    margin = np.full((GRID, GRID), np.inf)

    def add(mask, radius):
        nonlocal margin
        margin = np.minimum(margin, distance_to(mask) - radius)

    for label, radius in PATH_CORRIDOR_M.items():
        add(rasterize_polyline(paths[label], 1), radius)
    for label, radius in POINT_KEEPOUT_M.items():
        pts = [start_xz] if label == "start" else paths[label]
        add(rasterize_polyline(pts, 1), radius)
    for pts in links.values():
        add(rasterize_polyline(pts, 1), LINK_CORRIDOR_M)
    for obj in objects:
        r, c = to_tile(obj["x"], obj["z"])
        if not (0 <= r < GRID and 0 <= c < GRID):
            continue
        pad = np.zeros((GRID, GRID), bool)
        pad[r, c] = True
        if obj["odf"] == "avslf" or obj["odf"].startswith("egg"):
            add(pad, ARMORY_ISLAND_M)
        elif obj["odf"] == "ablpad":
            add(pad, LAUNCH_PAD_M)
        elif obj["team"] == 1 and obj["odf"] != "player":
            add(pad, TEAM1_BUILDING_M if obj["odf"].startswith("ab") else NAV_M)
        elif obj["team"] == 5:
            add(pad, CCA_OBJECT_M)
        elif obj["odf"].startswith("egg"):
            add(pad, NAV_M)
    return margin + edge_noise * KEEPOUT_EDGE_NOISE_M


def tidy(mask: np.ndarray, allowed: np.ndarray) -> np.ndarray:
    """Shapes the tileset can draw: every outside tile touches the mask on 0, 1 or 2 ADJACENT sides."""
    mask = mask & allowed
    for _ in range(80):
        n = np.roll(mask, 1, 0); s = np.roll(mask, -1, 0); w = np.roll(mask, 1, 1); e = np.roll(mask, -1, 1)
        count = n.astype(int) + s + w + e
        bad = (~mask) & ((count >= 3) | (n & s) | (w & e))
        if not bad.any():
            return mask
        mask = mask | (bad & allowed)
        # A bad tile that may not join the mask: shave the mask tiles that surround it instead.
        stuck = bad & ~allowed
        if stuck.any():
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                mask = mask & ~np.roll(np.roll(stuck, -dr, 0), -dc, 1)
    return mask


BOX3 = np.ones((3, 3), bool)


def dilate_box(mask, radius):
    return ndi.binary_dilation(mask, structure=BOX3, iterations=radius) if radius > 0 else mask.copy()


def central_region(paths, start_xz, objects):
    """Tiles enclosed by the escort route (west + north), the launch_attack/escape route (east) and the
    start/haulers (south): the central area the owner wants fully molten."""
    from matplotlib.path import Path as MplPath

    pad2 = next(o for o in objects if o["label"] == "launch_pad2")
    ring = (list(paths["base1"]) + list(paths["base2"]) + [paths["launch_attack"][0]] + list(paths["escape"])
            + [(pad2["x"], pad2["z"]), start_xz])
    poly = MplPath(ring)
    rows, cols = np.mgrid[0:GRID, 0:GRID]
    pts = np.column_stack([(cols.ravel() + 0.5) * TILE_M + WORLD_X0, (rows.ravel() + 0.5) * TILE_M + WORLD_Z0])
    return poly.contains_points(pts).reshape(GRID, GRID), ring


def plan_lava(heights, sulphur, paths, objects, start_xz, links):
    """Returns (lava, sulphur_after, margin, allowed)."""
    noise = seeded_noise(SEED, NOISE_SIGMA_TILES)
    low = (heights + noise * NOISE_AMPLITUDE_M) < LAVA_HEIGHT_M
    central, _ring = central_region(paths, start_xz, objects)
    low = low | central
    edge_noise = seeded_noise(SEED + 1, 2.0)
    margin = keepout_field(paths, objects, start_xz, edge_noise, links)
    allowed = ~(margin < 0.0)
    lava = low & allowed
    cross = ndi.generate_binary_structure(2, 1)
    lava = ndi.binary_opening(lava, structure=cross, iterations=1) & allowed
    lava = ndi.binary_closing(lava, structure=cross, iterations=1) & allowed
    lab, n = ndi.label(lava)
    for i, size in enumerate(ndi.sum(lava, lab, range(1, n + 1)), 1):
        if size < MIN_LAVA_COMPONENT_TILES:
            lava[lab == i] = False
    lab, n = ndi.label(~lava)
    for i, size in enumerate(ndi.sum(~lava, lab, range(1, n + 1)), 1):
        island = lab == i
        if size < MIN_DRY_ISLAND_TILES and allowed[island].all():
            lava[island] = True
    lava = tidy(lava, allowed)
    # The moat: sulphur may not come within MOAT_TILES of lava; re-tidy the sulphur outline outside it.
    moat = dilate_box(lava, MOAT_TILES)
    sulphur_after = tidy(sulphur & ~moat, ~moat & dilate_box(sulphur, 1))
    return lava, sulphur_after, margin, allowed


# --- painting -------------------------------------------------------------------------------------
def entry(base, nxt, cap=0, flip=0, rot=0, var=0):
    return (base << 12) | (nxt << 8) | (cap << 7) | (flip << 6) | (rot << 4) | var


def paint(mat: np.ndarray, lava: np.ndarray, sulphur: np.ndarray):
    """Rebuild every tile from the solid masks. Tiles that did not change keep their original entry."""
    out = mat.copy()
    rows, cols = np.arange(GRID)[:, None], np.arange(GRID)[None, :]
    h = (rows * 73856093 ^ cols * 19349663 ^ SEED * 83492791) & 0xFFFFFFFF   # deterministic scatter
    rot_s, flip_s, var_s = (h >> 8) & 3, (h >> 11) & 1, (h >> 13) & 3

    def solid(mask, rr, cc):
        return 0 <= rr < GRID and 0 <= cc < GRID and bool(mask[rr, cc])

    stats = {"lava": 0, "shore_edge": 0, "shore_corner": 0, "rim_edge": 0, "rim_corner": 0, "crust": 0,
             "sulphur": 0}
    for r in range(GRID):
        for c in range(GRID):
            old = int(mat[r, c])
            if lava[r, c]:
                out[r, c] = entry(LAVA_TYPE, LAVA_TYPE, 0, 0, int(rot_s[r, c]), 0)
                stats["lava"] += 1
                continue
            if sulphur[r, c]:
                if ((old >> 12) & 15, (old >> 8) & 15) == (SULPHUR_TYPE, SULPHUR_TYPE):
                    out[r, c] = old
                else:
                    out[r, c] = entry(SULPHUR_TYPE, SULPHUR_TYPE, 0, 0, int(rot_s[r, c]), 0)
                stats["sulphur"] += 1
                continue
            for name, mask, other, nxt in (("shore", lava, sulphur, LAVA_TYPE), ("rim", sulphur, lava, SULPHUR_TYPE)):
                north, south = solid(mask, r - 1, c), solid(mask, r + 1, c)   # r-1 is lower z
                west, east = solid(mask, r, c - 1), solid(mask, r, c + 1)
                sides = int(north) + int(south) + int(west) + int(east)
                if sides == 0:
                    continue
                if any(solid(other, r + dr, c + dc) for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    raise SystemExit(f"tile ({r},{c}) touches both lava and sulphur: widen the moat")
                if sides == 1:
                    rot, cap = (0 if north else 1 if east else 2 if south else 3), 0
                elif sides == 2 and not ((north and south) or (east and west)):
                    rot = 0 if (north and east) else 1 if (east and south) else 2 if (south and west) else 3
                    cap = 1
                else:
                    raise SystemExit(f"untidy {name} at tile ({r},{c}): {sides} sides")
                same = (((old >> 12) & 15, (old >> 8) & 15, (old >> 7) & 1, (old >> 4) & 3)
                        == (CRUST_TYPE, nxt, cap, rot))
                out[r, c] = old if same else entry(CRUST_TYPE, nxt, cap, int(flip_s[r, c]), rot, 0)
                stats[f"{name}_{'corner' if cap else 'edge'}"] += 1
                break
            else:
                if ((old >> 12) & 15, (old >> 8) & 15) == (CRUST_TYPE, CRUST_TYPE):
                    out[r, c] = old
                else:
                    out[r, c] = entry(CRUST_TYPE, CRUST_TYPE, 0, int(flip_s[r, c]), int(rot_s[r, c]), int(var_s[r, c]))
                stats["crust"] += 1
    return out, stats


def patch_trn(raw: bytes) -> bytes:
    text = raw.decode("latin-1")
    newline = "\r\n" if "\r\n" in text else "\n"
    if re.search(r"(?mi)^Lava\s*=", text):
        text = re.sub(r"(?mi)^Lava\s*=.*$", f"Lava={LAVA_TYPE}", text, count=1)
    else:
        text = re.sub(r"(?m)^(\[NormalView\]\r?\n)", lambda m: m.group(1) + f"Lava={LAVA_TYPE}{newline}", text, count=1)
    if f"Lava={LAVA_TYPE}" not in text:
        raise SystemExit("could not set Lava= in [NormalView]")
    section = re.search(r"(?m)^\[TextureType%d\]" % LAVA_TYPE, text)
    if not section or "Lava Pool" not in text[section.start():section.start() + 40]:
        raise SystemExit(f"TextureType{LAVA_TYPE} is not the Lava Pool tile in this .trn")
    return text.encode("latin-1")


# --- verification ---------------------------------------------------------------------------------
def dijkstra(passable, sources, cost_weight=None):
    """8-connected shortest path lengths (metres) from the source tiles over passable tiles."""
    import heapq

    dist = np.full((GRID, GRID), np.inf)
    heap = []
    for r, c in sources:
        if passable[r, c]:
            dist[r, c] = 0.0
            heap.append((0.0, r, c))
    heapq.heapify(heap)
    steps = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
             (-1, -1, 1.4142), (-1, 1, 1.4142), (1, -1, 1.4142), (1, 1, 1.4142)]
    while heap:
        d, r, c = heapq.heappop(heap)
        if d > dist[r, c]:
            continue
        for dr, dc, w in steps:
            rr, cc = r + dr, c + dc
            if 0 <= rr < GRID and 0 <= cc < GRID and passable[rr, cc]:
                if dr and dc and not (passable[r, cc] and passable[rr, c]):
                    continue   # no squeezing between two diagonal lava corners
                nd = d + w * TILE_M
                if nd < dist[rr, cc]:
                    dist[rr, cc] = nd
                    heapq.heappush(heap, (nd, rr, cc))
    return dist


def verify(lava, paths, objects, start_xz, box):
    report = {}
    dry = ~lava
    pad = next(o for o in objects if o["label"] == "launch_pad")
    pad2 = next(o for o in objects if o["label"] == "launch_pad2")
    keys = {"start": start_xz, "launch_pad": (pad["x"], pad["z"]), "launch_pad2": (pad2["x"], pad2["z"])}
    for label in ("base1", "base2", "escape", "openheimer", "strike_path1", "strike_path2"):
        for i, p in enumerate(paths[label]):
            keys[f"{label}[{i}]"] = p
    for label in ("strike1", "strike2", "check2", "launch_attack", "last_camera"):
        keys[label] = paths[label][0]
    for o in objects:
        if o["team"] in (1, 5) and o["odf"] not in ("player", "avslf"):   # the armory is a deliberate island
            keys[f"{o['odf']}:{o['label']}"] = (o["x"], o["z"])
    start_tile = to_tile(*start_xz)
    dist = dijkstra(dry, [start_tile])
    unreachable = [k for k, (x, z) in keys.items() if not np.isfinite(dist[to_tile(x, z)])]
    report["unreachable"] = unreachable
    on_lava = [k for k, (x, z) in keys.items() if lava[to_tile(x, z)]]
    report["key_points_on_lava"] = on_lava
    pr, pc = to_tile(pad["x"], pad["z"])
    straight = math.hypot(pad["x"] - start_xz[0], pad["z"] - start_xz[1])
    report["straight_m"] = straight
    report["dry_route_m"] = float(dist[pr, pc])
    # Straight line lava crossing.
    steps = int(straight / (TILE_M * 0.5))
    crossing = sum(1 for i in range(steps + 1)
                   if lava[to_tile(start_xz[0] + (pad["x"] - start_xz[0]) * i / steps,
                                   start_xz[1] + (pad["z"] - start_xz[1]) * i / steps)]) * TILE_M * 0.5
    report["straight_line_lava_m"] = crossing
    # The best path allowed to cross lava, only up to LAVA_ALLOW metres of it ("cheat" length).
    # A shortcut with only a narrow lava strip is what the design forbids: compute the shortest
    # path that crosses at most 80 m of lava by layering (cheap check: dilate lava by 2 tiles
    # and require connectivity differences).
    narrow = ndi.binary_erosion(lava, structure=np.ones((3, 3), bool), iterations=2)
    short = dijkstra(~narrow, [start_tile])
    report["route_if_80m_lava_crossable_m"] = float(short[pr, pc])
    r0, r1, c0, c1 = box
    report["lava_fraction_box"] = float(lava[r0:r1, c0:c1].mean())
    return report


# --- preview --------------------------------------------------------------------------------------
def render_preview(path, hg2, lava, mat_new, paths, objects, start_xz, box, report, bounds, links):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import LightSource

    heights = hg2.astype(np.float64) * 0.1
    shade = LightSource(azdeg=315, altdeg=42).shade(heights, cmap=plt.cm.gist_earth, vert_exag=1.3,
                                                    dx=5, dy=5, blend_mode="overlay")
    x_lo, x_hi, z_lo, z_hi = bounds
    fig, ax = plt.subplots(figsize=(15, 13))
    ax.imshow(shade, origin="lower", extent=(0, 5120, WORLD_Z0, WORLD_Z0 + 5120))
    extent = (0, 5120, WORLD_Z0, WORLD_Z0 + 5120)
    molten = np.ma.masked_where(~lava, np.ones_like(lava, float))
    ax.imshow(molten, origin="lower", extent=extent, cmap=matplotlib.colors.ListedColormap(["#ff5a00"]), alpha=0.72,
              interpolation="nearest")
    base = (mat_new >> 12) & 15
    nxt = (mat_new >> 8) & 15
    shore = (base == CRUST_TYPE) & (nxt == LAVA_TYPE)
    ax.imshow(np.ma.masked_where(~shore, np.ones(shore.shape)), origin="lower", extent=extent,
              cmap=matplotlib.colors.ListedColormap(["#ffb000"]), alpha=0.6, interpolation="nearest")
    sulphur = (base == 3)
    ax.imshow(np.ma.masked_where(~sulphur, np.ones(sulphur.shape)), origin="lower", extent=extent,
              cmap=matplotlib.colors.ListedColormap(["#f0e68c"]), alpha=0.25, interpolation="nearest")
    colours = {"base1": "#00e5ff", "base2": "#2f6bff", "escape": "#39ff14", "openheimer": "#ff2d2d",
               "strike_path1": "#ffa500", "strike_path2": "#ff00ff"}
    for label, pts in paths.items():
        if label == "edge_path":
            (xa, za), (xb, zb) = pts
            ax.plot([xa, xb, xb, xa, xa], [za, za, zb, zb, za], color="white", lw=1.0, ls="--")
            continue
        xs, zs = [p[0] for p in pts], [p[1] for p in pts]
        ax.plot(xs, zs, "-o" if len(pts) > 1 else "o", ms=4, lw=2.0, color=colours.get(label, "yellow"))
        ax.annotate(label, (xs[0], zs[0]), color="white", fontsize=7, xytext=(4, 4), textcoords="offset points")
    for name, pts in links.items():
        ax.plot([p[0] for p in pts], [p[1] for p in pts], color="#c8ff00", lw=1.6, ls="--")
        ax.annotate("link:" + name, pts[len(pts) // 2], color="#c8ff00", fontsize=7)
    pad = next(o for o in objects if o["label"] == "launch_pad")
    ax.plot([start_xz[0], pad["x"]], [start_xz[1], pad["z"]], color="white", lw=1.4, ls=":")
    for o in objects:
        colour = {0: "gray", 1: "deepskyblue", 5: "red"}.get(o["team"], "yellow")
        ax.plot(o["x"], o["z"], "s" if o["team"] == 1 else "^", color=colour, ms=5, mec="black", mew=0.6)
        ax.annotate(o["label"] or o["odf"], (o["x"], o["z"]), color="white", fontsize=6, xytext=(3, 3),
                    textcoords="offset points")
    ax.set_xlim(x_lo, x_hi)
    ax.set_ylim(z_lo, z_hi)
    ax.set_title("misn11 lava plan  |  orange = molten lava (damages hovering craft), amber = shoreline tiles, "
                 f"red/cyan/blue/green = CCA / escort / pad routes  |  lava {report['lava_fraction_box']*100:.0f}% of the "
                 f"playable box, dry route start->pad {report['dry_route_m']:.0f} m vs straight {report['straight_m']:.0f} m "
                 f"(straight line crosses {report['straight_line_lava_m']:.0f} m of lava)", fontsize=8)
    fig.savefig(path, dpi=85, bbox_inches="tight")
    plt.close(fig)


# --- main -----------------------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--zfs", type=Path, default=DEFAULT_ZFS, help="Redux bzone.zfs (the original misn11.mat/.trn)")
    ap.add_argument("--source-dir", type=Path, help="folder holding the original misn11.mat and misn11.trn instead")
    ap.add_argument("--toolbox", type=Path, default=DEFAULT_TOOLBOX)
    ap.add_argument("--missions", type=Path, default=ROOT / "Missions")
    ap.add_argument("--preview", type=Path, help="write the top-down preview PNG here")
    ap.add_argument("--dry-run", action="store_true", help="plan and verify, write nothing")
    args = ap.parse_args()

    ZFSArchive, read_hg2, pack_mat_zones, unpack_mat_zones = load_toolbox(args.toolbox)
    if args.source_dir:
        original_mat = (args.source_dir / "misn11.mat").read_bytes()
        original_trn = (args.source_dir / "misn11.trn").read_bytes()
    else:
        archive = ZFSArchive(args.zfs)
        original_mat, original_trn = archive.read("misn11.mat"), archive.read("misn11.trn")
    mat = unpack_mat_zones(original_mat, 4, 4).astype(np.int64)
    header, hg2 = read_hg2(args.missions / "misn11.hg2")
    assert hg2.shape == (1024, 1024), hg2.shape
    paths, objects = read_bzn_features(args.missions / "misn11.bzn")
    player = next(o for o in objects if o["odf"] == "player")
    start_xz = (player["x"], player["z"])
    (xa, za), (xb, zb) = paths["edge_path"]
    x_lo, x_hi, z_lo, z_hi = min(xa, xb), max(xa, xb), min(za, zb), max(za, zb)
    r0, c0 = to_tile(x_lo, z_lo)
    r1, c1 = to_tile(x_hi, z_hi)
    box = (r0, r1, c0, c1)

    heights = tile_heights(hg2)
    sulphur = (((mat >> 12) & 15) == SULPHUR_TYPE) & (((mat >> 8) & 15) == SULPHUR_TYPE)
    links = link_polylines(heights, paths, objects, start_xz)
    lava, sulphur_after, margin, allowed = plan_lava(heights, sulphur, paths, objects, start_xz, links)
    report = verify(lava, paths, objects, start_xz, box)
    painted, stats = paint(mat, lava, sulphur_after)
    report["sulphur_tiles"] = (int(sulphur.sum()), int(sulphur_after.sum()))

    print(f"lava tiles {int(lava.sum())} ({report['lava_fraction_box']*100:.1f}% of the playable box); "
          f"sulphur solid tiles {sulphur.sum()} -> {sulphur_after.sum()}; {stats}")
    print(f"straight start->pad {report['straight_m']:.0f} m, crossing {report['straight_line_lava_m']:.0f} m of lava; "
          f"dry route {report['dry_route_m']:.0f} m ({report['dry_route_m']/report['straight_m']:.2f}x); "
          f"if 80 m of lava were crossable {report['route_if_80m_lava_crossable_m']:.0f} m")
    for key in ("unreachable", "key_points_on_lava"):
        print(f"{key}: {report[key] or 'none'}")
    if report["unreachable"] or report["key_points_on_lava"]:
        print("verification FAILED", file=sys.stderr)
        return 1

    if args.preview:
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        render_preview(args.preview, hg2, lava, painted, paths, objects, start_xz, box, report,
                       (x_lo - 150, x_hi + 150, z_lo - 150, z_hi + 150), links)
        print(f"wrote {args.preview}")
    if args.dry_run:
        return 0
    out_mat = pack_mat_zones(painted.astype(np.uint16), 4, 4)
    (args.missions / "misn11.mat").write_bytes(out_mat)
    (args.missions / "misn11.trn").write_bytes(patch_trn(original_trn))
    print(f"wrote {args.missions / 'misn11.mat'} ({len(out_mat)} bytes) and misn11.trn (Lava={LAVA_TYPE})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
