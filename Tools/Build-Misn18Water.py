"""Build the mission 18 (Achilles) water: standing pools, streams that run down into
them and one cascade, as baked meshes plus a run-length watermask for CRWake.

Modelled on Tools/Build-Misn17Jungle.py (priority-flood pools, D8 stream routing on a
blurred surface, the same ribbon and pool-quad bakes, and its `water_mask`, imported
rather than copied) with three differences:

  * NOTHING IS CARVED. Misn17 cuts channel beds into its heightmap; here every pool
    fills an existing closed basin and every stream follows the existing gradient, so
    Missions/misn18.hg2 is read, never written, and its hash is pinned in the manifest.
  * Water is kept out of everything the mission needs: the 24 tornado keep-clear
    circles (Build-Misn18Storm.keep_clear: start/recycler, transport and thrusters, the
    discovery point, every spawn, the ambush column, which also covers the dropship
    ring of CRDrop18) plus a pad, the polylines of the spawn/return/dontgo paths the
    Fury arrivals use, and every stock object. A pool touching that area is rejected; a
    stream ends where it would enter it.
  * One cascade: the steepest drop on the kept streams is cut out of the stream mesh,
    drawn as its own sheet (CR18/Cascade) and given a mist emitter at its foot.

Outputs (Tools/Build-Misn18Storm.py calls this too, so one run writes everything):

  Assets/Models/cr18_pools.mesh, cr18_streams.mesh, cr18_cascade.mesh
  Scripts/CRStorm18Sites.lua            the `watermask`, `water` and `cascade` keys
  References/Misn18Storm/source-assets.json   hashes (water section)

  python Tools/Build-Misn18Water.py --stock <Battlezone_Source>/BZ1/1.5/Battlezone_Install/stock
  python -I Tools/Build-Misn18Water.py --check       (CI: outputs match the manifest)
"""
from pathlib import Path
import argparse
import hashlib
import heapq
import importlib.util
import json
import math
import struct
import sys

try:
    import numpy as np
except ImportError:     # --check needs only the standard library
    np = None

ROOT = Path(__file__).resolve().parents[1]
HG2 = ROOT / "Missions" / "misn18.hg2"
SITES = ROOT / "Scripts" / "CRStorm18Sites.lua"
MANIFEST = ROOT / "References" / "Misn18Storm" / "source-assets.json"
MODELS = ROOT / "Assets" / "Models"
MESHES = {"pools": "cr18_pools.mesh", "streams": "cr18_streams.mesh", "cascade": "cr18_cascade.mesh"}
MATERIALS = {"pools": "CR18/Pools", "streams": "CR18/Streams", "cascade": "CR18/Cascade"}
OUTPUTS = [MODELS / n for n in MESHES.values()]

MIN_X, MIN_Z = 0, 97280
ORIGIN = (1280.0, 0.0, 99840.0)    # meshes are local to this point (render z is mirrored)
MARGIN = 5                          # cells kept dry at the map edge

