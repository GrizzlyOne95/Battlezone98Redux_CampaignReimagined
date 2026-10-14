#!/usr/bin/env python3
"""Render Docs/MISN12_ROUTE_PREVIEW.png: the misn12 ("Flying Solo") map, its paths and the unused east-side route.

Stock misn12 has a long, thin, hand-sculpted ridge route on the east side of the Europa map that neither the
DLL nor the Lua ever references, and a cut Razor One line (misn1224.wav, "I know a fast way out of here. Follow
me.") that nothing plays. This tool draws the evidence so the two can be judged together:

  * the 1.5 (unsmoothed) heightmap, hill-shaded, with the 111 m cliff plateau greyed out;
  * every authored path: used named paths thin and coloured, the unnamed ones faint grey, and the paths no code
    references (stop1, stop2, 2spawn, choke_spawn, path_1, path_edge) highlighted;
  * the key objects, labelled: Drop Zone (nav1), the four checkpoints, the comm tower, the geysers, the silos and
    the muf, the spawn points;
  * the proposed Razor One route (thick magenta, numbered waypoints), from the held position at checkpoint 2, along
    the 25 m wide channel and up onto the 66 m shelf, across the jump, down the 45 m ledge and back to the drop zone;
  * an inset of the jump and a height profile along the route.

The route is DERIVED, not typed in: a least-cost walk over the 5 m heightmap (slope <= 42 degrees, strongly
preferring cells far from a cliff) joins the held position to the shelf lip, the landing ledge to the main floor,
and the floor to the drop zone. The jump itself (lip crest and landing, 98 m apart across the main channel) is the
one thing no ground walk can cross, so it is supplied as a chord. Everything is deterministic: same inputs, same
PNG, same numbers.

Inputs (all in the repository, plus the Modding Toolbox for the HG2 reader):
  Missions/misn12.hg2   unsmoothed Battlezone 1.5 heightmap (1024 x 1024 samples of 5 m, 0.1 m per unit)
  Missions/misn12.bzn   converted co-op map (objects and AI paths)

Usage:
  python Tools/Preview-Misn12Map.py [--output Docs/MISN12_ROUTE_PREVIEW.png] [--toolbox DIR]
                                    [--waypoints-json FILE] [--no-plot]
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from pathlib import Path

import numpy as np
from scipy import ndimage as ndi
from scipy import sparse
from scipy.sparse.csgraph import dijkstra

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", ROOT.parent / "Battlezone98_Modding_Toolbox"))

N = 1024                     # samples per side
CELL_M = 5.0                 # metres per sample
WORLD_X0, WORLD_Z0 = 0.0, 97280.0
HEIGHT_UNIT_M = 0.1
PLATEAU_M = 100.0            # the 111 m default plateau and 138 m massif: unreachable cliff country
MAX_SLOPE_DEG = 42.0
GRAVITY = 9.8                # ASSUMED (no [Gravity] key in misn12.trn); only used for the jump estimate

# The route, as the ordered anchors the least-cost walks join. Everything between anchors is derived.
HOLD = (2942.46, 100810.0)          # check2_geyser: the checkpoint-2 (turret hangar) compound, head of the east hook
SHELF_END = (3340.0, 99690.0)       # flat 66.4 m shelf, 50 m before the launch ramp
LIP = (3343.0, 99632.0)             # crest of the launch ramp (about 81 m)
LANDING = (3347.0, 99518.0)         # landing ledge top (about 43 m), 12 m past the far edge
FLOOR_JOIN = (3472.0, 99042.0)      # where the ledge's descending trench meets the main floor
DROP_ZONE = (3562.0, 97862.0)       # nav1 "Drop Zone" (apcamr20_camerapod) on the 39 m start plateau
WAYPOINT_SPACING_M = 40.0

UNUSED_PATHS = ("stop1", "stop2", "2spawn", "choke_spawn", "path_1", "path_edge")
KEY_LABELS = {
    "apcamr20_camerapod": ("Drop Zone (nav1)", "#00a000", "*", 13),
    "player0_hover": ("player start", "#00a000", "P", 8),
    "checktower1": ("CP1 checktower1", "#d06000", "s", 7),
    "svguntower2": ("CP2 hangar svguntower2", "#d06000", "s", 7),
    "svmuf": ("CP3 muf", "#d06000", "s", 7),
    "svsilo1": ("CP4 silos svsilo1-4", "#d06000", "s", 7),
    "center": ("center (sbhqt2)", "#d06000", "s", 7),
    "svcom_tower": ("COMM TOWER", "#d00000", "D", 8),
    "spawn_geyser": ("spawn_geyser (key ship)", "#2060d0", "^", 6),
    "spawn_geyser1": ("spawn_geyser1", "#2060d0", "^", 5),
    "spawn_geyser2": ("spawn_geyser2", "#2060d0", "^", 5),
    "check2_geyser": ("check2_geyser", "#2060d0", "^", 6),
    "center_geyser": ("center_geyser", "#2060d0", "^", 5),
    "choke_geyser": ("choke_geyser", "#2060d0", "^", 5),
}
MINOR_PREFIXES = {"sbbarr": ("#606060", "s", 3), "sbcafe": ("#606060", "s", 3), "svturr": ("#c02020", ".", 4),
                  "svartl": ("#c02020", "x", 4), "svtank": ("#c02020", ".", 3), "svfigh": ("#c02020", ".", 3),
                  "svapc": ("#c02020", ".", 3), "svscav": ("#808000", ".", 3), "sbsilo": ("#d06000", "s", 4),
                  "apcamr": ("#00a0a0", "o", 4), "eggeizr": ("#2060d0", "^", 3)}


# --- reading the inputs --------------------------------------------------------------------------------
def load_heights(toolbox: Path, hg2_path: Path) -> np.ndarray:
    sys.path.insert(0, str(toolbox))
    from battlezone.terrain.hg2 import read_hg2  # noqa: E402

    _, raw = read_hg2(hg2_path)
    assert raw.shape == (N, N), raw.shape
    return raw.astype(np.float64) * HEIGHT_UNIT_M


def read_bzn(path: Path):
    text = path.read_bytes().decode("latin-1").replace("\r\n", "\n")
    header, *blocks = text.split("[GameObject]\n")
    tail_at = re.search(r"(?m)^(?=name = MultSTMission$)", blocks[-1])
    blocks[-1] = blocks[-1][: tail_at.start()]
    objects = []
    for b in blocks:
        def num(name):
            m = re.search(rf"^\s*{name} \[1\] =\n(\S+)$", b, re.M)
            return float(m.group(1)) if m else None

        lab = re.search(r"^label = (.*)$", b, re.M)
        objects.append({
            "odf": re.search(r"^PrjID \[1\] =\n(\S*)$", b, re.M).group(1),
            "label": lab.group(1).strip() if lab else "",
            "team": int(num("team")), "x": num("posit_x"), "y": num("posit_y"), "z": num("posit_z"),
        })
    paths = []
    for chunk in text[text.index("[AiPaths]"):].split("[AiPath]\n")[1:]:
        lab = re.search(r"^label = (.*)$", chunk, re.M)
        pts = [(float(x), float(z)) for x, z in re.findall(r"  x \[1\] =\n(\S+)\n  z \[1\] =\n(\S+)", chunk)]
        paths.append({"label": lab.group(1).strip() if lab else "", "pts": pts})
    return objects, paths


# --- terrain helpers -----------------------------------------------------------------------------------
def cell(x: float, z: float):
    return int((z - WORLD_Z0) // CELL_M), int((x - WORLD_X0) // CELL_M)


def height_at(m: np.ndarray, x: float, z: float) -> float:
    r, c = cell(x, z)
    return float(m[r, c])


def cell_index(x: float, z: float) -> int:
    r, c = cell(x, z)
    return r * N + c


class Walker:
    """Least-cost ground walks over the heightmap: slope-limited, and hugging the middle of corridors."""

    def __init__(self, m: np.ndarray):
        self.m = m
        gy, gx = np.gradient(m, CELL_M)
        self.slope = np.degrees(np.arctan(np.hypot(gx, gy)))
        self.passable = (self.slope <= MAX_SLOPE_DEG) & (m < PLATEAU_M)
        self.clearance = ndi.distance_transform_edt(self.passable) * CELL_M
        idx = np.arange(N * N).reshape(N, N)
        t = math.tan(math.radians(MAX_SLOPE_DEG))
        rows, cols, weights = [], [], []
        for dr, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
            r0, r1 = slice(0, N - dr), slice(dr, N)
            c0, c1 = (slice(0, N - dc), slice(dc, N)) if dc >= 0 else (slice(-dc, N), slice(0, N + dc))
            a, b = idx[r0, c0], idx[r1, c1]
            d = CELL_M * math.hypot(dr, dc)
            sl = np.abs(m[r0, c0] - m[r1, c1]) / d
            ok = (sl <= t) & self.passable[r0, c0] & self.passable[r1, c1]
            cl = np.minimum(self.clearance[r0, c0], self.clearance[r1, c1])
            cost = d * (1 + sl * 2) * (1 + 200.0 / (cl + 4.0))
            rows.append(a[ok]); cols.append(b[ok]); weights.append(cost[ok])
        self.graph = sparse.coo_matrix(
            (np.concatenate(weights), (np.concatenate(rows), np.concatenate(cols))), shape=(N * N, N * N)).tocsr()

    def walk(self, src, dst):
        dist, pred = dijkstra(self.graph, directed=False, indices=cell_index(*src), return_predecessors=True)
        j = cell_index(*dst)
        if not math.isfinite(dist[j]):
            raise SystemExit(f"no ground walk from {src} to {dst} at {MAX_SLOPE_DEG} degrees")
        out, k = [], j
        while k != cell_index(*src):
            out.append(k)
            k = int(pred[k])
        out.append(cell_index(*src))
        return [((q % N) * CELL_M + CELL_M / 2, (q // N) * CELL_M + WORLD_Z0 + CELL_M / 2) for q in out[::-1]]

    def chord_clear(self, a, b):
        """Smallest clearance (m to the nearest cliff cell) along a straight leg, or minus the number of blocked
        5 m samples when three or more of them are blocked (one or two is the leg clipping a raster corner)."""
        steps = int(math.hypot(b[0] - a[0], b[1] - a[1]) // CELL_M) + 1
        worst, blocked = 1e9, 0
        for t in np.linspace(0.0, 1.0, steps + 1):
            r, c = cell(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            if self.passable[r, c]:
                worst = min(worst, self.clearance[r, c])
            else:
                blocked += 1
        return -float(blocked) if blocked >= 3 else float(worst if worst < 1e9 else 0.0)


def polyline_length(p):
    return sum(math.hypot(p[i + 1][0] - p[i][0], p[i + 1][1] - p[i][1]) for i in range(len(p) - 1))


def resample(p, spacing):
    P = np.array(p)
    d = np.r_[0.0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    ts = np.r_[np.arange(0.0, d[-1], spacing), d[-1]]
    return [(float(np.interp(t, d, P[:, 0])), float(np.interp(t, d, P[:, 1]))) for t in ts]


def build_route(w: Walker):
    """Return {'ground': [A, B, C], 'jump': (LIP, LANDING), 'waypoints': ordered list}."""
    seg_a = w.walk(HOLD, SHELF_END)
    seg_b = w.walk(LANDING, FLOOR_JOIN)
    seg_c = w.walk(FLOOR_JOIN, DROP_ZONE)
    # Short chords where the channel bends tightly, so no straight leg clips a wall.
    wa = resample(seg_a, 15.0) + [LIP]
    wb = [LANDING] + resample(seg_b, 25.0)[1:]
    wc = resample(seg_c, WAYPOINT_SPACING_M)[1:]
    waypoints = wa + wb + wc
    return {"ground": [seg_a, seg_b, seg_c], "waypoints": waypoints, "lip_index": len(wa) - 1}


def normal_route(w: Walker, src, dst):
    return w.walk(src, dst)


def jump_report(m: np.ndarray):
    """Numbers about the launch ramp, the gap and the landing, read straight off the heightmap."""
    cols = [3330.0, 3340.0, 3345.0, 3350.0, 3360.0]
    rep = {}
    z_grid = np.arange(99700.0, 99480.0, -5.0)
    prof = {int(x): [round(height_at(m, x, z), 1) for z in z_grid] for x in cols}
    x = 3345.0
    hs = [height_at(m, x, z) for z in z_grid]
    crest_i = int(np.argmax([h if z < 99660 else 0 for h, z in zip(hs, z_grid)]))
    rep["crest"] = (x, float(z_grid[crest_i]), hs[crest_i])
    floor = [z for z, h in zip(z_grid, hs) if h < 3.0]
    rep["floor_z"] = (max(floor), min(floor))
    land = [z for z, h in zip(z_grid, hs) if z < min(floor) and h > 38.0]
    rep["landing_edge_z"] = max(land)
    rep["landing_h"] = height_at(m, x, rep["landing_edge_z"] - 15.0)
    rep["gap_crest_to_landing_m"] = rep["crest"][1] - rep["landing_edge_z"]
    rep["gap_floor_to_floor_m"] = rep["floor_z"][0] - rep["floor_z"][1]
    rep["drop_m"] = rep["crest"][2] - rep["landing_h"]
    ramp = [(z, h) for z, h in zip(z_grid, hs) if 99632 <= z <= 99660]
    rep["ramp_slope_deg"] = math.degrees(math.atan2(rep["crest"][2] - 66.4, 99660.0 - rep["crest"][1]))
    rep["profile_columns"] = prof
    rep["shelf_height_m"] = height_at(m, 3345.0, 99750.0)
    rep["ledge_height_m"] = height_at(m, 3345.0, 99450.0)
    return rep


def ballistic(speed, ramp_deg, drop, g=GRAVITY):
    """Horizontal distance covered when launched at `speed` off a ramp of `ramp_deg`, landing `drop` m lower."""
    a = math.radians(ramp_deg)
    vx, vz = speed * math.cos(a), speed * math.sin(a)
    t = (vz + math.sqrt(vz * vz + 2 * g * drop)) / g
    return vx * t, t


def route_profile(m: np.ndarray, route):
    pts = route["waypoints"]
    dist, heights, marks = [0.0], [height_at(m, *pts[0])], {}
    total = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(seg // CELL_M))
        for k in range(1, n + 1):
            t = k / n
            dist.append(total + seg * t)
            heights.append(height_at(m, a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        total += seg
        if i + 1 == route["lip_index"]:
            marks["lip"] = total
        if i == route["lip_index"]:
            marks["landing"] = total
    return np.array(dist), np.array(heights), marks, total


def slope_stats(m: np.ndarray, dist: np.ndarray, heights: np.ndarray, lo: float, hi: float):
    sel = (dist >= lo) & (dist <= hi)
    d, h = dist[sel], heights[sel]
    # 20 m window slope, the scale a hover craft's pitch actually follows
    out = []
    for i in range(len(d)):
        j = int(np.searchsorted(d, d[i] + 20.0))
        if j < len(d):
            out.append(math.degrees(math.atan2(h[j] - h[i], d[j] - d[i])))
    return (min(out), max(out)) if out else (0.0, 0.0)


# --- drawing --------------------------------------------------------------------------------------------
def shaded(m: np.ndarray):
    import matplotlib
    from matplotlib.colors import LightSource, LinearSegmentedColormap

    cmap = LinearSegmentedColormap.from_list("eu", [(0.0, "#0b1d3a"), (0.04, "#1f5f8b"), (0.2, "#3f9a8c"),
                                                    (0.45, "#a8c97f"), (0.7, "#e6d9a0"), (1.0, "#f4efe0")])
    low = np.clip(m, 0, 85)
    rgb = LightSource(azdeg=315, altdeg=38).shade(low, cmap=cmap, vert_exag=2.5, blend_mode="soft", vmin=0, vmax=85)
    plateau = m >= PLATEAU_M
    rgb[plateau] = rgb[plateau] * 0.25 + np.array([0.80, 0.80, 0.82, 1.0]) * 0.75
    return rgb


def render(path: Path, m, objects, paths, w: Walker, route, report, extra):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rgb = shaded(m)
    X0, X1, Z0, Z1 = 1100.0, 4700.0, 97500.0, 101300.0
    fig = plt.figure(figsize=(19.5, 12.4), dpi=100)
    ax = fig.add_axes([0.03, 0.045, 0.60, 0.925])
    ext = (0, N * CELL_M, WORLD_Z0, WORLD_Z0 + N * CELL_M)
    ax.imshow(rgb, origin="lower", extent=ext, interpolation="nearest")
    ax.set_xlim(X0, X1); ax.set_ylim(Z0, Z1); ax.set_aspect("equal")
    ax.set_xticks(range(1200, 4701, 200)); ax.set_yticks(range(97600, 101301, 200)); ax.grid(alpha=0.18, lw=0.4)
    ax.tick_params(labelsize=7)
    ax.set_title("misn12 Flying Solo: authored paths, key objects and the unused east-side route "
                 "(x east, z north, metres)", fontsize=11)

    by_label = {o["label"]: o for o in objects if o["label"]}
    # authored paths
    for p in paths:
        xs, zs = [q[0] for q in p["pts"]], [q[1] for q in p["pts"]]
        if not p["label"]:
            ax.plot(xs, zs, color="#7a7a7a", lw=0.5, alpha=0.55)
        elif p["label"] in UNUSED_PATHS:
            continue
        elif len(xs) > 1:
            ax.plot(xs, zs, color="#ffffff", lw=1.0, alpha=0.8)
            ax.text(xs[len(xs) // 2], zs[len(zs) // 2], p["label"], fontsize=5.5, color="#ffffff", alpha=0.9)
    for p in paths:
        if p["label"] in UNUSED_PATHS:
            xs, zs = [q[0] for q in p["pts"]], [q[1] for q in p["pts"]]
            if len(xs) > 1:
                ax.plot(xs, zs, color="#ff9a00", lw=1.2, ls=(0, (6, 4)))
                ax.text(xs[0] + 40, zs[0] + 20, "path_edge (UNUSED, diagonal guide)", fontsize=6.5, color="#ff9a00",
                        rotation=-46, rotation_mode="anchor")
            else:
                ax.plot(xs, zs, marker="D", color="#ff9a00", ms=6, mec="k", mew=0.6)
                ax.text(xs[0] + 18, zs[0] + 18, f"{p['label']} (UNUSED)", fontsize=7, color="#ffb84d",
                        bbox=dict(fc="k", alpha=0.55, pad=1, lw=0))

    # objects
    for o in objects:
        if o["odf"] == "sscr_1":
            continue
        if o["label"] in KEY_LABELS:
            continue
        for pref, (col, mk, ms) in MINOR_PREFIXES.items():
            if o["odf"].startswith(pref):
                ax.plot(o["x"], o["z"], mk, color=col, ms=ms, mew=0.6, mec="k" if mk in "s^o" else col, alpha=0.9)
                break
    for label, (text, col, mk, ms) in KEY_LABELS.items():
        o = by_label.get(label)
        if not o:
            continue
        ax.plot(o["x"], o["z"], mk, color=col, ms=ms, mec="k", mew=0.7, zorder=6)
        dx, dz = (16, 16)
        if label in ("svmuf", "center_geyser"):
            dx, dz = (16, -50)
        if label == "spawn_geyser2":
            dx, dz = (-110, -55)
        if label == "check2_geyser":
            dx, dz = (-330, -90)
        if label == "svguntower2":
            dx, dz = (-300, 40)
        if label == "choke_geyser":
            dx, dz = (-60, 25)
        if label == "svsilo1":
            dx, dz = (-60, 35)
        if label == "apcamr20_camerapod":
            dx, dz = (24, -30)
        if label == "player0_hover":
            dx, dz = (30, 18)
        ax.text(o["x"] + dx, o["z"] + dz, text, fontsize=7, color="#101010", zorder=7,
                bbox=dict(fc="white", alpha=0.78, pad=1.2, lw=0))
    # scrap fields
    sc = [o for o in objects if o["odf"] == "sscr_1"]
    ax.plot([o["x"] for o in sc], [o["z"] for o in sc], ".", color="#c0b000", ms=1.5, alpha=0.8)

    # the proposed route
    pts = route["waypoints"]
    li = route["lip_index"]
    ground = pts[: li + 1], pts[li + 1:]
    ax.plot([p[0] for p in pts[: li + 1]], [p[1] for p in pts[: li + 1]], color="#ff00d0", lw=2.6, zorder=8)
    ax.plot([p[0] for p in pts[li + 1:]], [p[1] for p in pts[li + 1:]], color="#ff00d0", lw=2.6, zorder=8)
    ax.annotate("", xy=pts[li + 1], xytext=pts[li], arrowprops=dict(arrowstyle="-|>", color="#ffee00", lw=3.2,
                                                                  mutation_scale=22, ls="-"), zorder=9)
    for i in range(0, len(pts), 4):
        ax.plot(pts[i][0], pts[i][1], "o", color="#ff00d0", ms=3.2, mec="k", mew=0.5, zorder=9)
    hold = by_label["check2_geyser"]
    ax.plot(hold["x"], hold["z"], "o", ms=16, mfc="none", mec="#ff00d0", mew=2.2, zorder=9)
    ax.text(hold["x"] - 560, hold["z"] + 80, "RAZOR ONE held here (proposed):\ncheckpoint-2 compound, check2_geyser",
            fontsize=8, color="#ff00d0", fontweight="bold", bbox=dict(fc="white", alpha=0.85, pad=2, lw=0), zorder=9)
    ax.text(3400, 99640, f"THE JUMP\nlip {report['crest'][2]:.0f} m -> ledge {report['landing_h']:.0f} m\n"
            f"{report['gap_crest_to_landing_m']:.0f} m across the main channel", fontsize=8, color="#7a0066",
            fontweight="bold", bbox=dict(fc="#ffee00", alpha=0.9, pad=2, lw=0), zorder=10)
    ax.text(3395, 100120, "east hook channel:\n25 m wide, 0 m floor", fontsize=7.5, color="#101010",
            bbox=dict(fc="white", alpha=0.78, pad=1.2, lw=0), zorder=9)
    ax.text(3385, 99870, "66.4 m shelf\n(40 m wide)", fontsize=7.5, color="#101010",
            bbox=dict(fc="white", alpha=0.78, pad=1.2, lw=0), zorder=9)
    ax.text(3400, 99350, "45 m ledge", fontsize=7.5, color="#101010", bbox=dict(fc="white", alpha=0.78, pad=1.2, lw=0),
            zorder=9)

    # legend (hand-drawn, so it never covers the map)
    from matplotlib.lines import Line2D

    handles = [Line2D([0], [0], color="#ff00d0", lw=2.6, label="proposed Razor One route (derived)"),
               Line2D([0], [0], color="#ffee00", lw=3, label="the jump (one-way, north to south)"),
               Line2D([0], [0], color="#ff9a00", marker="D", lw=1.2, ls="--", label="authored paths no code uses"),
               Line2D([0], [0], color="#ffffff", lw=1.0, label="named paths the DLL/Lua use"),
               Line2D([0], [0], color="#7a7a7a", lw=0.8, label="unnamed paths (patrol and scav legs)"),
               Line2D([0], [0], marker="s", color="#d06000", lw=0, mec="k", label="checkpoints / key buildings"),
               Line2D([0], [0], marker="^", color="#2060d0", lw=0, mec="k", label="geysers (eggeizr1)"),
               Line2D([0], [0], marker=".", color="#c02020", lw=0, label="CCA units and turrets"),
               Line2D([0], [0], marker=".", color="#c0b000", lw=0, label="scrap fields"),
               Line2D([0], [0], marker="s", color="#cdcdd2", lw=0, mec="k", label="cliff country, 111 m and above")]
    ax.legend(handles=handles, loc="lower left", fontsize=7, framealpha=0.9)

    # --- inset: the jump
    jx0, jx1, jz0, jz1 = 3240.0, 3470.0, 99440.0, 99780.0
    axj = fig.add_axes([0.655, 0.43, 0.30, 0.50])
    r0, r1 = cell(jx0, jz0)[0], cell(jx0, jz1)[0]
    c0, c1 = cell(jx0, jz0)[1], cell(jx1, jz0)[1]
    sub = m[r0:r1, c0:c1]
    im = axj.imshow(np.clip(sub, 0, 90), origin="lower", extent=(jx0, jx1, jz0, jz1), cmap="nipy_spectral", vmin=0,
                    vmax=90, interpolation="nearest")
    xs = np.linspace(jx0, jx1, c1 - c0)
    zs = np.linspace(jz0, jz1, r1 - r0)
    cs = axj.contour(xs, zs, sub, levels=[10, 20, 30, 40, 50, 60, 70, 80], colors="k", linewidths=0.5, alpha=0.7)
    axj.clabel(cs, fmt="%d m", fontsize=6)
    axj.set_aspect("equal"); axj.tick_params(labelsize=7)
    axj.set_title("The jump: heightmap (colour = metres) with 10 m contours", fontsize=9)
    jp = [p for p in pts if jx0 <= p[0] <= jx1 and jz0 <= p[1] <= jz1]
    axj.plot([p[0] for p in jp], [p[1] for p in jp], "-o", color="#ff00d0", ms=3, lw=2)
    axj.annotate("", xy=LANDING, xytext=LIP, arrowprops=dict(arrowstyle="-|>", color="#ffee00", lw=3, mutation_scale=18))
    cr = report["crest"]
    axj.text(3250, 99650, f"shelf {report['shelf_height_m']:.1f} m (flat)\nlaunch ramp up to {cr[2]:.0f} m\n"
             f"at z {cr[1]:.0f}, rising {report['ramp_slope_deg']:.0f} deg", fontsize=7.5,
             bbox=dict(fc="white", alpha=0.85, pad=2, lw=0))
    axj.text(3395, 99555, f"channel floor 0 m\n{report['gap_floor_to_floor_m']:.0f} m wide", fontsize=7.5,
             bbox=dict(fc="white", alpha=0.85, pad=2, lw=0))
    axj.text(3250, 99455, f"ledge {report['ledge_height_m']:.1f} m; landing edge z "
             f"{report['landing_edge_z']:.0f}\nedge to edge {report['gap_crest_to_landing_m']:.0f} m, "
             f"drop {report['drop_m']:.0f} m", fontsize=7.5, bbox=dict(fc="white", alpha=0.85, pad=2, lw=0))

    # --- inset: profile
    dist, heights, marks, total = extra["profile"]
    axp = fig.add_axes([0.665, 0.06, 0.32, 0.30])
    axp.fill_between(dist, 0, heights, color="#7aa6c8", alpha=0.9)
    axp.plot(dist, heights, color="#0b1d3a", lw=1)
    axp.set_xlim(0, total); axp.set_ylim(0, 95)
    axp.set_xlabel("distance along the route (m)", fontsize=8); axp.set_ylabel("terrain height (m)", fontsize=8)
    axp.tick_params(labelsize=7); axp.grid(alpha=0.3)
    axp.set_title(f"Height profile, {total:.0f} m: hold -> channel -> shelf -> JUMP -> ledge -> floor -> drop zone",
                  fontsize=8.5)
    if "lip" in marks:
        axp.axvspan(marks["lip"], marks.get("landing", marks["lip"] + 100), color="#ffee00", alpha=0.7)
        axp.text(marks["lip"] - 40, 86, "jump", ha="right", fontsize=8, fontweight="bold")
    for dpos, text in extra["profile_labels"]:
        axp.axvline(dpos, color="k", lw=0.5, alpha=0.5)
        axp.text(dpos + 12, 3, text, fontsize=6.5, rotation=90, va="bottom")

    # route facts under the title block
    cax = fig.add_axes([0.962, 0.43, 0.01, 0.50])
    fig.colorbar(im, cax=cax).set_label("height (m)", fontsize=7)
    cax.tick_params(labelsize=7)
    fig.text(0.655, 0.992, extra["caption"], fontsize=8, va="top", family="monospace")
    fig.savefig(path, dpi=100)
    plt.close(fig)


# --- main -----------------------------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--toolbox", type=Path, default=DEFAULT_TOOLBOX)
    ap.add_argument("--missions", type=Path, default=ROOT / "Missions")
    ap.add_argument("--output", type=Path, default=ROOT / "Docs" / "MISN12_ROUTE_PREVIEW.png")
    ap.add_argument("--waypoints-json", type=Path, help="also write the derived Razor One waypoints here")
    ap.add_argument("--no-plot", action="store_true", help="print the numbers only")
    args = ap.parse_args()

    m = load_heights(args.toolbox, args.missions / "misn12.hg2")
    objects, paths = read_bzn(args.missions / "misn12.bzn")
    w = Walker(m)
    route = build_route(w)
    report = jump_report(m)

    pts = route["waypoints"]
    li = route["lip_index"]
    # every straight leg between neighbouring waypoints must stay on passable ground (except the jump leg)
    worst = []
    for i in range(len(pts) - 1):
        if i == li:
            continue
        worst.append((w.chord_clear(pts[i], pts[i + 1]), i))
    bad = [(c, i) for c, i in worst if c < 0]
    dist, heights, marks, total = route_profile(m, route)

    seg_len = [polyline_length(s) for s in route["ground"]]
    hold_to_dz_normal = polyline_length(normal_route(w, HOLD, DROP_ZONE))
    comm = next(o for o in objects if o["label"] == "svcom_tower")
    comm_to_dz = polyline_length(normal_route(w, (comm["x"], comm["z"]), DROP_ZONE))
    comm_to_hold = polyline_length(normal_route(w, (comm["x"], comm["z"]), HOLD))
    jump_leg = math.hypot(pts[li + 1][0] - pts[li][0], pts[li + 1][1] - pts[li][1])
    route_len = total
    a_end_d = polyline_length(pts[:li + 1])

    print(f"route waypoints: {len(pts)} (spacing 15 m in the channel, 25 m on the ledge, {WAYPOINT_SPACING_M:.0f} m on the floor)")
    print(f"hold {HOLD} -> shelf end {SHELF_END}: {seg_len[0]:.0f} m; lip {LIP}; landing {LANDING}")
    print(f"landing -> floor join {FLOOR_JOIN}: {seg_len[1]:.0f} m; floor join -> drop zone {DROP_ZONE}: {seg_len[2]:.0f} m")
    print(f"whole route hold -> drop zone: {route_len:.0f} m (jump leg {jump_leg:.0f} m); normal ground route "
          f"hold -> drop zone: {hold_to_dz_normal:.0f} m; comm tower -> drop zone normal: {comm_to_dz:.0f} m, "
          f"comm tower -> hold: {comm_to_hold:.0f} m")
    print(f"unwalkable chords (excluding the jump): {len(bad)}; tightest clearance on the ground legs "
          f"{min(c for c, _ in worst):.0f} m to the nearest cliff cell")
    for k in ("crest", "floor_z", "landing_edge_z", "landing_h", "gap_crest_to_landing_m", "gap_floor_to_floor_m",
              "drop_m", "ramp_slope_deg", "shelf_height_m", "ledge_height_m"):
        print(f"jump.{k}: {report[k]}")
    for sp in (20.0, 25.0, 30.0, 40.0, 50.0):
        d, t = ballistic(sp, report["ramp_slope_deg"], report["drop_m"])
        print(f"ballistic estimate (g={GRAVITY}): {sp:.0f} m/s off the ramp covers {d:.0f} m in {t:.1f} s "
              f"(needs {report['gap_crest_to_landing_m']:.0f} m)")
    lo_hi = {"channel ramp (z 100050 to 99880)": slope_stats(m, dist, heights, 0, a_end_d)}
    print("20 m slope range along the ground legs (deg):", slope_stats(m, dist, heights, 0, a_end_d), "shelf approach;",
          slope_stats(m, dist, heights, marks.get("landing", 0), total))

    if args.waypoints_json:
        args.waypoints_json.write_text(json.dumps({
            "hold": HOLD, "lip": LIP, "landing": LANDING, "drop_zone": DROP_ZONE,
            "waypoints": [[round(x, 1), round(z, 1), round(height_at(m, x, z), 1)] for x, z in pts],
            "lip_index": li}, indent=1))
    if args.no_plot:
        return 0 if not bad else 1

    labels = [(0.0, "hold (check2)"), (a_end_d - 60, "shelf"), (marks.get("lip", 0) + 4, "lip"),
              (marks.get("landing", 0) + 6, "landing"), (marks.get("landing", 0) + 560, "floor"),
              (total - 30, "drop zone")]
    caption = (f"Proposed Razor route {route_len:.0f} m (normal hangar -> drop zone {hold_to_dz_normal:.0f} m).\n"
               f"Jump: crest {report['crest'][2]:.0f} m -> landing {report['landing_h']:.0f} m, "
               f"{report['gap_crest_to_landing_m']:.0f} m edge to edge, ground AI cannot follow.")
    render(args.output, m, objects, paths, w, route, report,
           {"profile": (dist, heights, marks, total), "profile_labels": labels, "caption": caption})
    print(f"wrote {args.output}")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
