#!/usr/bin/env python3
"""Build CR's six destruction-chunklet variations (chunk1..chunk6).

The engine reads chunk.odf ([ChunkEffect] chunkletCount / chunkletGeomN) and picks one
chunklet GEO at random per piece; OpenShim draws the matching payload mesh
chunkMeshes/<geo>/<geo>.mesh instead of the bare GEO. This writes, from one set of
vertices per shape:

  Assets/ModelFixes/chunk1..6.geo      (GeoSerializer; the engine's chunklet geometry)
  chunkMeshes/chunkN/chunkN.mesh       (static_mesh_bytes; ogre v1.100, with tangents)

All binary formats go through the shared libraries (Tools/bzmodellibs.py); nothing is
hand-packed. The meshes use cr_chunklet_interior (chunkMeshes/cr_chunklet.material), CR's own copy of
OpenShim's burnt-machinery fracture-interior art: chunkMeshes/cr_chunklet_interior_{d,n,s,e}.dds
are byte copies of OpenShim's openshim_fracture_interior*.dds (src/patches/fracture_interior_textures.rc),
renamed so they cannot clash. They must live here, not be referenced from OpenShim's cache: the
mod folder's chunkMeshes loads into the mod's own resource group, which cannot see materials that
OpenShim defines in its OpenShimChunkPayloads group. The map (shipped at 256 px, downsampled from OpenShim's 512 px set) tiles seamlessly, so every
polygon gets its own frame (u along its longest edge, v = n x u, a random tile offset) at TILE_M
metres per tile: relief follows the mesh's own faces, never a world projection.

Run:  python Tools/Assets/Build-ChunkVariations.py [--textures-from <dir with OpenShim's 512 px openshim_fracture_interior*.dds>]
The committed maps are 256 px (the chunks are small); --textures-from regenerates them.
Needs numpy, scipy, PIL (Pillow) and the sibling toolkit checkout. The four DDS files are committed inputs.
"""
from __future__ import annotations

import io
import math
import sys
from pathlib import Path

import numpy as np
from scipy.spatial import ConvexHull

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "Tools"))
from bcdds import save_bc  # noqa: E402
from bzmodellibs import geo as geomod, geo_serializer  # noqa: E402
from bzstaticmodel import static_mesh_bytes  # noqa: E402

MATERIAL = "cr_chunklet_interior"
TEX = "cr_chunklet_interior"
TILE_M = 0.6  # metres of surface per 256 px texture tile (about 430 px/m)

# Stock chunk1/chunk2 GEO bounding boxes (metres) are 0.12x0.20x0.08 and 0.17x0.23x0.18, so the stock
# mean longest side is ~0.215 m. Each shape is uniformly scaled so its longest bounding-box side hits
# its target here (variety kept, mean on stock). UVs use metres/TILE_M, so texel density is unchanged.
TARGET_LONGEST_M = [0.20, 0.23, 0.25, 0.21, 0.18, 0.22]  # chunk1..6, mean 0.215
STOCK_LONGEST_M = (0.20, 0.23)  # fallback when the stock GEOs are not on disk
STOCK_MEAN_TOL_M = (0.20, 0.23)
CHUNK_BOUNDS_M = (0.16, 0.28)
STOCK_GEO_DIR = ROOT.parent / "Battlezone_Source" / "BZ1" / "1.5" / "Battlezone_Install" / "stock"


# ---------------------------------------------------------------- geometry
def _orient(tri, centre):
    a, b, c = (np.asarray(p, float) for p in tri)
    n = np.cross(b - a, c - a)
    if np.dot(n, (a + b + c) / 3 - centre) < 0:
        return (tri[0], tri[2], tri[1])
    return tri


def hull(points, nskin=2):
    """Closed convex part: triangles (outward, CCW) tagged skin (largest planes) or torn."""
    pts = np.asarray(points, float)
    h = ConvexHull(pts)
    centre = pts.mean(0)
    tris = [_orient(tuple(tuple(pts[i]) for i in s), centre) for s in h.simplices]
    groups = {}
    for tri in tris:
        a, b, c = (np.asarray(p) for p in tri)
        n = np.cross(b - a, c - a)
        n /= np.linalg.norm(n)
        key = (tuple(np.round(n, 3)), round(float(np.dot(n, a)), 3))
        groups.setdefault(key, []).append(tri)
    polys = []
    for gtris in groups.values():
        area = sum(0.5 * np.linalg.norm(np.cross(np.subtract(t[1], t[0]), np.subtract(t[2], t[0]))) for t in gtris)
        polys.append([area, gtris])
    polys.sort(key=lambda p: -p[0])
    return [(p[1], "skin" if i < nskin else "torn") for i, p in enumerate(polys)]