ZONE_PAD = 30            # m added to every keep-clear circle
PATH_PAD = 45            # m either side of the Fury spawn/return/dontgo path polylines
OBJECT_PAD = 28          # m around every stock object
POOLS = 4                # standing pools chosen
POOL_MIN_CELLS, POOL_MAX_CELLS = 60, 1500
POOL_MIN_DEPTH = 1.3     # m of fill over the lowest cell
POOL_SPACING = 260       # m between chosen pools
POOL_RANGE = (330, 1400) # m from the base/transport: near enough to be seen, outside the zones
ACC_T = 600              # drainage cells (5 m) that make a channel
MIN_STREAM = 90          # m
CASCADE_RUN = 22         # m of stream length for the steepest-drop search
CASCADE_MIN_DROP = 6.0   # m
STREAM_MARGIN = 10       # m: a stream ends this much sooner, so its drawn width and mask stay clear too
N8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Tools" / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def lua(v):
    if isinstance(v, dict):
        return "{" + ",".join(k + "=" + lua(x) for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(lua(x) for x in v) + "}"
    return json.dumps(v)


def flood(h):
    """Priority flood from the border: the surface with every closed basin filled."""
    R, C = h.shape
    fill = h.copy()
    seen = np.zeros(h.shape, bool)
    seen[[0, -1], :] = True
    seen[:, [0, -1]] = True
    pq = [(fill[r, c], r, c) for r, c in zip(*np.nonzero(seen))]
    heapq.heapify(pq)
    while pq:
        v, r, c = heapq.heappop(pq)
        for dr, dc in N8:
            rr, cc = r + dr, c + dc
            if 0 <= rr < R and 0 <= cc < C and not seen[rr, cc]:
                seen[rr, cc] = True
                fill[rr, cc] = max(h[rr, cc], v + 1e-3)
                heapq.heappush(pq, (fill[rr, cc], rr, cc))
    return fill


def blur(h):
    k = np.exp(-.5 * (np.arange(-9, 10) / 3.) ** 2)
    k /= k.sum()
    s = np.pad(h, 9, mode="edge")
    s = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 0, s)
    return np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 1, s)


def stock_inputs(stock, toolbox):
    """(zones, path polylines, object positions) from the stock .bzn, exactly as the
    storm builder reads them."""
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.bz1 import read_bzn
    storm = load("build_misn18_storm", "Build-Misn18Storm.py")
    bzn = read_bzn(Path(stock) / "misn18.bzn", odf_dirs=[Path(stock)])
    objects, points = [], []
    for o in bzn.objects:
        t = o.fields["transform"].value
        objects.append((o.label, t[9], t[11], o.prjid))
        points.append((t[9], t[11]))
    paths, lines = {}, {}
    for p in bzn.paths:
        name = p["label"].value.rstrip(b"\0").decode()
        paths[name] = [(round(x), round(z)) for x, z in p["points"].value]
        lines[name] = [(float(x), float(z)) for x, z in p["points"].value]
    zones = storm.keep_clear(objects, paths)
    fury = [pl for n, pl in lines.items() if n.startswith(("spawn", "return", "dontgo", "transfound"))]
    return zones, fury, points


def exclusion(shape, zones, fury, points, extra=0):
    """True where water must not be: zones + pad, Fury path corridors, stock objects."""
    R, C = shape
    X = np.arange(C) * 5.
    Z = np.arange(R) * 5. + MIN_Z
    XX, ZZ = np.meshgrid(X, Z)
    out = np.zeros(shape, bool)
    for x, z, r, _ in zones:
        out |= (XX - x) ** 2 + (ZZ - z) ** 2 < (r + ZONE_PAD + extra) ** 2
    for x, z in points:
        out |= (XX - x) ** 2 + (ZZ - z) ** 2 < (OBJECT_PAD + extra) ** 2
    for line in fury:
        for (ax, az), (bx, bz) in zip(line, line[1:]) if len(line) > 1 else [(line[0], line[0])]:
            dx, dz = bx - ax, bz - az
            l2 = dx * dx + dz * dz
            t = np.clip(((XX - ax) * dx + (ZZ - az) * dz) / l2, 0, 1) if l2 else 0
            out |= (XX - (ax + dx * t)) ** 2 + (ZZ - (az + dz * t)) ** 2 < (PATH_PAD + extra) ** 2
    return out


