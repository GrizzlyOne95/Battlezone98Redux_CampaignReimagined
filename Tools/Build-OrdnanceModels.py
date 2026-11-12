"""Modular projectile kit for CR: twelve meshes sharing one atlas (crord_d/crord_e) and one material.

Every byte of each .mesh is written by BZ98RBlenderToolKit's serializer through
``bzstaticmodel.static_mesh_bytes``. Hulls are single revolved profiles (nose,
body, band, nozzle pieces concatenated, so the coaxial parts are truly unioned);
glow parts are profile segments with their own UV island. Fins and canards are
closed hexahedra whose roots are sunk into the hull. Panel lines in the atlas sit
on the borders of each UV island, i.e. on the mesh's own edge rings and fin edges.

The engine flies ordnance along +Z, so every mesh is built with its nose at +Z.
Deterministic: no clocks, a fixed-seed noise source. Needs numpy, PIL and texconv.
"""
from pathlib import Path
import json, math, sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Tools'))
from bzstaticmodel import static_mesh_bytes
from bcdds import save_bc

MESH_DIR = ROOT / 'Assets/ModelFixes'
TEX_DIR = ROOT / 'Assets/Textures'
ATLAS = 512
SEG = 12          # sides of every revolved hull
MATERIAL = 'crord'

# Atlas islands (x0, y0, x1, y1) in pixels. Content is inset by PAD; the pad is border colour.
REGIONS = {
    'olive': (0, 0, 256, 128), 'gun': (256, 0, 512, 128),
    'copper': (0, 128, 256, 192), 'warn': (256, 128, 512, 192),
    'finf': (0, 192, 128, 320), 'fine': (128, 192, 192, 256),
    'orange': (192, 192, 352, 256), 'green': (352, 192, 512, 256),
    'blue': (128, 256, 320, 320), 'seekero': (320, 256, 512, 320),
    'finf2': (0, 320, 128, 448),
}
PAD = 4


def uv_rect(role):
    x0, y0, x1, y1 = REGIONS[role]
    return ((x0 + PAD) / ATLAS, (y0 + PAD) / ATLAS, (x1 - PAD) / ATLAS, (y1 - PAD) / ATLAS)


# ---------------------------------------------------------------- hull profiles
# A profile is a list of (role, [(z, r), ...]) running tail to nose; consecutive
# segments share their end/start point. r == 0 marks a pole.
def smooth(a, b, n):
    return [a + (b - a) * (0.5 - 0.5 * math.cos(math.pi * i / n)) for i in range(n + 1)]


def nose_ogive(z0, length, r, role='gun', n=5, power=1.6):
    pts = [(z0 + length * i / n, r * (1 - (i / n) ** power) ** 0.62) for i in range(n + 1)]
    pts[-1] = (pts[-1][0], 0.0)
    return [(role, pts)]


def nose_cone(z0, length, r, role='gun', tip=0.0):
    return [(role, [(z0, r), (z0 + length, tip)])] + ([] if tip == 0 else [('gun', [(z0 + length, tip), (z0 + length, 0.0)])])


def nose_dome(z0, length, r, role='seekero', n=4):
    pts = [(z0 + length * math.sin(math.pi / 2 * i / n), r * math.cos(math.pi / 2 * i / n)) for i in range(n + 1)]
    pts[-1] = (pts[-1][0], 0.0)
    return [(role, pts)]


def nose_needle(z0, length, r, role='gun'):
    return [(role, [(z0, r), (z0 + length * 0.35, r * 0.62), (z0 + length, 0.0)])]


def body_cyl(z0, z1, r, role='olive'):
    return [(role, [(z0, r), (z1, r)])]


def body_barrel(z0, z1, r, role='olive', bulge=0.0, n=4):
    pts = [(z0 + (z1 - z0) * i / n, r + bulge * math.sin(math.pi * i / n)) for i in range(n + 1)]
    return [(role, pts)]


def taper(z0, z1, r0, r1, role='olive'):
    return [(role, [(z0, r0), (z1, r1)])]