def loft(rings, cap_jitter=None):
    """Closed lofted strut: `rings` are equal-size loops (outward CCW looking down +x)."""
    polys = []
    n = len(rings[0])
    for r in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            a, b = rings[r][i], rings[r][j]
            c, d = rings[r + 1][j], rings[r + 1][i]
            polys.append(([(a, b, c)], "skin"))
            polys.append(([(a, c, d)], "skin"))
    for ring, flip, mid in ((rings[0], True, None), (rings[-1], False, None)):
        centre = tuple(np.mean(ring, 0) + (cap_jitter if (cap_jitter is not None and not flip) else 0))
        tris = []
        for i in range(n):
            j = (i + 1) % n
            tri = (ring[i], ring[j], centre) if not flip else (ring[j], ring[i], centre)
            tris.append(tri)
        polys.append((tris, "torn"))
    return polys


def rot_x(points, deg, about=(0, 0, 0)):
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    o = np.asarray(about, float)
    return [tuple(o + np.array([p[0] - o[0], c * (p[1] - o[1]) - s * (p[2] - o[2]), s * (p[1] - o[1]) + c * (p[2] - o[2])])) for p in points]


def rot_z(points, deg):
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    return [(c * x - s * y, s * x + c * y, z) for x, y, z in points]


def box(x0, x1, y0, y1, z0, z1, jitter=None):
    pts = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    if jitter is not None:
        pts = [tuple(np.array(p) + jitter[i]) for i, p in enumerate(pts)]
    return pts


def shape_shard():
    """Long tapering blade with a bent fin: a sheared shard."""
    blade = [(-0.30, -0.10, -0.028), (-0.30, 0.10, -0.022), (-0.30, 0.09, 0.03), (-0.30, -0.08, 0.026),
             (0.02, -0.15, -0.02), (0.02, 0.12, -0.02), (0.02, 0.10, 0.025), (0.02, -0.12, 0.024),
             (0.40, 0.03, 0.0), (0.36, 0.06, 0.012)]
    fin = rot_x([(-0.18, -0.02, -0.01), (-0.18, 0.12, -0.01), (-0.18, 0.12, 0.02), (-0.18, -0.02, 0.02),
                 (0.16, 0.0, -0.01), (0.20, 0.07, 0.0), (0.20, 0.07, 0.02), (0.16, 0.0, 0.02)], 38, (0, 0, 0))
    return hull(blade, 2) + hull(fin, 1)


def shape_bent_plate():
    """Plate folded along a hinge: two slabs, the far one bent down 38 degrees."""
    a = [(-0.26, -0.20, 0.0), (0.26, -0.20, 0.0), (0.26, 0.10, 0.0), (0.10, 0.20, 0.0), (-0.26, 0.17, 0.0),
         (-0.26, -0.20, 0.04), (0.26, -0.20, 0.04), (0.26, 0.10, 0.04), (0.10, 0.20, 0.04), (-0.26, 0.17, 0.04)]
    hinge_y = -0.20
    b0 = [(-0.24, 0.0, 0.0), (0.24, 0.0, 0.0), (0.20, 0.24, 0.0), (-0.20, 0.20, 0.0),
          (-0.24, 0.0, 0.04), (0.24, 0.0, 0.04), (0.20, 0.24, 0.04), (-0.20, 0.20, 0.04)]
    b = rot_x([(x, y - 0.02, z) for x, y, z in b0], -38, (0, 0, 0))
    b = [(x, y + hinge_y - 0.02, z) for x, y, z in b]
    b = [(x, y, z - 0.0) for x, y, z in b]
    # mirror the bent flap in front of the hinge so the fold reads as a bend, not a tab
    b = [(x, -(y - hinge_y) + hinge_y, z) for x, y, z in b]
    return hull(a, 2) + hull(b, 2)


