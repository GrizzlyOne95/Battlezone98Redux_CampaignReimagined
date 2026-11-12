"""Build `savfury`: the SAV as the Furies infect it (Mission 8 betrayal swap).

Native files are a namespaced copy of stock svsav: the VDF, skeleton and seven GEO
companions change part-name prefixes only (ssv11 -> csf11); the mesh changes only its
material and skeleton resource links. Geometry, UVs, skinning, collision and animation
stay stock. The texture pair is painted offline in the svsav UV layout:

* The stock diffuse luminance is kept (same plates, vents and rivets) and re-coloured
  into dark Fury blue metal; stock lamps and red/yellow markings become cyan.
* Panel seams come from the mesh's own edges: crease edges, boundary edges and UV
  island borders are rasterised in UV space and turned into grooves, bevels, contour
  ribs parallel to the edge, and a cyan glow along part of the seams.
* Veins are ridged noise in an island-local frame (the island's own UV axes scaled
  to its world size), never a world-space projection, and branch out of the seams.

Run `python Tools/Build-SavFury.py`; reads only References/SavFury/original.
"""
from pathlib import Path
import io, re, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh_serializer
from bcdds import save_bc

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'References/SavFury/original'
OUT = ROOT / 'Assets/ModelFixes'
NAME = 'savfury'
SIZE = 1024
CREASE_DEG = 32.0


def namespace(data):
    return re.sub(b'ssv11', b'csf11', data, flags=re.I)


def read_mesh(data):
    return ogremesh_serializer.MeshSerializer(io.BytesIO(data)).read()


def geometry(mesh):
    sub = mesh.submesh_list[0]
    vd = sub.vertex_data
    b0 = np.frombuffer(bytes(vd.get_vertex_buffer(0).buffer), dtype='<f4').reshape(-1, 6)
    b1 = np.frombuffer(bytes(vd.get_vertex_buffer(1).buffer), dtype=np.uint8).reshape(-1, 24)
    uv = b1[:, 4:12].copy().view('<f4').reshape(-1, 2).astype(np.float64)
    pos = b0[:, :3].astype(np.float64)
    tris = np.asarray(sub.get_index_array()).astype(np.int64).reshape(-1, 3)
    return pos, uv, tris


# ---------------------------------------------------------------- mesh topology