def band(z0, z1, r, delta, role):
    """Raised (delta>0) or recessed (delta<0) ring on a cylinder of radius r."""
    return [(role, [(z0, r), (z0, r + delta)]), (role, [(z0, r + delta), (z1, r + delta)]),
            (role, [(z1, r + delta), (z1, r)])]


def base_cap(z, r, role='gun'):
    return [(role, [(z, 0.0), (z, r)])]


def tail_closed(z, r, r_noz, depth, role='orange'):
    """Flat tail ring from r down to the nozzle rim, then the glowing cone recess."""
    return [(role, [(z + depth, 0.0), (z, r_noz)]), ('gun', [(z, r_noz), (z, r)])]


def radius_at(profile, z):
    """Hull radius at z (the largest crossing, so fins sit inside every part there)."""
    best = 0.0
    for _, pts in profile:
        for (za, ra), (zb, rb) in zip(pts, pts[1:]):
            lo, hi = min(za, zb), max(za, zb)
            if lo - 1e-9 <= z <= hi + 1e-9 and hi > lo:
                best = max(best, ra + (rb - ra) * (z - za) / (zb - za))
    return best


def revolve(profile, tris, rows):
    """Append the lathe of `profile` (flat triangles with smooth in-segment normals)."""
    for role, pts in profile:
        u0, v0, u1, v1 = uv_rect(role)
        arc = [0.0]
        for (za, ra), (zb, rb) in zip(pts, pts[1:]):
            arc.append(arc[-1] + math.hypot(zb - za, rb - ra))
        total = arc[-1] or 1.0
        # per-point (nz, nr) from the averaged adjacent tangents, hard at segment ends
        norm = []
        for i, (z, r) in enumerate(pts):
            ts = []
            if i > 0:
                ts.append((z - pts[i - 1][0], r - pts[i - 1][1]))
            if i < len(pts) - 1:
                ts.append((pts[i + 1][0] - z, pts[i + 1][1] - r))
            tz = sum(t[0] / math.hypot(*t) for t in ts)
            tr = sum(t[1] / math.hypot(*t) for t in ts)
            length = math.hypot(tz, tr)
            norm.append((-tr / length, tz / length))
        ring = []
        for (z, r), (nz, nr), a in zip(pts, norm, arc):
            v = v0 + (v1 - v0) * (a / total)
            row = []
            for i in range(SEG + 1):
                phi = 2 * math.pi * i / SEG
                c, s = math.cos(phi), math.sin(phi)
                row.append([r * c, r * s, z, nr * c, nr * s, nz, u0 + (u1 - u0) * i / SEG, v])
            ring.append(row)
        for j in range(len(pts) - 1):
            lo_pole, hi_pole = pts[j][1] == 0, pts[j + 1][1] == 0
            for i in range(SEG):
                a, b, c, d = ring[j][i], ring[j][i + 1], ring[j + 1][i + 1], ring[j + 1][i]
                if lo_pole:
                    tris.append((a, c, d))
                elif hi_pole:
                    tris.append((a, b, c))
                else:
                    tris.append((a, b, c))
                    tris.append((a, c, d))