def shape_strut():
    """Twisted, bent strut: a square-tube ring loft with a torn end."""
    rings = []
    seg = 4
    for i in range(seg + 1):
        t = i / seg
        x = -0.34 + 0.70 * t
        twist = math.radians(80 * t * t)
        w = 0.055 - 0.012 * t
        h = 0.040 + 0.010 * t
        sy = 0.07 * math.sin(math.pi * t * 0.9)
        sz = 0.03 * t * t
        ring = []
        for (cy, cz) in ((-w, -h), (w, -h), (w, h), (-w, h)):
            y = cy * math.cos(twist) - cz * math.sin(twist)
            z = cy * math.sin(twist) + cz * math.cos(twist)
            ring.append((x, y + sy, z + sz))
        rings.append(ring)
    rings[-1] = [(x + dx, y, z) for (x, y, z), dx in zip(rings[-1], (0.03, -0.04, 0.05, -0.02))]
    # outward CCW looking down +x requires this ring order
    rings = [list(reversed(r)) for r in rings]
    flange = rot_x([(-0.34, -0.09, -0.012), (-0.34, 0.09, -0.012), (-0.34, 0.09, 0.012), (-0.34, -0.09, 0.012),
                    (-0.28, -0.09, -0.012), (-0.28, 0.09, -0.012), (-0.28, 0.09, 0.012), (-0.28, -0.09, 0.012)], 0)
    return loft(rings, cap_jitter=np.array([0.02, 0.0, 0.0])) + hull(flange, 2)


def shape_panel():
    """Broken panel: warped irregular slab with a snapped stiffener rib."""
    outline = [(-0.30, -0.18), (0.05, -0.24), (0.30, -0.10), (0.26, 0.14), (0.02, 0.22), (-0.28, 0.12)]
    top = [(x, y, 0.016 + 0.018 * (x + y)) for x, y in outline]
    bot = [(x * 0.97, y * 0.97, -0.016 + 0.014 * (x - y)) for x, y in outline]
    rib = [(-0.20, -0.02, -0.050), (0.24, -0.04, -0.050), (0.24, 0.02, -0.050), (-0.20, 0.03, -0.050),
           (-0.20, -0.02, -0.008), (0.24, -0.04, -0.012), (0.24, 0.02, -0.012), (-0.20, 0.03, -0.008)]
    return hull(top + bot, 2) + hull(rib, 2)


def shape_lump():
    """Chunky rock-metal lump: two jittered ellipsoid hulls fused together."""
    rng = np.random.default_rng(7)
    pts = []
    for p in _sphere_dirs(14):
        r = 1.0 + 0.22 * rng.uniform(-1, 1)
        pts.append((p[0] * 0.20 * r, p[1] * 0.15 * r, p[2] * 0.14 * r))
    small = []
    for p in _sphere_dirs(9):
        r = 1.0 + 0.2 * rng.uniform(-1, 1)
        small.append((0.13 + p[0] * 0.10 * r, 0.06 + p[1] * 0.09 * r, -0.04 + p[2] * 0.08 * r))
    return hull(pts, 0) + hull(small, 0)


def _sphere_dirs(n):
    out = []
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n
        r = math.sqrt(1 - y * y)
        out.append((math.cos(ga * i) * r, y, math.sin(ga * i) * r))
    return out


def shape_girder():
    """Girder end: I-beam (two flanges + web) bent, with a jagged torn end."""
    L0, L1 = -0.30, 0.30
    j = [0.0, 0.05, -0.03, 0.04, 0.0, 0.06, -0.02, 0.03]  # torn-end flange stagger
    top = box(L0, L1, 0.06, 0.09, -0.06, 0.06)
    bot = box(L0, L1, -0.09, -0.06, -0.06, 0.06)
    web = box(L0 + 0.02, L1 - 0.03, -0.075, 0.075, -0.010, 0.010)
    top = [(x - (0.0 if x < 0 else abs(j[(k * 3) % 8])), y, z) for k, (x, y, z) in enumerate(top)]
    bot = [(x - (0.0 if x < 0 else abs(j[(k * 5 + 1) % 8]) * 1.6), y, z) for k, (x, y, z) in enumerate(bot)]
    top = [(x, y, z + (0.02 if x > 0.2 and z > 0 else 0)) for x, y, z in top]
    parts = [top, bot, web]
    bent = []
    for part in parts:
        bent.append([(x, y + 0.9 * max(0.0, x - 0.0) ** 2, z) for x, y, z in part])
    return hull(bent[0], 3) + hull(bent[1], 3) + hull(bent[2], 2)


SHAPES = [shape_shard, shape_bent_plate, shape_strut, shape_panel, shape_lump, shape_girder]