def model(g, excl, zones, excl_stream):
    """Pools, streams and the cascade on the heightmap `g` (metres, 5 m grid). Pure."""
    R, C = g.shape
    X = np.arange(C) * 5.
    Z = np.arange(R) * 5. + MIN_Z
    fill = flood(g)
    flow = flood(blur(g))
    # --- pools ---------------------------------------------------------------------
    deep = (fill - g) > .6
    label = np.full(g.shape, -1)
    comps = []
    for r, c in zip(*np.nonzero(deep)):
        if label[r, c] >= 0:
            continue
        comp = [(r, c)]
        label[r, c] = len(comps)
        k = 0
        while k < len(comp):
            a, b = comp[k]
            k += 1
            for dr, dc in N8:
                rr, cc = a + dr, b + dc
                if 0 <= rr < R and 0 <= cc < C and deep[rr, cc] and label[rr, cc] < 0:
                    label[rr, cc] = len(comps)
                    comp.append((rr, cc))
        comps.append(comp)
    anchors = [(z[0], z[1]) for z in zones if z[3] in ("base", "transport")]
    cands = []
    for i, comp in enumerate(comps):
        cells = tuple(np.array(comp).T)
        if len(comp) < 40:
            continue
        r0, r1, c0, c1 = cells[0].min(), cells[0].max(), cells[1].min(), cells[1].max()
        # The pool, bank and all, must stay clear (one cell of dilation + the pad).
        win = excl[max(0, r0 - 2):r1 + 3, max(0, c0 - 2):c1 + 3]
        wl = label[max(0, r0 - 2):r1 + 3, max(0, c0 - 2):c1 + 3] == i
        if (win & wl).any():
            continue
        if r0 < MARGIN or c0 < MARGIN or r1 > R - 1 - MARGIN or c1 > C - 1 - MARGIN:
            continue
        level = min(float(fill[cells].max()), float(g[cells].min()) + 2.)
        if len(comp) > POOL_MAX_CELLS:
            level = min(level, float(np.sort(g[cells])[POOL_MAX_CELLS - 1]))
        wet = int((g[cells] <= level + .2).sum())
        depth = level - float(g[cells].min())
        if wet < POOL_MIN_CELLS or depth < POOL_MIN_DEPTH:
            continue
        cx, cz = float(X[cells[1]].mean()), float(Z[cells[0]].mean())
        near = min(math.hypot(cx - ax, cz - az) for ax, az in anchors)
        if not POOL_RANGE[0] <= near <= POOL_RANGE[1]:
            continue
        cands.append({"id": i, "cells": wet, "level": level, "depth": depth, "x": cx, "z": cz,
                      "score": min(wet, 900) * min(depth, 3.0) / (1 + near / 700.)})
    cands.sort(key=lambda c: (-c["score"], c["id"]))
    chosen = []
    for c in cands:
        if all(math.hypot(c["x"] - o["x"], c["z"] - o["z"]) >= POOL_SPACING for o in chosen):
            chosen.append(c)
        if len(chosen) == POOLS:
            break
    pool_level = {c["id"]: c["level"] for c in chosen}
    pool_cells = np.zeros(g.shape, bool)
    pool_of = np.full(g.shape, -1)
    pverts, pindices = [], []
    for c in chosen:
        cells = tuple(np.array(comps[c["id"]]).T)
        r0, r1, c0, c1 = cells[0].min(), cells[0].max(), cells[1].min(), cells[1].max()
        for r in range(max(1, r0 - 1), min(R - 1, r1 + 2)):
            for cc in range(max(1, c0 - 1), min(C - 1, c1 + 2)):
                if excl[r, cc]:
                    continue
                lab = label[r - 1:r + 2, cc - 1:cc + 2]
                if not (lab == c["id"]).any() or g[r, cc] > c["level"] + .2:
                    continue
                pool_cells[r, cc] = True
                pool_of[r, cc] = c["id"]
                x, z = X[cc], Z[r]
                base = len(pverts)
                for ox, oz in [(-2.5, -2.5), (2.5, -2.5), (2.5, 2.5), (-2.5, 2.5)]:
                    pverts.append(vertex(x + ox, c["level"], z + oz, (0, 1, 0), (x + ox) / 18, (z + oz) / 18))
                pindices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
    # --- streams -------------------------------------------------------------------
    recv = np.full(g.shape + (2,), -1)
    drop = np.zeros(g.shape)
    for dr, dc in N8:
        sh = np.full(g.shape, np.inf)
        sh[max(0, -dr):R - max(0, dr), max(0, -dc):C - max(0, dc)] = flow[max(0, dr):R + min(0, dr), max(0, dc):C + min(0, dc)]
        gr = (flow - sh) / math.hypot(dr, dc)
        better = gr > drop
        drop[better] = gr[better]
        recv[better] = (dr, dc)
    acc = np.ones(g.shape)
    for i in np.argsort(-flow, axis=None):
        r, c = divmod(int(i), C)
        if drop[r, c] > 0:
            acc[r + recv[r, c, 0], c + recv[r, c, 1]] += acc[r, c]
    channel = acc >= ACC_T
    heads = [(r, c) for r, c in zip(*np.nonzero(channel)) if not any(
        0 <= r - dr < R and 0 <= c - dc < C and channel[r - dr, c - dc] and tuple(recv[r - dr, c - dc]) == (dr, dc)
        and drop[r - dr, c - dc] > 0 for dr, dc in N8)]
    heads.sort(key=lambda p: (-flow[p], p))

    def trace(r, c):
        """Cells downstream of (r, c) until the edge, the exclusion, a chosen pool
        (kind 'pool') or a cell already walked."""
        path = []
        seen = set()
        while True:
            if r < MARGIN or c < MARGIN or r > R - 1 - MARGIN or c > C - 1 - MARGIN or excl_stream[r, c]:
                return path, ("end", None)
            if pool_cells[r, c]:
                return path, ("pool", int(pool_of[r, c]))
            if (r, c) in seen:
                return path, ("loop", None)
            seen.add((r, c))
            path.append((r, c))
            if drop[r, c] < .0004:
                return path, ("flat", None)
            dr, dc = recv[r, c]
            r, c = r + dr, c + dc
            if (r, c) in claimed:
                return path + [(r, c)], ("merge", (r, c))

    claimed = set()
    streams = []
    taken = {c["id"]: 0 for c in chosen}
    for r, c in heads:
        path, (kind, ref) = trace(r, c)
        if kind != "pool" or len(path) < 2 or taken[ref] >= 2:
            continue
        if sum(math.hypot(5 * (b[0] - a[0]), 5 * (b[1] - a[1])) for a, b in zip(path, path[1:])) < MIN_STREAM:
            continue
        taken[ref] += 1
        claimed.update(path)
        streams.append({"cells": path, "pool": ref})
    # Outflow: from each pool's lowest cell downhill to the edge of the dry area.
    for c in chosen:
        cells = [(r, cc) for r, cc in zip(*np.nonzero(pool_of == c["id"]))]
        r, cc = min(cells, key=lambda p: (flow[p], p))
        out = []
        seen = set()
        while True:
            if r < MARGIN or cc < MARGIN or r > R - 1 - MARGIN or cc > C - 1 - MARGIN or excl_stream[r, cc] or (r, cc) in seen:
                break
            seen.add((r, cc))
            if not pool_cells[r, cc]:
                out.append((r, cc))
            elif out:
                break
            if drop[r, cc] < .0004:
                break
            dr, dcc = recv[r, cc]
            r, cc = r + dr, cc + dcc
            if (r, cc) in claimed:
                break
        if len(out) > 1 and sum(math.hypot(5 * (b[0] - a[0]), 5 * (b[1] - a[1])) for a, b in zip(out, out[1:])) >= MIN_STREAM:
            claimed.update(out)
            streams.append({"cells": out, "pool": None})
    # --- geometry --------------------------------------------------------------------
    def height(x, z):
        fr, fc = (z - MIN_Z) / 5., x / 5.
        r0, c0 = int(min(R - 2, max(0, fr))), int(min(C - 2, max(0, fc)))
        a, b = fr - r0, fc - c0
        return float(g[r0, c0] * (1 - a) * (1 - b) + g[r0, c0 + 1] * (1 - a) * b
                     + g[r0 + 1, c0] * a * (1 - b) + g[r0 + 1, c0 + 1] * a * b)

    ribbons = []
    for s in streams:
        pts = np.array([(X[c], Z[r]) for r, c in s["cells"]])
        for _ in range(2):
            if len(pts) > 2:
                pts[1:-1] = (pts[:-2] + pts[1:-1] * 2 + pts[2:]) / 4
        ys, prev = [], math.inf
        for x, z in pts:
            prev = min(prev, height(x, z) + .15)
            ys.append(prev)
        if s["pool"] is not None:
            ys = [max(y, pool_level[s["pool"]] + .02) if i >= len(ys) - 3 else y for i, y in enumerate(ys)]
        half = [min(3.0, 1.3 + .8 * math.sqrt(float(acc[r, c]) / ACC_T)) for r, c in s["cells"]]
        ribbons.append({"pts": pts, "y": ys, "half": half})
    # The cascade: the steepest CASCADE_RUN of any ribbon.
    best = None
    for ri, rb in enumerate(ribbons):
        p, y = rb["pts"], rb["y"]
        for i in range(len(p) - 1):
            d, j = 0.0, i
            while j < len(p) - 1 and d < CASCADE_RUN:
                d += math.hypot(*(p[j + 1] - p[j]))
                j += 1
            if d >= CASCADE_RUN * .8 and (best is None or y[i] - y[j] > best[0]):
                best = (y[i] - y[j], ri, i, j)
    if best is None or best[0] < CASCADE_MIN_DROP:
        raise SystemExit("no stream drop of %.1f m in %d m: the cascade has nowhere to go" % (CASCADE_MIN_DROP, CASCADE_RUN))
    drop_m, cri, ci, cj = best
    meshes = {"pools": (pverts, pindices), "streams": ([], []), "cascade": ([], [])}
    stream_points = []
    for ri, rb in enumerate(ribbons):
        p, y, half = rb["pts"], rb["y"], rb["half"]
        n = len(p)
        spans = [(0, n - 1, "streams")]
        if ri == cri:
            spans = [(0, ci, "streams"), (ci, cj, "cascade"), (cj, n - 1, "streams")]
        length = 0.0
        lengths = [0.0]
        for i in range(1, n):
            lengths.append(lengths[-1] + math.hypot(*(p[i] - p[i - 1])))
        for a, b, which in spans:
            if b - a < 1:
                continue
            verts, indices = meshes[which]
            base = len(verts)
            for i in range(a, b + 1):
                u, w = p[max(0, i - 1)], p[min(n - 1, i + 1)]
                dx, dz = w - u
                ln = math.hypot(dx, dz) or 1
                nx, nz = -dz / ln, dx / ln
                dy = (y[min(n - 1, i + 1)] - y[max(0, i - 1)])
                normal = np.cross((dx, dy, -dz), (nx, 0, -nz))
                normal = normal / (np.linalg.norm(normal) or 1)
                if normal[1] < 0:
                    normal = -normal
                hw = half[i] * (1.25 if which == "cascade" else 1.0)
                for sign, uu in [(-1, 0), (1, 1)]:
                    verts.append(vertex(p[i][0] + nx * hw * sign, y[i], p[i][1] + nz * hw * sign, normal, uu,
                                        lengths[i] / (6 if which == "cascade" else 10)))
                if i > a:
                    k = base + 2 * (i - a)
                    quad(verts, indices, k - 2, k - 1, k + 1, k)
                stream_points.append((float(p[i][0]), float(y[i]), float(p[i][1]), float(hw)))
    # mist at the foot of the fall, a little off the sheet
    foot = ribbons[cri]["pts"][cj]
    cascade = {"x": round(float(foot[0]), 2), "y": round(float(ribbons[cri]["y"][cj]), 2), "z": round(float(foot[1]), 2),
               "drop": round(drop_m, 2),
               "top": [round(float(ribbons[cri]["pts"][ci][0]), 2), round(float(ribbons[cri]["y"][ci]), 2), round(float(ribbons[cri]["pts"][ci][1]), 2)]}
    return {"pools": chosen, "pool_cells": pool_cells, "meshes": meshes, "stream_points": stream_points,
            "streams": len(ribbons), "cascade": cascade, "pool_level": pool_level}