# ---------------------------------------------------------------- fins
def fin(tris, angle_deg, z_root0, z_root1, z_tip0, z_tip1, rho_in, rho_out, thick, role='finf'):
    """Closed hexahedron: polygon (z, rho) extruded +-thick/2 tangentially, sunk root at rho_in."""
    th = math.radians(angle_deg)
    rad = np.array([math.cos(th), math.sin(th), 0.0])
    tan = np.array([-math.sin(th), math.cos(th), 0.0])
    poly = [(z_root0, rho_in), (z_root1, rho_in), (z_tip1, rho_out), (z_tip0, rho_out)]

    def point(p, side):
        return np.array([0, 0, p[0]]) + rad * p[1] + tan * (side * thick / 2)
    pos = {(i, s): point(p, s) for i, p in enumerate(poly) for s in (-1, 1)}
    center = sum(pos.values()) / len(pos)
    zs = [p[0] for p in poly]
    rs = [p[1] for p in poly]
    fu0, fv0, fu1, fv1 = uv_rect(role)
    eu0, ev0, eu1, ev1 = uv_rect('fine')

    def uv_main(i, side):
        u = (poly[i][0] - min(zs)) / (max(zs) - min(zs))
        v = 1 - (poly[i][1] - min(rs)) / (max(rs) - min(rs))
        if side < 0:
            u = 1 - u
        return (fu0 + (fu1 - fu0) * u, fv0 + (fv1 - fv0) * v)

    def emit(ids, uvs):
        pts = [pos[k] for k in ids]
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        n /= np.linalg.norm(n)
        if np.dot(n, sum(pts) / len(pts) - center) < 0:
            ids, uvs, pts = ids[::-1], uvs[::-1], pts[::-1]
            n = -n
        rows = [[*p, *n, *uv] for p, uv in zip(pts, uvs)]
        tris.append((rows[0], rows[1], rows[2]))
        tris.append((rows[0], rows[2], rows[3]))
    for side in (-1, 1):
        emit([(i, side) for i in range(4)], [uv_main(i, side) for i in range(4)])
    edge_uv = [(eu0, ev0), (eu1, ev0), (eu1, ev1), (eu0, ev1)]
    for i in range(4):
        j = (i + 1) % 4
        emit([(i, -1), (j, -1), (j, 1), (i, 1)], edge_uv)


def fin_set(tris, profile, count, phase, z_a, z_b, tip_a, tip_b, span, thick, role='finf', sink=0.7):
    """`count` fins root-sunk into the hull between z_a..z_b (tail..lead), tips tip_a..tip_b."""
    root = min(radius_at(profile, z_a), radius_at(profile, z_b))
    assert root > 0, 'fin root outside the hull'
    rho_in = root - thick * sink - 1e-3
    rho_out = max(radius_at(profile, z_a), radius_at(profile, z_b)) + span
    for k in range(count):
        fin(tris, phase + 360.0 * k / count, z_a, z_b, tip_a, tip_b, rho_in, rho_out, thick, role)