# ---------------------------------------------------------------- UV + mesh rows
def build_mesh(polys, seed, target_longest):
    """Centre the shape, give each polygon its own frame and atlas patch.

    Returns (rows, indices, tangents flag data): per-triangle unwelded vertices with flat
    normals; also the welded GEO arrays.
    """
    allp = np.array([p for tris, _ in polys for t in tris for p in t], float)
    centre = (allp.min(0) + allp.max(0)) / 2
    scale = target_longest / float((allp.max(0) - allp.min(0)).max())
    rng = np.random.default_rng(seed)
    rows, indices = [], []
    for tris, kind in polys:
        tris = [tuple(tuple((np.asarray(p, float) - centre) * scale) for p in t) for t in tris]
        # polygon frame: normal from the largest triangle, u along its longest edge
        best = max(tris, key=lambda t: np.linalg.norm(np.cross(np.subtract(t[1], t[0]), np.subtract(t[2], t[0]))))
        a, b, c = (np.asarray(p) for p in best)
        n = np.cross(b - a, c - a)
        n /= np.linalg.norm(n)
        edges = [(b - a), (c - b), (a - c)]
        e = max(edges, key=np.linalg.norm)
        t_axis = e - n * np.dot(e, n)
        t_axis /= np.linalg.norm(t_axis)
        b_axis = np.cross(n, t_axis)
        pts2 = [(np.dot(np.asarray(p), t_axis), np.dot(np.asarray(p), b_axis)) for tri in tris for p in tri]
        umin = min(p[0] for p in pts2); umax = max(p[0] for p in pts2)
        vmin = min(p[1] for p in pts2); vmax = max(p[1] for p in pts2)
        ou, ov = rng.uniform(0, 1, 2)
        for tri in tris:
            base = len(rows)
            for p in tri:
                p = np.asarray(p)
                u = ou + (np.dot(p, t_axis) - umin) / TILE_M
                v = ov + (np.dot(p, b_axis) - vmin) / TILE_M
                rows.append((*p, *n, u, v, *t_axis))
            indices.extend([base, base + 1, base + 2])
    return rows, indices


def welded_geo(name, rows, indices):
    """GEO: positions mirrored in x (toolkit mesh<->GEO convention), welded, with plane data."""
    pos, remap, vn_acc = [], {}, []
    pos_arr = np.array([r[:3] for r in rows])
    nrm_arr = np.array([r[3:6] for r in rows])
    for i, p in enumerate(pos_arr):
        key = tuple(np.round(p, 5))
        if key not in remap:
            remap[key] = len(pos)
            pos.append(p)
            vn_acc.append(np.zeros(3))
        vn_acc[remap[key]] += nrm_arr[i]
    vmap = [remap[tuple(np.round(p, 5))] for p in pos_arr]
    geo = geomod.Geo()
    geo.name = name.upper()
    geo.vert_count = len(pos)
    geo.flags = 0
    gp = np.array([(-p[0], p[1], p[2]) for p in pos], dtype="<f4")
    vn = []
    for acc in vn_acc:
        nv = acc / (np.linalg.norm(acc) or 1.0)
        vn.append((nv[0], -nv[1], -nv[2]))
    geo.vertex_pos_buffer = gp
    geo.vertex_normal_buffer = np.array(vn, dtype="<f4")
    tri_ids = [(indices[i], indices[i + 1], indices[i + 2]) for i in range(0, len(indices), 3)]
    order = list(range(len(tri_ids)))
    for k, ti in enumerate(order):
        a, b, c = (vmap[x] for x in tri_ids[ti])
        face = geo.create_face(k)
        face.color.r, face.color.g, face.color.b = 65, 68, 68
        pa, pb, pc = (gp[x].astype(float) for x in (a, b, c))
        nrm = np.cross(pb - pa, pc - pa)
        area = np.linalg.norm(nrm) / 2
        nrm = nrm / (np.linalg.norm(nrm) or 1.0)
        face.plane.surface_normal.x, face.plane.surface_normal.y, face.plane.surface_normal.z = (float(q) for q in nrm)
        face.plane.distance = float(-np.dot(nrm, pa))
        face.poly_area = 0.0
        face.shade_type, face.texture_type, face.xluscent_type = 5, 1, 0
        face.texture_name = ""
        face.parent_face_index = k - 1
        face.tree_branch = 1
        for (vi, ri) in zip((a, b, c), tri_ids[ti]):
            face.create_face_node(vertex_index=int(vi), vertex_normal_index=int(vi),
                                  uv=geomod.UV(float(rows[ri][6]), float(rows[ri][7])))
    return geo


# ---------------------------------------------------------------- main
MATERIAL_TEXT = """// Shared material for CR's destruction chunklet meshes (chunkN/chunkN.mesh).
// Mirrors OpenShim's openshim_fracture_interior (burnt machinery, ember cracks) under CR-unique
// names. Inherits the stock BZBase, as OpenShim's own payload materials do, never a CR-only base.
import * from "BZBase.material"

material {mat} : BZBase
{{
	set_texture_alias DiffuseMap {tex}_d.dds
	set_texture_alias NormalMap {tex}_n.dds
	set_texture_alias SpecularMap {tex}_s.dds
	set_texture_alias EmissiveMap {tex}_e.dds

	set $diffuse "1 1 1"
	set $ambient "1 1 1"
	set $specular "0.30 0.28 0.26"
	set $shininess "40"
	set $bias "0"
}}
"""


