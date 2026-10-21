"""Place Mission 17's firs on Mission 18, without changing terrain or mission objects.

Uses the toolbox's BZN/HG2/MAT readers. All authored paths (including cameras),
objective/spawn zones, stock objects and baked water stay clear. --check repeats
placement and compares the shipped table; no private source assets are needed.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import math
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Scripts/CRStorm18TreesSites.lua"
SEED, SPACING = 18117, 64
PATH_PAD, OBJECT_PAD, ZONE_PAD, WATER_PAD = 50, 40, 20, 18


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Tools" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def model(toolbox):
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.bz1 import read_bzn
    from battlezone.terrain.hg2 import read_hg2
    from battlezone.terrain.mat import read_mat
    forest = load("forest", "Build-Misn17Forest.py")
    storm = load("storm", "Build-Misn18Storm.py")
    bzn = read_bzn(ROOT / "Missions/misn18.bzn", odf_dirs=[ROOT / "ODF"])
    _, heights = read_hg2(ROOT / "Missions/misn18.hg2")
    heights = heights.astype(float) * .1
    mat = read_mat(ROOT / "Missions/misn18.mat", 2, 4)
    text = (ROOT / "Scripts/CRStorm18Sites.lua").read_text()
    scenery = forest.parse_lua(text[text.index("return ") + 7:])
    objects = [(o.label, o.fields["transform"].value[9], o.fields["transform"].value[11], o.prjid)
               for o in bzn.objects]
    paths = {p["label"].value.rstrip(b"\0").decode(): list(p["points"].value) for p in bzn.paths}
    zones = storm.keep_clear(objects, paths)
    # BZN trigger paths are mostly single points. Also reserve the connecting
    # player approaches/return and the explicit spawn-to-transport Goto lanes.
    base = next((x, z) for label, x, z, _ in objects if label == "avrecy2_recycler")
    transport = next((x, z) for label, x, z, _ in objects if label == "hbtran0038_i76building")
    paths["main_approach"] = [base] + [paths[n][0] for n in ("spawn1a", "spawn2a", "spawn3a", "transfound")] + [transport]
    paths["alternate_approach"] = [base] + [paths[n][0] for n in ("spawnalt1a", "spawnalt1b", "spawnalt2a", "spawnalt2b", "spawnalt3a", "spawnalt3b", "transfound")] + [transport]
    for a, b in [("spawn1b", "transport1"), ("spawnalt1b", "transport2"),
                 ("spawn2b", "transport3"), ("spawnalt2b", "transport4"),
                 ("spawn3b", "transport5"), ("spawnalt3b", "transport6"),
                 ("spawnrand", "transport7"), ("spawnrand2", "transport8"),
                 ("spawnreturn", "transport9")]:
        paths[a + "_goto_" + b] = [paths[a][0], paths[b][0]]
    # All water cells, expanded by a trunk/canopy bank margin.
    water = []
    mask = scenery["watermask"]
    for row, runs in enumerate(mask["rows"], mask["firstRow"]):
        for col, length in zip(runs[::2], runs[1::2]):
            water.extend((c * 5, row * 5 + 97280) for c in range(col, col + length))

    def height(x, z):
        r, c = (z - 97280) / 5, x / 5
        iz, ix = int(r), int(c)
        rz, rx = r - iz, c - ix
        return float((heights[iz, ix] * (1 - rx) + heights[iz, ix + 1] * rx) * (1 - rz) +
                     (heights[iz + 1, ix] * (1 - rx) + heights[iz + 1, ix + 1] * rx) * rz)

    def distance_segment(x, z, a, b):
        dx, dz = b[0] - a[0], b[1] - a[1]
        d2 = dx * dx + dz * dz
        t = max(0, min(1, ((x - a[0]) * dx + (z - a[1]) * dz) / d2)) if d2 else 0
        return math.hypot(x - a[0] - t * dx, z - a[1] - t * dz)

    def clear(x, z):
        if any(math.hypot(x - a, z - b) < r + ZONE_PAD for a, b, r, _ in zones):
            return False
        if any(math.hypot(x - a, z - b) < OBJECT_PAD for _, a, b, _ in objects):
            return False
        for line in paths.values():
            segments = zip(line, line[1:]) if len(line) > 1 else [(line[0], line[0])]
            if any(distance_segment(x, z, a, b) < PATH_PAD for a, b in segments):
                return False
        return not any(math.hypot(x - a, z - b) < WATER_PAD for a, b in water)

    rng, sites = random.Random(SEED), []
    for z in range(97330, 102350, SPACING):
        for x in range(50, 2510, SPACING):
            px, pz = round(x + rng.uniform(-18, 18), 2), round(z + rng.uniform(-18, 18), 2)
            odf = "c17frst" + str(rng.randrange(1, 5))
            yaw, keep = round(rng.uniform(0, math.tau), 4), rng.random()
            slope = math.hypot(height(px + 6, pz) - height(px - 6, pz),
                               height(px, pz + 6) - height(px, pz - 6)) / 12
            if int(mat[int((pz - 97280) / 20), int(px / 20)]) >> 12 not in (0, 1):
                continue
            if keep > .85 or slope > .6 or not clear(px, pz):
                continue
            sites.append({"label": "cr18_tree%04d" % (len(sites) + 1), "odf": odf,
                          "position": [px, round(height(px, pz), 2), pz], "yaw": yaw})
    # The runtime's fixed query budget covers every possible tree in a strike.
    cells = {}
    for s in sites:
        p = s["position"]
        k = (math.floor(p[0] / 64), math.floor(p[2] / 64))
        cells[k] = cells.get(k, 0) + 1
        assert clear(p[0], p[2])
    assert max(cells.values()) <= 4
    data = {"seed": SEED, "spacing": SPACING, "sites": sites}
    body = "-- Generated by Tools/Build-Misn18Trees.py; reuse the credited Mission 17 fir assets.\nreturn "
    body += storm.lua(data) + "\n"
    return body, len(sites)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    from bzmodellibs import toolbox_root
    parser.add_argument("--toolbox", type=Path, default=toolbox_root())
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    body, count = model(args.toolbox)
    if args.check:
        assert OUTPUT.read_text() == body, "Mission 18 tree sites differ; regenerate"
    else:
        OUTPUT.write_text(body, newline="\n")
    print(f"Mission 18 trees: {count} sites; all object/zone/path/water exclusions pass")