# ---------------------------------------------------------------- models
def hull_models():
    models = {}

    # crordhow: long howitzer shell, pointed ogive, copper driving band, no fins
    r = 0.10
    prof = (base_cap(0.0, 0.075) + taper(0.0, 0.07, 0.075, r)
            + body_cyl(0.07, 0.15, r) + band(0.15, 0.25, r, 0.008, 'copper')
            + body_cyl(0.25, 0.50, r) + body_cyl(0.50, 0.56, r, 'warn')
            + nose_ogive(0.56, 0.28, r, 'gun'))
    models['crordhow'] = (prof, [])

    # crordmrt: finned mortar bomb, teardrop body, tail boom with 4 fins
    r = 0.14
    prof = (base_cap(0.0, 0.03) + body_cyl(0.0, 0.26, 0.03, 'gun')
            + taper(0.26, 0.42, 0.03, r) + body_barrel(0.42, 0.52, r, 'olive', 0.0, 2)
            + nose_ogive(0.52, 0.28, r, 'olive', n=5, power=2.0))
    models['crordmrt'] = (prof, [('fin', 4, 45, 0.03, 0.20, 0.0, 0.12, 0.09, 0.022, 'finf')])

    # crordmdm: squat round bomb with an emissive green band (recessed into the barrel)
    r = 0.20
    prof = (base_cap(0.0, 0.10) + taper(0.0, 0.07, 0.10, r - 0.03) + taper(0.07, 0.12, r - 0.03, r)
            + body_cyl(0.12, 0.26, r) + band(0.26, 0.36, r, -0.012, 'green')
            + body_cyl(0.36, 0.44, r) + nose_ogive(0.44, 0.22, r, 'olive', n=4, power=2.2))
    models['crordmdm'] = (prof, [])

    # crordats: slim AT rocket, 4 fins, emissive nozzle
    r = 0.06
    prof = (tail_closed(0.0, r, 0.036, 0.05) + body_cyl(0.0, 0.34, r)
            + body_cyl(0.34, 0.40, r, 'warn') + nose_ogive(0.40, 0.20, r, 'gun', n=4))
    models['crordats'] = (prof, [('fin', 4, 0, 0.04, 0.17, 0.0, 0.12, 0.07, 0.016, 'finf')])

    # crordsps: stubby SP rocket, bigger warhead
    r, rw = 0.06, 0.105
    prof = (tail_closed(0.0, r, 0.034, 0.05) + body_cyl(0.0, 0.26, r)
            + taper(0.26, 0.31, r, rw) + body_cyl(0.31, 0.40, rw, 'warn')
            + nose_ogive(0.40, 0.24, rw, 'olive', n=4, power=1.9))
    models['crordsps'] = (prof, [('fin', 4, 45, 0.03, 0.20, 0.02, 0.14, 0.04, 0.016, 'finf')])

    # crordhrn / crordshd: same missile body, different seeker, nose part and fins
    r = 0.075

    def missile_body(nose):
        return (tail_closed(0.0, r, 0.045, 0.06) + body_cyl(0.0, 0.42, r)
                + body_cyl(0.42, 0.46, r, 'copper') + body_cyl(0.46, 0.60, r) + nose)
    seat = r * (1 - (0.16 / 0.20) ** 1.8) ** 0.62
    prof_h = missile_body([('gun', [(0.60 + 0.16 * i / 3, r * (1 - ((0.16 * i / 3) / 0.20) ** 1.8) ** 0.62) for i in range(4)])]
                          + nose_dome(0.76, 0.05, seat, 'seekero'))
    models['crordhrn'] = (prof_h, [('fin', 4, 0, 0.04, 0.20, 0.0, 0.15, 0.09, 0.018, 'finf'),
                                   ('fin', 4, 0, 0.60, 0.68, 0.58, 0.66, 0.045, 0.014, 'finf')])
    prof_s = missile_body(nose_needle(0.60, 0.34, r, 'gun'))
    prof_s[-1] = ('gun', [(0.60, r), (0.66, r * 0.7), (0.80, r * 0.38)])
    prof_s += nose_dome(0.80, 0.11, r * 0.38, 'blue')
    models['crordshd'] = (prof_s, [('fin', 4, 45, 0.02, 0.30, 0.02, 0.10, 0.10, 0.018, 'finf2')])

    # crordtag: small, short missile
    r = 0.05
    prof = (tail_closed(0.0, r, 0.028, 0.04) + body_cyl(0.0, 0.22, r) + nose_cone(0.22, 0.20, r, 'olive', 0.0))
    models['crordtag'] = (prof, [('fin', 4, 45, 0.02, 0.12, 0.0, 0.08, 0.06, 0.014, 'finf')])

    # crordrkt: fat rocket bomb
    r = 0.14
    prof = (tail_closed(0.0, 0.10, 0.06, 0.06) + taper(0.0, 0.08, 0.10, r)
            + body_cyl(0.08, 0.60, r) + body_cyl(0.60, 0.70, r, 'warn')
            + nose_ogive(0.70, 0.32, r, 'olive', n=5, power=1.8))
    models['crordrkt'] = (prof, [('fin', 4, 0, 0.06, 0.30, 0.0, 0.20, 0.10, 0.030, 'finf')])

    # crordanc: grapple dart, emissive seeker tip, 3 swept forward-raked prong blades
    r = 0.045
    prof = (base_cap(0.0, 0.03) + taper(0.0, 0.04, 0.03, r, 'gun') + body_cyl(0.04, 0.12, r)
            + body_cyl(0.12, 0.16, r, 'copper') + body_cyl(0.16, 0.20, r)
            + taper(0.20, 0.25, r, 0.025, 'gun') + nose_dome(0.25, 0.06, 0.025, 'seekero'))
    models['crordanc'] = (prof, [('fin', 3, 90, 0.05, 0.15, 0.14, 0.27, 0.065, 0.014, 'finf')])

    # crordtgp: targeting puck, closed back, recessed emissive rim band, emissive lens dome
    r = 0.15
    prof = (base_cap(0.0, 0.13) + taper(0.0, 0.015, 0.13, r, 'gun') + body_cyl(0.015, 0.045, r, 'gun')
            + band(0.045, 0.065, r, -0.01, 'green') + body_cyl(0.065, 0.08, r, 'gun')
            + taper(0.08, 0.088, r, 0.115, 'olive') + [('olive', [(0.088, 0.115), (0.088, 0.09)])]
            + nose_dome(0.088, 0.012, 0.09, 'blue'))
    models['crordtgp'] = (prof, [])

    # crordspl: spiked cluster bomb, needle tail and nose, 4 tapering flat spike blades
    prof = ([('gun', [(0.0, 0.0), (0.10, 0.035), (0.28, 0.10)]),
             ('olive', [(0.28, 0.10), (0.33, 0.13)]), ('warn', [(0.33, 0.13), (0.40, 0.14), (0.47, 0.13)]),
             ('olive', [(0.47, 0.13), (0.52, 0.10)]), ('gun', [(0.52, 0.10), (0.70, 0.035), (0.80, 0.0)])])
    models['crordspl'] = (prof, [('fin', 4, 45, 0.31, 0.49, 0.38, 0.42, 0.235, 0.03, 'finf')])

    return models