def downsample_textures(src_dir, out_chunks):
    """256x256 BC1 + full mips from OpenShim's 512 px openshim_fracture_interior{,_n,_s,_e}.dds."""
    from PIL import Image
    for suffix, src in (("d", ""), ("n", "_n"), ("s", "_s"), ("e", "_e")):
        im = Image.open(Path(src_dir) / f"openshim_fracture_interior{src}.dds").convert("RGBA")
        im = im.resize((256, 256), Image.LANCZOS)
        if suffix == "n":
            a = np.asarray(im, float)[..., :3] / 255 * 2 - 1
            a /= np.maximum(np.linalg.norm(a, axis=2, keepdims=True), 1e-6)
            rgb = ((a * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)
            im = Image.fromarray(np.dstack([rgb, np.full((256, 256), 255, np.uint8)]), "RGBA")
        save_bc(im, out_chunks / f"{TEX}_{suffix}.dds")


def _geo_longest(src):
    with open(src, "rb") as f:
        g = geo_serializer.GeoSerializer(f).read()
    p = np.asarray(g.vertex_pos_buffer.tolist(), dtype=float)
    return float((p.max(0) - p.min(0)).max())


def assert_stock_scale(longest):
    """Fail if the six chunklets drift from stock size (mean and per-chunk bounds)."""
    stock = list(STOCK_LONGEST_M)
    geos = [STOCK_GEO_DIR / "chunk1.geo", STOCK_GEO_DIR / "chunk2.geo"]
    if all(g.is_file() for g in geos):
        stock = [_geo_longest(g) for g in geos]
    stock_mean = sum(stock) / len(stock)
    mean = sum(longest) / len(longest)
    lo, hi = CHUNK_BOUNDS_M
    tlo, thi = STOCK_MEAN_TOL_M
    problems = []
    if not (tlo <= mean <= thi) or abs(mean - stock_mean) > 0.015:
        problems.append(f"mean longest {mean:.3f} m vs stock {stock_mean:.3f} m (allowed {tlo}-{thi})")
    for i, v in enumerate(longest, start=1):
        if not lo <= v <= hi:
            problems.append(f"chunk{i} longest {v:.3f} m outside {lo}-{hi}")
    if problems:
        raise SystemExit("chunklet size regression: " + "; ".join(problems))
    print(f"size check ok: mean longest {mean:.3f} m (stock {stock_mean:.3f})")


def main():
    out_models = ROOT / "Assets" / "ModelFixes"
    out_chunks = ROOT / "chunkMeshes"
    out_chunks.mkdir(exist_ok=True)
    if "--textures-from" in sys.argv:
        i = sys.argv.index("--textures-from")
        if i + 1 >= len(sys.argv):
            raise SystemExit("--textures-from needs a directory")
        downsample_textures(sys.argv[i + 1], out_chunks)
    for suffix in "dnse":
        if not (out_chunks / f"{TEX}_{suffix}.dds").is_file():
            raise SystemExit(f"missing {TEX}_{suffix}.dds (copy OpenShim's fracture-interior DDS set)")
    (out_chunks / "cr_chunklet.material").write_text(MATERIAL_TEXT.format(mat=MATERIAL, tex=TEX), newline="\r\n")
    longest = []
    for idx, fn in enumerate(SHAPES, start=1):
        polys = fn()
        rows, indices = build_mesh(polys, seed=100 + idx, target_longest=TARGET_LONGEST_M[idx - 1])
        name = f"chunk{idx}"
        mesh = static_mesh_bytes(MATERIAL, rows, indices, tangents=True)
        (out_chunks / name).mkdir(exist_ok=True)
        (out_chunks / name / f"{name}.mesh").write_bytes(mesh)
        geo = welded_geo(name, rows, indices)
        buf = io.BytesIO()
        geo_serializer.GeoSerializer(buf).write(geo)
        (out_models / f"{name}.geo").write_bytes(buf.getvalue())
        pts = np.array([r[:3] for r in rows])
        ext = pts.max(0) - pts.min(0)
        longest.append(float(ext.max()))
        print(name, "tris", len(indices) // 3, "geo verts", geo.vert_count, "extent m", [round(float(e), 2) for e in ext])
    assert_stock_scale(longest)


if __name__ == "__main__":
    main()