def vertex(x, y, z, normal, u, v):
    return (x - ORIGIN[0], y, -(z - ORIGIN[2]), float(normal[0]), float(normal[1]), float(normal[2]), u, v)


def quad(vs, ix, a, b, c, d):
    # Faces up (+Y) whatever the corner order.
    p = [np.array(vs[i][:3]) for i in (a, b, c)]
    if np.cross(p[1] - p[0], p[2] - p[0])[1] < 0:
        b, d = d, b
    ix.extend([a, b, c, a, c, d])


def write_meshes(m, toolbox):
    sys.path.insert(0, str(toolbox))
    from battlezone.meshes import ogre
    MODELS.mkdir(parents=True, exist_ok=True)
    for key, (verts, indices) in m["meshes"].items():
        assert verts and indices, "no %s geometry" % key
        geo = ogre.Geometry(vertex_count=len(verts), elements=[ogre.VertexElement(0, 2, 1, 0, 0),
                            ogre.VertexElement(0, 2, 4, 12, 0), ogre.VertexElement(0, 1, 7, 24, 0)],
                            buffers={0: ogre.VertexBuffer(0, 32, b"".join(struct.pack("<8f", *v) for v in verts), 0)})
        mesh = ogre.OgreMesh(version="[MeshSerializer_v1.100]", endian="<",
                             submeshes=[ogre.SubMesh(material=MATERIALS[key], uses_shared_vertices=False, indices=indices,
                                                     use32bit=len(verts) > 65535, operation=4, geometry=geo)])
        (MODELS / MESHES[key]).write_bytes(ogre.write_mesh(mesh))