def compose(profile, fins):
    tris = []
    revolve(profile, tris, None)
    for kind, count, phase, za, zb, ta, tb, span, thick, role in fins:
        fin_set(tris, profile, count, phase, za, zb, ta, tb, span, thick, role)
    z = [v[2] for t in tris for v in t]
    shift = (max(z) + min(z)) / 2          # centre on the origin like the stock meshes
    rows, idx = [], []
    for t in tris:
        for v in t:
            idx.append(len(rows))
            rows.append([v[0], v[1], v[2] - shift, *v[3:]])
    return rows, idx


# ---------------------------------------------------------------- textures
def region_box(role):
    x0, y0, x1, y1 = REGIONS[role]
    return x0 + PAD, y0 + PAD, x1 - PAD, y1 - PAD


def build_textures():
    rng = np.random.default_rng(20261112)
    diff = np.zeros((ATLAS, ATLAS, 3), np.float32)
    emis = np.zeros((ATLAS, ATLAS, 3), np.float32)
    line = np.array([22, 24, 22], np.float32)

    def noise(h, w, amp):
        n = rng.normal(0, amp, (h, w, 1)).astype(np.float32)
        return n + rng.normal(0, amp * 0.5, (h, 1, 1)).astype(np.float32)

    def paint(role, base, em=None, seams=0, stripes=None):
        X0, Y0, X1, Y1 = REGIONS[role]
        x0, y0, x1, y1 = region_box(role)
        diff[Y0:Y1, X0:X1] = line
        h, w = y1 - y0, x1 - x0
        tile = np.empty((h, w, 3), np.float32)
        tile[:] = base
        tile += noise(h, w, 4.0)
        if stripes:  # horizontal bands (rings on the mesh), alternating colours
            a, b, period = stripes
            ys = (np.arange(h) // period) % 2
            tile[ys == 0] = a
            tile[ys == 1] = b
            tile += noise(h, w, 3.0)
        if em is not None:
            ys = np.linspace(-1, 1, h)[:, None, None]
            glow = np.clip(1.0 - 0.55 * np.abs(ys), 0, 1)
            tile = np.broadcast_to(np.asarray(base, np.float32), (h, w, 3)) * (0.55 + 0.45 * glow) + noise(h, w, 2.0)
            emis[y0:y1, x0:x1] = np.asarray(em, np.float32) * glow
        # panel lines on the island's own edges (ring/fin outlines) and at the seam columns
        tile[:5] = line
        tile[-5:] = line
        tile[5:7] = np.clip(tile[5:7] * 1.35, 0, 255)
        tile[-7:-5] = np.clip(tile[-7:-5] * 1.35, 0, 255)
        for k in range(seams + 1):
            c = int(round(k * (w - 1) / max(seams, 1))) if seams else 0
            for dc in range(-2, 3):
                if 0 <= c + dc < w:
                    tile[:, c + dc] = line * (1.0 if abs(dc) < 2 else 1.6)
        if em is None:
            tile[:, 0:1] = line
            tile[:, -1:] = line
        diff[y0:y1, x0:x1] = tile

    paint('olive', (84, 92, 52), seams=6)
    paint('gun', (62, 66, 72), seams=6)
    paint('copper', (176, 104, 56), seams=12)
    paint('warn', 0, stripes=((212, 176, 40), (34, 34, 30), 12), seams=6)
    paint('finf', (70, 76, 58))
    paint('finf2', (58, 66, 84))
    paint('fine', (40, 42, 44))
    paint('orange', (140, 60, 16), em=(255, 120, 24))
    paint('green', (30, 120, 50), em=(60, 255, 90))
    paint('blue', (150, 190, 230), em=(170, 215, 255))
    paint('seekero', (190, 80, 16), em=(255, 110, 20))
    # fin centre rib (face-local, along the chord), drawn after the fill
    for role in ('finf', 'finf2'):
        x0, y0, x1, y1 = region_box(role)
        cx = (x0 + x1) // 2
        diff[y0 + 8:y1 - 8, cx - 1:cx + 1] = line
    return (np.clip(diff, 0, 255).astype(np.uint8), np.clip(emis, 0, 255).astype(np.uint8))


MATERIAL_TEXT = '''import * from "CR_BZBase.material"

material crord : CR_BZBase
{
    set_texture_alias DiffuseMap crord_d.dds
    set_texture_alias EmissiveMap crord_e.dds
    set $diffuse "1 1 1"
    set $ambient "1 1 1"
    set $specular ".35 .35 .35"
    set $shininess "48"
    set $glow "1 1 1"
}
'''


def geo_bytes(name, rows, idx):
    """Native .geo twin of the mesh. ODFs name the .geo (as stock ordnance does) and Ogre
    draws the same-named .mesh; without the .geo the engine logs 'could not add geometry'."""
    import io
    from bzmodellibs import geo, geo_serializer
    rows = np.asarray(rows, dtype='<f8')
    points = rows[:, :3].astype('<f4')
    g = geo.Geo()
    g.name = name
    g.vert_count = len(points)
    g.vertex_pos_buffer = points
    g.vertex_normal_buffer = rows[:, 3:6].astype('<f4')
    for i in range(0, len(idx), 3):
        q = [rows[j, :3] for j in idx[i:i + 3]]
        normal = np.cross(q[1] - q[0], q[2] - q[0])
        length = np.linalg.norm(normal)
        normal = normal / length if length > 1e-12 else np.array([0.0, 1.0, 0.0])
        face = g.create_face(i // 3)
        face.color = geo.Color3(255, 255, 255)
        face.plane = geo.SurfacePlane(geo.Vector3(*(-normal)), float(normal.dot(q[0])))
        face.shade_type = face.texture_type = 0
        face.texture_name = name + '.map'
        for j in idx[i:i + 3]:
            face.create_face_node(j, j, geo.UV(float(rows[j, 6]), float(rows[j, 7])))
    raw = io.BytesIO()
    geo_serializer.GeoSerializer(raw).write(g)
    return raw.getvalue()


def main():
    MESH_DIR.mkdir(parents=True, exist_ok=True)
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    for name, (profile, fins) in sorted(hull_models().items()):
        rows, idx = compose(profile, fins)
        assert len(idx) // 3 <= 400, (name, len(idx) // 3)
        (MESH_DIR / (name + '.mesh')).write_bytes(static_mesh_bytes(MATERIAL, rows, idx))
        (MESH_DIR / (name + '.geo')).write_bytes(geo_bytes(name, rows, idx))
        print(f'{name}: {len(idx) // 3} tris')
    diff, emis = build_textures()
    save_bc(Image.fromarray(diff, 'RGB'), TEX_DIR / 'crord_d.dds')
    save_bc(Image.fromarray(emis, 'RGB'), TEX_DIR / 'crord_e.dds')
    (ROOT / 'Materials/CR_Ordnance.material').write_bytes(MATERIAL_TEXT.encode('ascii'))


if __name__ == '__main__':
    main()