def topology(pos, uv, tris):
    """Per-triangle island id, island world/UV scale and the list of UV-space edge
    segments that are creases, boundaries or UV island borders (mesh's own edges)."""
    weld = {}
    wid = np.empty(len(pos), np.int64)
    for i, p in enumerate(np.round(pos, 4)):
        wid[i] = weld.setdefault(tuple(p), len(weld))
    p0, p1, p2 = (pos[tris[:, k]] for k in range(3))
    fn = np.cross(p1 - p0, p2 - p0)
    area3 = np.linalg.norm(fn, axis=1) / 2
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    u0, u1, u2 = (uv[tris[:, k]] for k in range(3))
    areauv = np.abs((u1[:, 0] - u0[:, 0]) * (u2[:, 1] - u0[:, 1]) - (u2[:, 0] - u0[:, 0]) * (u1[:, 1] - u0[:, 1])) / 2

    edges = {}
    for t, tri in enumerate(tris):
        for a, b in ((0, 1), (1, 2), (2, 0)):
            key = tuple(sorted((wid[tri[a]], wid[tri[b]])))
            edges.setdefault(key, []).append((t, a, b))

    # island = triangles connected through edges whose UV endpoints coincide
    parent = list(range(len(tris)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    cos_crease = np.cos(np.radians(CREASE_DEG))
    segs = []  # (uv_a, uv_b, kind) kind 0 crease/boundary, 1 uv border
    for key, users in edges.items():
        if len(users) == 1:
            t, a, b = users[0]
            segs.append((uv[tris[t][a]], uv[tris[t][b]], 0))
            continue
        for i in range(len(users) - 1):
            (t, a, b), (s, c, d) = users[i], users[i + 1]
            if wid[tris[t][a]] == wid[tris[s][c]]:
                ua, ub, uc, ud = uv[tris[t][a]], uv[tris[t][b]], uv[tris[s][c]], uv[tris[s][d]]
            else:
                ua, ub, uc, ud = uv[tris[t][a]], uv[tris[t][b]], uv[tris[s][d]], uv[tris[s][c]]
            same_uv = np.allclose(ua, uc, atol=1e-5) and np.allclose(ub, ud, atol=1e-5)
            if same_uv:
                parent[find(t)] = find(s)
                if float(fn[t] @ fn[s]) < cos_crease:
                    segs.append((ua, ub, 0))
            else:
                segs.append((ua, ub, 1))
                segs.append((uc, ud, 1))
    island = np.array([find(t) for t in range(len(tris))])
    ids = {v: i for i, v in enumerate(sorted(set(island)))}
    island = np.array([ids[v] for v in island])
    n = len(ids)
    a3 = np.bincount(island, area3, n)
    auv = np.bincount(island, areauv, n)
    # island UV units per world unit: sqrt(uv area / world area)
    uv_per_world = np.sqrt(np.maximum(auv, 1e-12) / np.maximum(a3, 1e-12))
    return island, uv_per_world, a3, segs


# ----------------------------------------------------------------- rasteriser

def rasterise(uv, tris, island):
    """Triangle id and island id per texel of the UV atlas (v maps straight to y)."""
    tid = np.full((SIZE, SIZE), -1, np.int64)
    px = uv * SIZE
    for t, tri in enumerate(tris):
        a, b, c = px[tri]
        x0, x1 = int(np.floor(min(a[0], b[0], c[0]))), int(np.ceil(max(a[0], b[0], c[0])))
        y0, y1 = int(np.floor(min(a[1], b[1], c[1]))), int(np.ceil(max(a[1], b[1], c[1])))
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, SIZE - 1), min(y1, SIZE - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / d
        l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / d
        l3 = 1 - l1 - l2
        eps = -0.02
        inside = (l1 >= eps) & (l2 >= eps) & (l3 >= eps)
        sub = tid[y0:y1 + 1, x0:x1 + 1]
        sub[inside] = t
    return tid


def fill_gutters(arr, covered):
    """Bleed covered texel values into the uncovered gutter (nearest texel)."""
    _, (iy, ix) = ndimage.distance_transform_edt(~covered, return_indices=True)
    return arr[iy, ix]


# ----------------------------------------------------------------------- noise

def value_noise(shape_xy, rng_seed, cell):
    """Smooth tileless value noise sampled at float coordinates (arrays x, y)."""
    xs, ys = shape_xy
    rng = np.random.default_rng(rng_seed)
    grid = rng.random((256, 256))
    gx, gy = xs / cell, ys / cell
    ix, iy = np.floor(gx).astype(np.int64), np.floor(gy).astype(np.int64)
    fx, fy = gx - ix, gy - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    g = lambda a, b: grid[(b % 256), (a % 256)]
    top = g(ix, iy) * (1 - sx) + g(ix + 1, iy) * sx
    bot = g(ix, iy + 1) * (1 - sx) + g(ix + 1, iy + 1) * sx
    return top * (1 - sy) + bot * sy


def fbm(xs, ys, seed, base_cell, octaves=4):
    out = np.zeros_like(xs)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * value_noise((xs, ys), seed + o * 17, base_cell / (2 ** o))
        tot += amp
        amp *= .5
    return out / tot


def smoothstep(lo, hi, x):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------- paint

def paint():
    mesh = read_mesh((SRC / 'svsav.mesh').read_bytes())
    pos, uv, tris = geometry(mesh)
    island_of_tri, uv_per_world, island_area, segs = topology(pos, uv, tris)
    tid = rasterise(uv, tris, island_of_tri)
    covered = tid >= 0
    isl = np.where(covered, island_of_tri[np.maximum(tid, 0)], 0)
    isl = fill_gutters(isl, covered)

    # mesh-edge masks in UV space
    mask = {0: Image.new('L', (SIZE, SIZE), 0), 1: Image.new('L', (SIZE, SIZE), 0)}
    dr = {k: ImageDraw.Draw(v) for k, v in mask.items()}
    for a, b, kind in segs:
        dr[kind].line([tuple(a * SIZE), tuple(b * SIZE)], fill=255, width=1)
    crease = np.asarray(mask[0]) > 0
    border = np.asarray(mask[1]) > 0
    edge = crease | border
    dist = ndimage.distance_transform_edt(~edge)
    dist_c = ndimage.distance_transform_edt(~crease)

    stock = np.asarray(Image.open(SRC / 'svsav_D.dds').convert('RGB')).astype(np.float64) / 255
    stock_e = Image.open(SRC / 'svsav_E.dds').convert('RGB').resize((SIZE, SIZE), Image.Resampling.BILINEAR)
    stock_e = np.asarray(stock_e).astype(np.float64) / 255
    lum = stock @ np.array([.30, .59, .11])
    mx, mn = stock.max(2), stock.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    lamp = smoothstep(.35, .6, sat) * smoothstep(.2, .4, mx)         # stock lights and red/yellow markings
    lamp = ndimage.gaussian_filter(lamp, .6)
    emit_stock = np.clip(stock_e.max(2) * 1.6, 0, 1)

    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    # island-local frame: texels converted to world units of the island they sit on,
    # shifted by a per-island offset so neighbouring islands do not share a pattern.
    texel_per_world = uv_per_world[isl] * SIZE
    world_u = xx / texel_per_world + isl * 7.31
    world_v = yy / texel_per_world + isl * 3.77

    # veins: ridged noise; width tuned in world units so small parts stay clean.
    warp = fbm(world_u * .9, world_v * .9, 11, 2.2, 3)
    wu, wv = world_u + (warp - .5) * 1.4, world_v + (warp - .5) * 1.4
    ridge = 1 - np.abs(fbm(wu, wv, 31, 1.6, 4) * 2 - 1)
    ridge2 = 1 - np.abs(fbm(wu * 1.7 + 9, wv * 1.7 - 4, 57, 1.1, 3) * 2 - 1)
    width = .018 / np.maximum(.4, np.minimum(texel_per_world / 40, 2.0))
    main_v = smoothstep(.965 - width, .985, ridge)
    fine_v = smoothstep(.975, .992, ridge2) * .6
    vein = np.clip(main_v + fine_v, 0, 1)
    # branch from seams: strong near edges, a sparse set elsewhere
    near = np.exp(-dist_c / 26.0)
    vein *= (.22 + .78 * near)
    big_island = np.clip(island_area[isl] / .6, .15, 1.0)            # keep tiny parts calm
    vein *= big_island
    flicker = smoothstep(.42, .62, fbm(world_u * .5, world_v * .5, 77, 2.0, 2))
    vein *= .35 + .65 * flicker
    vein = ndimage.gaussian_filter(vein, .55)

    # seams: groove, bevel highlight, contour ribs parallel to the edge
    groove = np.exp(-(dist / 1.1) ** 2)
    bevel = np.exp(-((dist - 3.0) / 1.6) ** 2)
    rib_period = 5.0
    ribs = .5 + .5 * np.cos(dist * 2 * np.pi / rib_period)
    rib_zone = smoothstep(46, 10, dist) * (dist > 2.5)
    rib_zone *= np.clip(texel_per_world / 60, .0, 1.0)

    # glow along part of the creases (broken runs, not every seam)
    seam_run = smoothstep(.5, .66, fbm(world_u * .35 + 5, world_v * .35, 91, 1.4, 2))
    seam_glow = np.exp(-(dist_c / 0.95) ** 2) * seam_run * big_island ** 1.5

    # ---- diffuse: dark Fury blue metal
    L = np.clip(lum, 0, 1)
    dark = np.array([.012, .024, .048])
    mid = np.array([.045, .085, .140])
    light = np.array([.20, .30, .42])
    t = (L ** 1.25)[..., None]
    base = np.where(t < .35, dark + (mid - dark) * (t / .35), mid + (light - mid) * ((t - .35) / .65))
    base *= (1 - .10 * rib_zone * ribs)[..., None]                 # ribbed metal near edges
    base *= (1 - .55 * groove)[..., None]
    base += (.35 * bevel[..., None] * np.array([.12, .20, .30]))
    cyan = np.array([.04, .62, .82])
    base = base * (1 - lamp[..., None]) + np.array([.02, .10, .14]) * lamp[..., None]
    base = base + cyan * (.55 * vein[..., None]) + cyan * (.45 * seam_glow[..., None])
    base = np.clip(base, 0, 1)

    # ---- emissive: veins, glowing seams, stock lamps recoloured cyan
    glow = np.array([.10, .88, 1.0])
    e = np.clip(.75 * vein + .6 * seam_glow + .6 * np.maximum(emit_stock, lamp * .5), 0, 1)
    emis = e[..., None] * glow * (.75 + .25 * L[..., None])

    # gutters bleed so mips and filtering do not pull in black
    base = np.stack([fill_gutters(base[..., c], covered) for c in range(3)], -1)
    emis = np.stack([fill_gutters(emis[..., c], covered) for c in range(3)], -1)
    return (Image.fromarray((base * 255 + .5).astype(np.uint8), 'RGB'),
            Image.fromarray((emis * 255 + .5).astype(np.uint8), 'RGB'),
            dict(texels=int(covered.sum()), islands=int(isl.max() + 1), segs=len(segs)))


def build(textures=True):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f'{NAME}.vdf').write_bytes(namespace((SRC / 'svsav.vdf').read_bytes()))
    (OUT / f'{NAME}.skeleton').write_bytes(namespace((SRC / 'svsav.skeleton').read_bytes()))
    for p in sorted(SRC.glob('ssv11*.geo')):
        (OUT / ('csf11' + p.name[5:])).write_bytes(namespace(p.read_bytes()))
    mesh = read_mesh((SRC / 'svsav.mesh').read_bytes())
    for sub in mesh.submesh_list:
        sub.material_name = NAME
    mesh.skeleton_name = f'{NAME}.skeleton'
    out = io.BytesIO()
    ogremesh_serializer.MeshSerializer(out).write(mesh)
    (OUT / f'{NAME}.mesh').write_bytes(out.getvalue())
    if textures:
        diffuse, emissive, info = paint()
        diffuse.save(ROOT / 'References/SavFury/savfury-diffuse.png')
        emissive.save(ROOT / 'References/SavFury/savfury-emission.png')
        save_bc(diffuse.convert('RGBA'), ROOT / 'Assets/Textures/savfury_d.dds')
        save_bc(emissive.convert('RGBA'), ROOT / 'Assets/Textures/savfury_e.dds')
        print('painted', info)
    print('Built savfury VDF/mesh/skeleton + 7 GEO companions; BC1 mipped diffuse/emission.')


if __name__ == '__main__':
    build()