def sites_data(m, shape):
    """The keys spliced into CRStorm18Sites.lua (last in the table, from `watermask`)."""
    j17 = load("build_misn17_jungle", "Build-Misn17Jungle.py")
    mask = j17.water_mask(m["pool_cells"], m["stream_points"], 0, 0, shape)
    pos = [ORIGIN[0], ORIGIN[1], ORIGIN[2]]
    return {
        "watermask": mask,
        "water": {"pools": {"mesh": MESHES["pools"], "position": pos, "material": MATERIALS["pools"]},
                  "streams": {"mesh": MESHES["streams"], "position": pos, "material": MATERIALS["streams"]},
                  "cascade": {"mesh": MESHES["cascade"], "position": pos, "material": MATERIALS["cascade"]},
                  "pools_info": [{"x": round(c["x"]), "z": round(c["z"]), "level": round(c["level"], 2),
                                  "cells": c["cells"]} for c in m["pools"]]},
        "cascade": m["cascade"],
    }


def splice(text, data):
    tail = "".join("," + k + "=" + lua(v) for k, v in data.items())
    i = text.find(",watermask=")
    if i < 0:
        i = text.rindex("}")
    return text[:i] + tail + "}\n"


def compute(stock, toolbox):
    sys.path.insert(0, str(toolbox))
    from battlezone.terrain.hg2 import read_hg2
    _, h = read_hg2(HG2)
    g = h.astype(float) * .1
    zones, fury, points = stock_inputs(stock, toolbox)
    excl = exclusion(g.shape, zones, fury, points)
    m = model(g, excl, zones, exclusion(g.shape, zones, fury, points, STREAM_MARGIN))
    # Belt and braces: not one water cell in an exclusion.
    wet = np.zeros(g.shape, bool)
    wet |= m["pool_cells"]
    for x, _, z, w in m["stream_points"]:
        iz, ix = round((z - MIN_Z) / 5), round(x / 5)
        wet[iz, ix] = True
    assert not (wet & excl).any(), "water inside an exclusion zone"
    data = sites_data(m, g.shape)
    mask = data["watermask"]
    for i, row in enumerate(mask["rows"]):
        for k in range(0, len(row), 2):
            assert not excl[mask["firstRow"] + i, row[k]:row[k] + row[k + 1]].any(), "watermask cell inside an exclusion zone"
    return g, m, data


def update_manifest(extra):
    manifest = json.loads(MANIFEST.read_text())
    manifest.setdefault("outputs", {})
    for p in OUTPUTS + [SITES]:
        manifest["outputs"][p.name] = sha_lua(p) if p.suffix == ".lua" else sha(p)
    manifest["water"] = extra
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", newline="\n")


def sha_lua(path):
    return hashlib.sha256(Path(path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def build(stock, toolbox, write_sites=True):
    g, m, data = compute(stock, toolbox)
    write_meshes(m, toolbox)
    if write_sites:
        text = SITES.read_text(encoding="utf-8")
        SITES.write_text(splice(text, data), encoding="utf-8", newline="\n")
        update_manifest(info(m, data))
    return g, m, data


def info(m, data):
    return {"heightmap": "Missions/misn18.hg2", "heightmapSha256": sha(HG2), "carved": False,
            "pools": len(m["pools"]), "poolCells": int(m["pool_cells"].sum()), "streams": m["streams"],
            "streamPoints": len(m["stream_points"]), "maskCells": data["watermask"]["cells"],
            "cascadeDrop": data["cascade"]["drop"]}


def preview(g, m, stock, toolbox, path):
    from PIL import Image
    zones, fury, points = stock_inputs(stock, toolbox)
    excl = exclusion(g.shape, zones, fury, points)
    gy, gx = np.gradient(g)
    shade = np.clip(128 + 20 * (gx - gy), 0, 255)
    img = np.stack([shade] * 3, -1).astype(np.uint8)
    img[excl] = img[excl] // 2 + (90, 0, 0)
    img[m["pool_cells"]] = (40, 200, 220)
    for x, _, z, w in m["stream_points"]:
        img[round((z - MIN_Z) / 5), round(x / 5)] = (20, 60, 255)
    c = m["cascade"]
    img[round((c["z"] - MIN_Z) / 5) - 2:round((c["z"] - MIN_Z) / 5) + 3, round(c["x"] / 5) - 2:round(c["x"] / 5) + 3] = (255, 255, 0)
    Image.fromarray(img[::-1]).resize((img.shape[1] * 2, img.shape[0] * 2), Image.NEAREST).save(path)


def check():
    manifest = json.loads(MANIFEST.read_text())
    bad = [p.name for p in OUTPUTS if not p.exists() or sha(p) != manifest["outputs"].get(p.name)]
    water = manifest.get("water") or {}
    if water.get("heightmapSha256") != sha(HG2):
        bad.append("Missions/misn18.hg2 (water was modelled on a different heightmap; it must stay uncarved)")
    if "watermask=" not in SITES.read_text(encoding="utf-8"):
        bad.append("CRStorm18Sites.lua watermask")
    if bad:
        raise SystemExit("Misn18 water outputs differ from the manifest: " + ", ".join(bad))
    print("Misn18 water outputs match the manifest.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stock", type=Path)
    ap.add_argument("--toolbox", type=Path, default=ROOT.parent / "Battlezone98_Modding_Toolbox")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview", type=Path, help="with --report: write a top-down review image")
    ap.add_argument("--report", action="store_true", help="compute and print the selection; write nothing")
    a = ap.parse_args()
    if a.check:
        check()
    elif a.stock and a.report:
        g, m, data = compute(a.stock, a.toolbox)
        if a.preview:
            preview(g, m, a.stock, a.toolbox, a.preview)
        print(json.dumps({"info": info(m, data), "pools": data["water"]["pools_info"], "cascade": m["cascade"]}, indent=1))
    elif a.stock:
        g, m, data = build(a.stock, a.toolbox)
        print("Built misn18 water:", info(m, data))
    else:
        ap.error("--stock or --check required")
