"""Thruster housings ("nacelle jets") at the points where a hover craft's jet flames emit.

    python Tools/Build-NacelleJets.py [--units avfigh] [--skip-render] [--ship]
    python Tools/Build-NacelleJets.py --contact --units avtank avltnk   # contact sheets from finished renders

Most stock hover VDFs carry no flame-emitter part, so the engine hangs one under every
nacelle part (class 67): at the part origin dropped to the bottom of its bounding box,
firing along the part's -Y. A VDF that authors flame-emitter parts (class 75) emits from
those instead, along each part's front axis (BZ 1.5 decompile; see
References/NacelleJets/README.md). This tool derives those points from the unit's VDF, GEOs
and skeleton, builds a housing around each one (Tools/nacellejet_blender.py), paints it in
the unit's faction colours and writes a preview mesh, textures and material under
Local/NacelleJets plus review renders (References/NacelleJets/review for shipped units,
Local/NacelleJets/review-rollout for previews). It always starts from the unit's pre-rig
mesh (the weapon-rig source revision), so it can be re-run at any time.

--ship installs the result as the unit's pre-rig stage: Assets/ModelFixes/<unit>.mesh, the
four textures and the material block. Commit that, pin the commit in
References/WeaponRigs/models.json stage_revisions, then re-run Tools/Build-WeaponRigs.py for
the unit (References/NacelleJets/README.md has the steps).
"""
from pathlib import Path
import argparse, hashlib, io, json, math, os, re, shutil, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'Tools'))
import ogrelayout
import reddevilcockpit as shared
import weaponrigs as wr
from bcdds import save_bc
from bzmodellibs import legacy, legacy_port

om, oms, VES = shared.om, shared.oms, shared.om.VES
BLENDER = Path(os.environ.get('CR_BLENDER') or r'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe')
PAINT, BELL, LIP, GROOVE, BORE, THROAT, VENT = range(7)
SIZE = 512

S = np.array([-1., 1., 1.])  # VDF space -> Ogre mesh space
MIRROR = np.array([-1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1])  # a vertex row mirrored in x

# Faction dressing that cannot be sampled from the hull texture.
FACTIONS = {'nsdf': dict(stripe=(214, 214, 204), glow=(40, 140, 255)), 'blackdogs': dict(stripe=(176, 44, 36), glow=(255, 96, 40)),
            'cca': dict(stripe=(206, 176, 70), glow=(255, 70, 50)), 'cra': dict(stripe=(196, 150, 60), glow=(70, 230, 170))}
# Shape in metres, in the housing's build frame: the flame runs along -y, z runs along the
# chord from the emit point (+z is the nose), pod depth hangs from the measured wing
# underside, bell/bore/groove heights are from the emit point.
BASE = dict(
    sides=20, bury=.06, chamfer=.045, flat=.86, smoothAngle=35,
    sections=[(.47, .09, .015), (.37, .21, .07), (.24, .30, .12), (.21, .30, .12), (.14, .30, .12),
              (-.20, .30, .12), (-.33, .21, .08), (-.44, .08, .015)],
    bell=dict(top=0., lip=-.15, rTop=.25, rLip=.235),
    bore=dict(roof=.03, rRoof=.15, rMouth=.205),
    groove=dict(y0=-.132, y1=-.120, depth=.008, rOut=.28),
    vent=dict(z=[-.13, -.03, .07], drop=.04, halfWidth=.30, depth=.02, height=.03, length=.085))


def fitted(scale, length=1., **over):
    """BASE scaled to another unit (chord by scale x length). The build seats it on a plane
    measured under the pod and sets the pod depth from how far the emit point hangs below
    the skin. over: bury (metres into the wing), offset (dx, dz of the pod body from the
    emit point, build frame)."""
    k = lambda v: v * scale
    shape = dict(sides=BASE['sides'], flat=BASE['flat'], smoothAngle=BASE['smoothAngle'], bury=k(BASE['bury']), chamfer=k(BASE['chamfer']),
                 sections=[(k(z) * length, k(a), k(d)) for z, a, d in BASE['sections']],
                 vent=dict({n: k(v) for n, v in BASE['vent'].items() if n != 'z'}, z=[k(z) * length for z in BASE['vent']['z']]),
                 scale=scale, auto=True, stripe=(k(.14) * length, k(.21) * length))
    for part in ('bell', 'bore', 'groove'):
        shape[part] = {n: k(v) for n, v in BASE[part].items()}
    return dict(shape, **over)


def unit(faction, scale, length=1., also=(), **over):
    """CONFIG entry. also: ((part-name regex, shape), ...) for nacelles that need their own shape."""
    return dict(faction=faction, shape=fitted(scale, length, **over), also=also)


CONFIG = {
    'avfigh': dict(faction='nsdf', stripe=(.14, .21), shape=BASE),
    # Fitted shapes. scale ~ flame width (the engine draws every unit's flame the same size)
    # and the room under the nacelle; length stretches the pod along the chord.
    'avapc': unit('nsdf', 1.3, .4, offset=(0, -.42)), 'avartl': unit('nsdf', 1.2, also=(('nrl$', fitted(.9, .6, offset=(0, -.18))),)), 'avltnk': unit('nsdf', 1., .6), 'avmine': unit('nsdf', 1.3),
    'avrckt': unit('nsdf', 1.), 'avtank': unit('nsdf', 1., .8), 'avhraz': unit('nsdf', .9, .8), 'avtest': unit('nsdf', .8),
    'bvapc': unit('blackdogs', 1.3, .4, offset=(0, -.42)), 'bvartl': unit('blackdogs', 1.2, also=(('nrl$', fitted(.9, .6, offset=(0, -.18))),)), 'bvltnk': unit('blackdogs', 1., .6), 'bvmine': unit('blackdogs', 1.3),
    'bvraz': unit('blackdogs', .9), 'bvrckt': unit('blackdogs', 1.), 'bvtank': unit('blackdogs', 1., .8),
    'svapc': unit('cca', 1.3), 'svartl': unit('cca', 1.3, offset=(.25, 0)), 'svfigh': unit('cca', 1., offset=(.2, 0)), 'svhraz': unit('cca', .8, .6, offset=(.15, 0)), 'svltnk': unit('cca', .8, .9, offset=(-.12, 0)),
    'svmine': unit('cca', 1.2, offset=(.2, 0)), 'svmuf': unit('cca', 1.4, offset=(.2, 0)), 'svrckt': unit('cca', 1.1), 'svrecy': unit('cca', 1.5), 'svslf': unit('cca', 1.2), 'svscav': unit('cca', 1.3),
    'cvfigh': unit('cra', .9), 'cvhraz': unit('cra', 1.3), 'cvmine': unit('cra', .9),
    # Units that author class 75 flame parts: one housing per part, along its own front axis.
    'bvrdev': unit('blackdogs', .9), 'svhaul': unit('cca', 1.2),
}


def unit_vectors(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def quat_matrix(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def vdf_world(parts):
    """Band-0 part world transforms in VDF space: rows right, up, front; and the position."""
    by = {p.name.lower(): p for p in parts}; cache = {}

    def world(p):
        key = p.name.lower()
        if key not in cache:
            m = np.array(p.matrix, float); R, t = m[:9].reshape(3, 3), m[9:]
            parent = by.get((p.parent or '').lower())
            if parent is not None and parent is not p:
                Rp, tp = world(parent); R, t = R @ Rp, t @ Rp + tp
            cache[key] = (R, t)
        return cache[key]
    return {p.name.lower(): world(p) for p in parts}, by


def vdf_pose(skeleton, W):
    """Per bone, (D, shift) taking bind-pose mesh points to the VDF band-0 pose: p' = D p + shift.
    A bone without a VDF part follows its nearest ancestor that has one."""
    out = {}
    for b in skeleton.bones:
        a = b
        while a is not None and a.name.lower() not in W:
            a = skeleton.bones[a.parent] if a.parent is not None else None
        if a is None:
            out[b.handle] = (np.eye(3), np.zeros(3)); continue
        R, t = W[a.name.lower()]; M = (R.T * S[:, None]) * S[None, :]; pos, q = wr.flash.bone_world(skeleton, a.handle)
        D = M @ quat_matrix(q).T; out[b.handle] = (D, t * S - D @ np.array(pos, float))
    return out


def emitters(unit, skeleton, mesh):
    """Engine flame emit points in Ogre mesh space (skeleton bind pose), and the bind-to-VDF
    pose of every bone. One emitter per class 75 part when the VDF authors any, else one under
    every class 67 nacelle. Each carries the bone its housing rides, `axes` (build frame as
    columns: the flame runs along -y) when that frame is not the mesh frame, and `posed`: the
    same point and flame direction in the VDF pose."""
    source = legacy_port.AssetSource(folders=[ROOT / 'Assets/ModelFixes', ROOT / 'Assets/Models'],
                                     archives=[wr.GAME / 'bzone.zfs', wr.GAME / 'tro_cam.zfs'])
    parts = legacy.read_vdf(source(unit + '.vdf')).band(0); W, by = vdf_world(parts); pose = vdf_pose(skeleton, W)
    authored = [p for p in parts if p.klass == 75]; out = []
    for part in authored or [p for p in parts if p.klass == 67]:
        owner = part; bone = None
        while bone is None:  # an emitter part without a bone rides its parent's
            bone = next((b for b in skeleton.bones if b.name.lower() == owner.name.lower()), None)
            owner = by[owner.parent.lower()] if bone is None else owner
        D, shift = pose[bone.handle]; pivot, q = wr.flash.bone_world(skeleton, bone.handle); pivot = np.array(pivot, float)
        jet = dict(part=part.name, bone=bone.handle, pivot=[float(c) for c in pivot])
        skin = bone  # the housing seats on the skin its bone owns, or the nearest ancestor's when the bone owns none (a hardpoint stub of a few triangles is not skin)
        while skin is not None and sum(a.bone_index == skin.handle for s in mesh.submesh_list for a in s.bone_assignments()) < 24:
            skin = skeleton.bones[skin.parent] if skin.parent is not None else None
        assert skin is not None, (part.name, 'no bone up its chain owns any mesh')
        if skin is not bone:
            jet['skin'] = skin.handle
        if authored:
            # Its own transform; the flame runs along the part's front axis (BZ 1.5 decompile
            # all_decompiled.c 255588-255605: flame end = position + front * 2 * flameLength * scale;
            # class 75 parts collected at 193702-193706). UNVERIFIED against the Redux renderer.
            R, t = W[part.name.lower()]; M = (R.T * S[:, None]) * S[None, :]; y = -M[:, 2]; z = M[:, 1]
            jet.update(source='class 75 part', emit=(D.T @ (t * S - shift)).tolist(), axes=(D.T @ np.c_[np.cross(y, z), y, z]).tolist())
            if owner is not part:
                jet['rides'] = owner.name
        else:
            geo = source(part.name + '.geo')
            if geo is None:  # no GEO to read the bounding box from: lowest vertex the nacelle bone owns
                own = hull(mesh, bone.handle)[0].reshape(-1, 3); assert len(own), (part.name, 'has neither a GEO nor mesh triangles')
                drop = float(((own - pivot) @ quat_matrix(q))[:, 1].min()); jet['estimate'] = 'GEO file missing: emit height taken from the lowest mesh vertex the nacelle bone owns'
            else:
                drop = float(np.asarray(legacy.read_geo(geo).positions, float)[:, 1].min())
            if max(abs(c) for c in q[:3]) < 1e-5:
                jet['emit'] = [float(pivot[0]), float(pivot[1]) + drop, float(pivot[2])]
            else:  # rotated bind pose: the drop and the flame follow the nacelle's own up axis
                Rb = quat_matrix(q); jet.update(emit=(pivot + Rb[:, 1] * drop).tolist(), axes=Rb.tolist())
        e = np.array(jet['emit']); Q = np.array(jet.get('axes', np.eye(3)))
        jet['posed'] = dict(emit=(D @ e + shift).tolist(), flame=(-(D @ Q)[:, 1]).tolist(), axes=(D @ Q).tolist())
        out.append(jet)
    assert out, 'no class 67 nacelle and no class 75 flame emitter: the engine draws no flame'
    return sorted(out, key=lambda e: -e['emit'][0]), pose  # +X first: the solid is built there


def hull(mesh, bone=None):
    """Triangles (positions, uvs, submesh number) of the opaque hull: all of it, or those owned by one bone."""
    out = []
    for n, sub in enumerate(mesh.submesh_list):
        if 'glass' in sub.material_name.lower() or sub.material_name.endswith('_nacjet'):
            continue
        p = shared.values(sub.vertex_data, VES.POSITION).astype(float); uv = shared.values(sub.vertex_data, VES.TEXTURE_COORDINATES).astype(float)
        index = np.array(sub.index_array).reshape(-1, 3); owner = np.full(len(p), -1)
        for a in sub.bone_assignments():
            owner[a.vertex_index] = a.bone_index
        if bone is not None:
            index = index[(owner[index] == bone).all(1)]
        out.append((p[index], uv[index], np.full(len(index), n)))
    return [np.concatenate(v) for v in zip(*out)]


def to_build(points, jet, centre, mirror):
    """Mesh-space points around jet in a build frame whose emit point is centre: the jet's own
    frame, x-mirrored when mirror (a housing built on +X and carried on -X, or the reverse)."""
    e = np.array(jet['emit'])
    if not mirror and 'axes' not in jet and np.abs(e - centre).max() < 1e-9:
        return points
    flip = np.array((-1., 1, 1) if mirror else (1., 1, 1))
    return ((points - e) @ np.array(jet.get('axes', np.eye(3)))) * flip + centre


def instance(rows, jet, centre, mirror):
    """Vertex rows of a solid built around centre, placed on jet in mesh space (inverse of to_build)."""
    out = rows * MIRROR if mirror else rows
    origin = np.array(centre) * ((-1., 1, 1) if mirror else (1., 1, 1)); e = np.array(jet['emit'])
    if 'axes' not in jet and np.abs(e - origin).max() < 1e-4:
        return out
    Q = np.array(jet.get('axes', np.eye(3))).T; out = out.copy()
    out[:, :3] = (out[:, :3] - origin) @ Q + e; out[:, 3:6] = out[:, 3:6] @ Q; out[:, 8:11] = out[:, 8:11] @ Q
    return out


def underside(tri, emit, shape, plane=None):
    """Least-squares height of the wing underside over the pod footprint: along the chord, and
    across it too for a fitted shape. Returns the fit, its worst error and the seat: share of
    the footprint with skin above it, and share where the buried roof would come out of the
    far side. With plane, measures against that fit instead."""
    a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
    d = (b[:, 2] - c[:, 2]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 2] - c[:, 2])
    ok = np.abs(d) > 1e-12; d = np.where(ok, d, 1); ox, oz = shape.get('offset', (0., 0.)); auto = shape.get('auto')
    half = max(s[1] for s in shape['sections']); zs = [s[0] for s in shape['sections']]; rows = []; total = 0
    outline = sorted((s[0], s[1]) for s in shape['sections'])
    grid = {}
    for i, x in enumerate(np.arange(emit[0] + ox - half, emit[0] + ox + half + 1e-6, .05)):
        for j, z in enumerate(np.arange(emit[2] + oz + min(zs), emit[2] + oz + max(zs) + 1e-6, .05)):
            if auto and abs(x - emit[0] - ox) > np.interp(z - emit[2] - oz, *zip(*outline)):
                continue  # outside the tapered pod outline
            total += 1; grid[i, j] = None
            u = ((b[:, 2] - c[:, 2]) * (x - c[:, 0]) + (c[:, 0] - b[:, 0]) * (z - c[:, 2])) / d
            v = ((c[:, 2] - a[:, 2]) * (x - c[:, 0]) + (a[:, 0] - c[:, 0]) * (z - c[:, 2])) / d
            hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1)
            if hit.any():
                y = np.sort((u * a[:, 1] + v * b[:, 1] + (1 - u - v) * c[:, 1])[hit]); above = y[y > y[0] + .01]
                grid[i, j] = (z - emit[2], y[0], x - emit[0], above[0] if len(above) else np.inf)
    for (i, j), row in list(grid.items()):
        # A thin sliver next to a cell with no skin is the part's side wall, not a far side the
        # roof could come out of: the pod roof shows there, as it does past the edge.
        if auto and row and row[3] - row[1] < .05 and any(grid.get(n) is None for n in ((i - 1, j), (i + 1, j), (i, j - 1), (i, j + 1))):
            grid[i, j] = None
    rows = [row for row in grid.values() if row]
    assert len(rows) > 3, 'no skin above the pod footprint to seat the housing on'
    rows = np.array(rows); A = np.c_[np.ones(len(rows)), rows[:, 0], rows[:, 2]][:, :3 if auto else 2]
    fit = np.array(plane) if plane is not None else np.linalg.lstsq(A, rows[:, 1], rcond=None)[0]
    error = float(np.abs(rows[:, 1] - A @ fit).max())
    if auto and plane is not None:  # against a seated plane only skin above it (the roof would float) counts
        error = float((rows[:, 1] - A @ fit).max())
    if auto and plane is None:  # seat on the highest skin so the roof is buried everywhere; the pod deepens to suit
        fit[0] += (rows[:, 1] - A @ fit).max()
    seat = dict(cover=len(rows) / total, pokes=float((A @ fit + shape['bury'] > rows[:, 3] - .003).mean()))
    if plane is None:
        assert error < (shape['scale'] * .3 if auto else shape['bury'] * .5), ('wing underside is not flat enough to bury the pod roof', error)
        assert not auto or seat['cover'] >= .35, ('too little skin above the pod footprint to seat on', seat)
        assert seat['pokes'] == 0, ('the buried pod roof would come out of the far side of the wing', seat)
    return [float(f) for f in fit], error, seat


def solid_config(shape, emit, fit, seat):
    """Absolute dimensions for the Blender step and for the face tagging."""
    out = dict(shape, emit=emit, underside=fit)
    if shape.get('auto'):
        # gap: skin height above the emit point. The pod is as deep as it takes to carry the
        # nozzle at the emit point. Where the emit point is at or inside the skin the nozzle
        # hangs just under the skin instead (its throat stays buried; the flame then starts
        # above the throat) and `inside` says by how much.
        s = shape['scale']; gap = fit[0] - emit[1]; datum = min(emit[1], fit[0] - .05 * s)
        k = (fit[0] - datum + .09 * s) / (.12 * s)
        out.update(emit=[emit[0], datum, emit[2]], sections=[(z, a, d * k) for z, a, d in shape['sections']],
                   vent=dict(shape['vent'], drop=shape['vent']['drop'] * min(k, 1), height=shape['vent']['height'] * min(k, 1)),
                   dropBuried=seat['cover'] > .999, seated=dict(seat, gap=gap, inside=emit[1] - datum, depthScale=k))
        emit = out['emit']
    for part, keys in (('bell', ('top', 'lip')), ('bore', ('roof',)), ('groove', ('y0', 'y1'))):
        out[part] = dict(shape[part], **{k: emit[1] + shape[part][k] for k in keys})
    groove = out['groove']
    out['groove']['rIn'] = bell_radius(out, (groove['y0'] + groove['y1']) / 2) - groove['depth']
    return out


def bell_radius(cfg, y):
    b = cfg['bell']
    return b['rLip'] + (b['rTop'] - b['rLip']) * (y - b['lip']) / (b['top'] - b['lip'])


def bore_radius(cfg, y):
    return cfg['bore']['rMouth'] + (cfg['bore']['rRoof'] - cfg['bore']['rMouth']) * (y - cfg['bell']['lip']) / (cfg['bore']['roof'] - cfg['bell']['lip'])


def lathe_radius(cfg, p):
    """Circumradius of the N-gon lathe ring a point lies on (plain radius would dip mid-facet)."""
    step = 2 * math.pi / cfg['sides']
    angle = np.arctan2(p[..., 2] - cfg['emit'][2], p[..., 0] - cfg['emit'][0]) % step
    return np.hypot(p[..., 0] - cfg['emit'][0], p[..., 2] - cfg['emit'][2]) * np.cos(angle - step / 2) / math.cos(step / 2)


def tag_faces(tri, cfg):
    """Material zone of every triangle, from where it sits on the construction solids."""
    eps = 2e-3; y = tri[..., 1]; rho = lathe_radius(cfg, tri); centre = tri.mean(1)
    bell, bore, groove, vent = cfg['bell'], cfg['bore'], cfg['groove'], cfg['vent']
    tag = np.full(len(tri), PAINT)
    tag[(np.abs(rho - bell_radius(cfg, y)) < eps).all(1) & (y < bell['top'] + eps).all(1)] = BELL
    tag[(y > groove['y0'] - eps).all(1) & (y < groove['y1'] + eps).all(1) & (rho < bell_radius(cfg, y) + eps).all(1) & (rho > groove['rIn'] - eps).all(1)] = GROOVE
    tag[(np.abs(y - bell['lip']) < eps).all(1)] = LIP
    tag[(rho < bore_radius(cfg, y) + eps).all(1) & (y > bell['lip'] + eps).any(1) & (y < bore['roof'] + eps).all(1)] = BORE
    tag[(np.abs(y - bore['roof']) < eps).all(1) & (rho < bore['rRoof'] + eps).all(1)] = THROAT
    ox, oz = cfg.get('offset', (0., 0.)); side = centre[:, 0] - cfg['emit'][0] - ox
    slope = cfg['underside'][2] * (ox + np.sign(side) * vent['halfWidth']) if len(cfg['underside']) > 2 else 0.; side = np.abs(side)
    for z in vent['z']:
        zc = cfg['emit'][2] + z + oz; yc = cfg['underside'][0] + cfg['underside'][1] * (z + oz) + slope - vent['drop']
        tag[(np.abs(centre[:, 2] - zc) < vent['length'] / 2 + eps) & (np.abs(centre[:, 1] - yc) < vent['height'] / 2 + eps)
            & (side < vent['halfWidth'] - eps / 2) & (side > vent['halfWidth'] - vent['depth'] - eps)] = VENT
    for name, value in (('bell', BELL), ('lip', LIP), ('groove', GROOVE), ('bore', BORE), ('throat', THROAT), ('vent', VENT)):
        assert (tag == value).any(), name + ' zone is missing from the solid'
    return tag


def raster(uv):
    """Per texel: the covering triangle (-1 where empty) and its barycentric weights."""
    face = np.full((SIZE, SIZE), -1); weight = np.zeros((SIZE, SIZE, 3))
    for f, t in enumerate(uv * SIZE):
        x0, y0 = np.floor(t.min(0)).astype(int).clip(0); x1, y1 = np.ceil(t.max(0)).astype(int).clip(None, SIZE)
        d = (t[1, 1] - t[2, 1]) * (t[0, 0] - t[2, 0]) + (t[2, 0] - t[1, 0]) * (t[0, 1] - t[2, 1])
        if abs(d) < 1e-12 or x0 >= x1 or y0 >= y1:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1) + .5, np.arange(y0, y1) + .5)
        a = ((t[1, 1] - t[2, 1]) * (X - t[2, 0]) + (t[2, 0] - t[1, 0]) * (Y - t[2, 1])) / d
        b = ((t[2, 1] - t[0, 1]) * (X - t[2, 0]) + (t[0, 0] - t[2, 0]) * (Y - t[2, 1])) / d
        inside = (a >= 0) & (b >= 0) & (a + b <= 1)
        face[y0:y1, x0:x1][inside] = f; weight[y0:y1, x0:x1][inside] = np.dstack([a, b, 1 - a - b])[inside]
    return face, weight


def mesh_edges(tri, tag, crease):
    """Creases and zone borders of the solid itself: (face, corner, convex, border) per side."""
    ids = {}; vid = np.array([[ids.setdefault(tuple(p), len(ids)) for p in t] for t in np.round(tri, 5)])
    normal = unit_vectors(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])); centre = tri.mean(1); users = {}
    for f, v in enumerate(vid):
        for i in range(3):
            users.setdefault((min(v[i], v[(i + 1) % 3]), max(v[i], v[(i + 1) % 3])), []).append((f, i))
    out = []
    for pair in users.values():
        if len(pair) != 2:
            continue
        (f, i), (g, j) = pair; border = tag[f] != tag[g]
        if border or normal[f] @ normal[g] < math.cos(math.radians(crease)):
            convex = normal[f] @ (centre[g] - centre[f]) < 0
            out += [(f, i, convex, border), (g, j, convex, border)]
    return out


def blurred(mask, radius):
    return np.asarray(Image.fromarray(np.uint8(np.clip(mask, 0, 1) * 255)).filter(ImageFilter.GaussianBlur(radius)), float) / 255


def paint_colour(mesh, bone):
    """Faction hull paint: the median chromatic texel of the submesh that carries the nacelle."""
    tri, uv, sub = hull(mesh); n = np.bincount(hull(mesh, bone)[2]).argmax(); uv = uv[sub == n]
    path = texture_path(mesh.submesh_list[n].material_name); assert path, (mesh.submesh_list[n].material_name, 'has no diffuse map in this mod')
    image = np.asarray(Image.open(path).convert('RGB'), float); h, w = image.shape[:2]
    weights = np.random.default_rng(1).dirichlet((1, 1, 1), (len(uv), 8))
    sample = (weights[..., None] * uv[:, None]).sum(2).reshape(-1, 2) % 1
    texel = image[(sample[:, 1] * h).astype(int).clip(0, h - 1), (sample[:, 0] * w).astype(int).clip(0, w - 1)]
    chroma = texel.max(1) - texel.min(1); texel = texel[(chroma > 15) & (texel.max(1) < 200)]
    assert len(texel) > 200, 'could not find painted texels on the hull'
    return [float(c) for c in np.median(texel, 0)], path


def texture_path(material):
    """Diffuse texture file of a material in this mod, or None."""
    for path in sorted((ROOT / 'Materials').glob('*.material')):
        block = re.search(r'^material\s+' + re.escape(material) + r'\s*:[^{]*\{(.*?)^\}', path.read_text(errors='ignore'), re.S | re.M)
        if block:
            name = re.search(r'set_texture_alias\s+DiffuseMap\s+(\S+)', block.group(1))
            stock = wr.GAME / 'BZ_ASSETS/pc/textures'  # stock faction packs keep theirs in a subfolder (TRO/DIFF)
            for folder in [ROOT / 'Assets/Textures', stock / 'DIFF'] + [f / 'DIFF' for f in stock.iterdir() if f.is_dir()]:
                if name and (folder / name.group(1)).is_file():
                    return folder / name.group(1)
    return None


def textures(unit, tri, uv, tag, cfg, stripe, paint, faction):
    """Diffuse, normal, specular and emissive images. Every line follows one of the solid's
    own creases or zone borders; colour ramps use the lathe and loft parameters."""
    face, weight = raster(uv); filled = face >= 0; f = np.where(filled, face, 0)
    p = (weight[..., None] * tri[f]).sum(2); zone = np.where(filled, tag[f], -1)
    emit = cfg['emit']; bell, bore = cfg['bell'], cfg['bore']
    relz = p[..., 2] - emit[2]; y = p[..., 1]; drop = cfg['underside'][0] + cfg['underside'][1] * relz - y
    if len(cfg['underside']) > 2:
        drop = drop + cfg['underside'][2] * (p[..., 0] - emit[0])
    rng = np.random.default_rng(int(hashlib.sha256(unit.encode()).hexdigest()[:8], 16))
    mottle = blurred(rng.random((SIZE, SIZE)), 5); mottle = (mottle - mottle.mean()) / mottle.std()
    blotch = blurred(rng.random((SIZE, SIZE)), 14); blotch = (blotch - blotch.mean()) / blotch.std()
    grain = rng.normal(0, 1, (SIZE, SIZE))

    scale = 4; seam = Image.new('L', (SIZE * scale,) * 2); wear = Image.new('L', (SIZE * scale,) * 2); rivet = Image.new('L', (SIZE * scale,) * 2)
    for fi, corner, convex, border in mesh_edges(tri, tag, cfg['smoothAngle']):
        a, b, c = (uv[fi][(corner + k) % 3] * SIZE * scale for k in range(3))
        if border or not convex:
            ImageDraw.Draw(seam).line([tuple(a), tuple(b)], fill=255, width=int(2.2 * scale))
        if convex and tag[fi] not in (BORE, THROAT, VENT, GROOVE):
            ImageDraw.Draw(wear).line([tuple(a), tuple(b)], fill=255, width=int(2.6 * scale))
        # Rivet row just inside every long crease of a painted panel.
        pa, pb, pc = (tri[fi][(corner + k) % 3] for k in range(3)); length = np.linalg.norm(pb - pa)
        height = np.linalg.norm(np.cross(pb - pa, pc - pa)) / max(length, 1e-9)
        if tag[fi] == PAINT and convex and not border and length > .1 and height > .04:
            inset = .016 / height
            for s in (np.arange(.5, int(length / .05)) + .0) / int(length / .05):
                q = (a * (1 - s) + b * s) * (1 - inset) + c * inset; r = 1.5 * scale
                ImageDraw.Draw(rivet).ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=255)
    down = lambda image: np.asarray(image.resize((SIZE, SIZE), Image.LANCZOS), float) / 255
    seam, wear, rivet = down(seam), down(wear), down(rivet)
    grime = blurred(seam, 5); chipped = np.clip(blurred(wear, 1.2) * (1.1 + .9 * mottle) - .25, 0, 1)

    paint = np.array(paint); bare = np.array((148., 150, 146)); glow = np.array(faction['glow'], float)
    colour = np.zeros((SIZE, SIZE, 3)); spec = np.zeros((SIZE, SIZE)); emissive = np.zeros((SIZE, SIZE, 3))
    body = paint * (1 + .07 * blotch[..., None] + .04 * mottle[..., None])
    band = (relz >= stripe[0]) & (relz <= stripe[1])
    body = np.where((band & (blotch + mottle < 1.4))[..., None], np.array(faction['stripe'], float) * (1 + .05 * mottle[..., None]), body)
    body *= (.55 + .45 * np.clip(drop / .035, 0, 1))[..., None]  # contact shadow under the wing skin
    t = np.clip((y - bell['lip']) / (bell['top'] - bell['lip']), 0, 1)[..., None]  # 0 at the lip
    heat = np.clip(1 - t / .65, 0, 1) ** 1.5
    metal = (np.array((60., 63, 68)) * (1 - heat) + np.array((104., 78, 58)) * heat) * (1 + .06 * mottle[..., None])
    depth = np.clip((y - bell['lip']) / (bore['roof'] - bell['lip']), 0, 1)[..., None]  # 1 at the bore roof
    core = np.clip(1 - (lathe_radius(cfg, p) / bore['rRoof']) ** 2 * .7, 0, 1)[..., None]
    hot = np.array((255., 150, 60))
    for value, base, shine in ((PAINT, body, 46 + 14 * band), (BELL, metal, 120), (LIP, np.array((118., 114, 106)) * (1 + .08 * mottle[..., None]), 160),
                               (GROOVE, glow * .45, 40), (BORE, np.array((26., 24, 24)) * (1 - depth) + np.array((84., 44, 24)) * depth, 22),
                               (THROAT, np.array((110., 58, 30)) * core, 30), (VENT, np.array((15., 16, 18)) + 0 * body, 10)):
        mask = zone == value; colour[mask] = np.broadcast_to(base, colour.shape)[mask]; spec[mask] = np.broadcast_to(shine, spec.shape)[mask]
    emissive[zone == GROOVE] = glow * .95
    emissive[zone == BORE] = (hot * .45 * depth ** 2.5)[zone == BORE]
    emissive[zone == THROAT] = (hot * (.35 + .65 * core))[zone == THROAT]
    worn = (chipped * np.isin(zone, (PAINT, BELL, LIP)))[..., None]
    colour = colour * (1 - worn) + np.where((zone == PAINT)[..., None], bare, colour * 1.7) * worn
    lit = (zone == GROOVE) | (zone == THROAT)
    colour *= np.where(lit, 1, (1 - .5 * grime) * (1 - .7 * seam))[..., None]
    colour *= (1 - .35 * rivet[..., None]) * (1 + .03 * grain[..., None])
    spec = (spec + 90 * worn[..., 0]) * np.where(lit, 1, 1 - .6 * seam)
    height = blurred(rivet, .8) * .7 - blurred(seam, .9)
    gy, gx = np.gradient(height); n = unit_vectors(np.dstack([-gx * 3.5, -gy * 3.5, np.ones_like(gx)]))  # +v (image down) is the shader's binormal
    images = dict(D=colour, N=(n * .5 + .5) * 255, S=np.repeat(spec[..., None], 3, 2), E=emissive)
    return {k: Image.fromarray(np.uint8(np.clip(padded(v, filled), 0, 255))) for k, v in images.items()}, zone


def padded(image, filled, passes=8):
    """Bleed chart colours into the gutters so lower mips do not pick up black."""
    image = image.copy(); filled = filled.copy()
    for _ in range(passes):
        total = np.zeros_like(image); count = np.zeros(filled.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            total += np.roll(image * filled[..., None], (dy, dx), (0, 1)); count += np.roll(filled, (dy, dx), (0, 1))
        grow = ~filled & (count > 0); image[grow] = total[grow] / count[grow][:, None]; filled |= grow
    return image


def vertex_rows(tri, normal, uv):
    """Welded [position normal uv tangent] rows and triangle indices for one housing."""
    corners = np.column_stack([tri.reshape(-1, 3), normal.reshape(-1, 3), uv.reshape(-1, 2)])
    data, index = np.unique(np.round(corners, 6), axis=0, return_inverse=True); index = index.reshape(-1, 3)
    tangent = np.zeros((len(data), 3))
    for face in index:
        p = data[face, :3]; t = data[face, 6:8]; a, b = t[1] - t[0], t[2] - t[0]; det = a[0] * b[1] - b[0] * a[1]
        if abs(det) > 1e-12:
            tangent[face] += ((p[1] - p[0]) * b[1] - (p[2] - p[0]) * a[1]) / det
    tangent -= data[:, 3:6] * (tangent * data[:, 3:6]).sum(1)[:, None]
    # Boolean slivers can have zero UV area; their corners take any direction in the surface.
    lost = np.linalg.norm(tangent, axis=1) < 1e-9; n = data[lost, 3:6]
    spare = np.cross(n, np.where((np.abs(n[:, 1:2]) < .9), (0., 1, 0), (1., 0, 0)))
    tangent[lost] = spare; assert lost.mean() < .05, ('too many housing vertices without a tangent', int(lost.sum()))
    return np.column_stack([data, unit_vectors(tangent)]), index


def stage_base(unit, work):
    """The unit's mesh and skeleton before the weapon rig and before any housing."""
    key = f'Assets/ModelFixes/{unit}.mesh'
    revision = json.loads((ROOT / 'References/WeaponRigs/models.json').read_text())['source_revision']
    proc = subprocess.run(['git', 'show', f'{revision}:{key}'], cwd=ROOT, capture_output=True)
    assert proc.returncode == 0, (key, 'is not in the weapon-rig source revision', revision)
    (work / 'base.mesh').write_bytes(proc.stdout); mesh = shared.read_mesh(work / 'base.mesh')
    assert not any(s.material_name == unit + '_nacjet' for s in mesh.submesh_list), 'the base stage already carries a housing'
    folders = (ROOT / 'Assets/ModelFixes', ROOT / 'Assets/Models', wr.GAME / 'BZ_ASSETS/common/models')
    skeleton = next((f / mesh.skeleton_name for f in folders if (f / mesh.skeleton_name).is_file()), None)
    if skeleton is None:  # stock skeletons sit in faction subfolders
        skeleton = next(p for p in folders[2].rglob('*.skeleton') if p.name.lower() == mesh.skeleton_name.lower())
    return mesh, wr.read_skeleton(skeleton), revision


def material_block(material):
    lines = [f'material {material} : CR_BZBase', '{']
    lines += [f'\tset_texture_alias {alias} {material}_{key}.dds' for alias, key in (('DiffuseMap', 'D'), ('NormalMap', 'N'), ('SpecularMap', 'S'), ('EmissiveMap', 'E'))]
    return lines + ['', '\tset $diffuse "1 1 1"', '\tset $ambient "1 1 1"', '\tset $specular ".7 .7 .7"', '\tset $shininess "127"', '\tset $glow "1 1 1"', '}', '']


def ship(unit, material, work):
    """Install the housing as the unit's pre-rig stage: mesh, textures and material block."""
    raw = (work / (unit + '.mesh')).read_bytes()
    assert not ogrelayout.mixed_skinned_submeshes(raw), 'the stage mesh must keep the stock two-stream layout'
    (ROOT / 'Assets/ModelFixes' / (unit + '.mesh')).write_bytes(raw)
    for key in 'DNSE':
        shutil.copyfile(work / f'{material}_{key}.dds', ROOT / 'Assets/Textures' / f'{material}_{key}.dds')
    path = ROOT / 'Materials' / (unit + '.material'); text = path.read_bytes().decode()
    block = '\r\n'.join(material_block(material))
    old = re.compile(r'^material[ \t]+' + re.escape(material) + r'[ \t]*:.*?^\}\r?\n', re.S | re.M)
    text = old.sub(lambda m: block, text) if old.search(text) else text.rstrip() + '\r\n\r\n\r\n' + block
    path.write_bytes(text.encode())
    return hashlib.sha256(raw).hexdigest()


def preview_mesh(mesh, material, data, faces, owner, dest):
    """Append the housings to the unit mesh as one submesh, each rigid on its emitter's bone."""
    data = data.astype('<f4'); assert len(data) < 65536
    before = [(s.material_name, s.vertex_data.vertex_count) for s in mesh.submesh_list]
    sub = mesh.create_submesh(); sub.material_name = material; sub.index_count = faces.size; sub.indices_32_bit = False
    sub.set_index_buffer(faces.astype('<u2').tobytes()); ogrelayout.fill_vertex_data(sub.create_vertex_data(len(data)), data)
    for i, bone in enumerate(owner):
        sub.create_bone_assignment(i, int(bone), 1.)
    out = io.BytesIO(); oms.MeshSerializer(out).write(mesh); dest.write_bytes(out.getvalue())
    check = shared.read_mesh(dest); new = check.submesh_list[-1]
    assert [(s.material_name, s.vertex_data.vertex_count) for s in check.submesh_list] == before + [(material, len(data))]
    assert sorted((a.vertex_index, a.bone_index) for a in new.bone_assignments()) == list(zip(range(len(data)), owner.tolist()))
    assert np.allclose(shared.values(new.vertex_data, VES.POSITION), data[:, :3])


def ahead(tri, origin, direction):
    """Distance to the first triangle a ray from origin hits, or None."""
    e1 = tri[:, 1] - tri[:, 0]; e2 = tri[:, 2] - tri[:, 0]; h = np.cross(direction, e2); a = (e1 * h).sum(1)
    ok = np.abs(a) > 1e-12; f = 1 / np.where(ok, a, 1); s = origin - tri[:, 0]; u = f * (s * h).sum(1); q = np.cross(s, e1)
    v = f * (direction * q).sum(1); d = f * (e2 * q).sum(1); hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (d > 1e-4)
    return float(d[hit].min()) if hit.any() else None


def group(cfg, jets, mesh):
    """Housings to build: emitters that seat alike (same shape, same skin under the pod, as it
    is or mirrored) share one solid; the first of each group is the one it is built on. An
    emitter whose flame runs into mesh within half a metre sits in modelled geometry (a duct
    or nozzle the author drew) and gets no housing; it is flagged instead."""
    out = []; whole = hull(mesh)[0]
    for jet in jets:
        blocked = ahead(whole, np.array(jet['emit']), -np.array(jet.get('axes', np.eye(3)))[:, 1])
        if blocked is not None and blocked < .5:
            jet['skipped'] = f'sits in modelled geometry: mesh {blocked:.3f} m along the flame, no housing'; continue
        shape = next((s for pattern, s in cfg.get('also', ()) if re.search(pattern, jet['part'], re.I)), cfg['shape'])
        skin = hull(mesh, jet.get('skin', jet['bone']))[0]
        for h in out:
            mirror = jet['emit'][0] * h['centre'][0] < 0
            if h['shape'] is shape:
                try:
                    _, error, seat = underside(to_build(skin, jet, h['centre'], mirror), h['centre'], shape, h['fit'])
                except AssertionError:
                    continue
                if error < shape['bury'] * .5 and abs(seat['cover'] - h['seat']['cover']) < .08 and not seat['pokes']:
                    h['jets'].append((jet, mirror)); break
        else:  # its own solid, built on the +X side so one CONFIG offset serves both sides
            mirror = jet['emit'][0] < -1e-3; centre = np.array(jet['emit']) * ((-1., 1, 1) if mirror else (1., 1, 1))
            fit, error, seat = underside(to_build(skin, jet, centre, mirror), centre, shape)
            out.append(dict(shape=shape, jets=[(jet, mirror)], centre=centre.tolist(), fit=fit, error=error, seat=seat))
    assert out, ('every emit point sits in modelled geometry', [j['skipped'] for j in jets])
    return out


def posed_parts(mesh, pose):
    """Every submesh in the VDF pose: (material, positions, normals, uvs, triangles)."""
    out = []
    for sub in mesh.submesh_list:
        vd = sub.vertex_data; p = shared.values(vd, VES.POSITION).astype(float); n = shared.values(vd, VES.NORMAL).astype(float)
        owner = np.full(len(p), -1); weight = np.zeros(len(p))
        for a in sub.bone_assignments():
            if a.weight > weight[a.vertex_index]:
                weight[a.vertex_index] = a.weight; owner[a.vertex_index] = a.bone_index
        for bone in np.unique(owner[owner >= 0]):
            D, shift = pose[bone]; sel = owner == bone; p[sel] = p[sel] @ D.T + shift; n[sel] = n[sel] @ D.T
        out.append((sub.material_name, p, n, shared.values(vd, VES.TEXTURE_COORDINATES), np.array(sub.index_array).reshape(-1, 3)))
    return out


def notes_for(jets, housings, solids):
    """Plain-language flags for the receipt and the review sheets."""
    out = [f"{j['part']}: {j['estimate']}" for j in jets if 'estimate' in j]
    out += [f"{j['part']}: {j['skipped']}" for j in jets if 'skipped' in j]
    out += [f"{j['part']}: class 75 flame part" + (f", rides the bone of {j['rides']}" if 'rides' in j else '') for j in jets if j.get('source')]
    for h, solid in zip(housings, solids):
        seat = solid.get('seated'); name = h['jets'][0][0]['part']
        if not seat:
            continue
        if seat['inside'] > 0:
            out.append(f"{name}: emit point is {seat['gap']:+.3f} m from the skin (datum); the nozzle hangs {seat['inside']:.2f} m lower so its throat stays buried, and the flame starts above the throat")
        elif seat['gap'] > .06 * h['shape']['scale']:
            out.append(f"{name}: emit point hangs {seat['gap']:.2f} m below the skin; the pod is deepened to carry the nozzle there")
        if seat['cover'] < .999:
            out.append(f"{name}: only {seat['cover']:.0%} of the pod footprint has skin above it (edge of the part); the rest of the pod roof shows")
        if any(h['shape'].get('offset', (0, 0))):
            out.append(f"{name}: pod body offset {h['shape']['offset']} m (x, z) from the emit point to reach solid skin")
    return out


def blender(script, *args):
    result = subprocess.run([str(BLENDER), '-b', '--factory-startup', '--python-exit-code', '1', '--python', str(ROOT / 'Tools' / script), '--', *map(str, args)],
                            capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout[-3000:] + result.stderr[-3000:])
    return result.stdout


def sheet(images, captions, dest, columns, footer=()):
    """Captioned contact sheet of same-sized images, with optional note lines underneath."""
    font = ImageFont.truetype('arial.ttf', 20); w, h = images[0].size; rows = -(-len(images) // columns)
    out = Image.new('RGB', (w * columns, (h + 34) * rows + 28 * len(footer)), (24, 26, 28))
    for i, (image, caption) in enumerate(zip(images, captions)):
        x, y = i % columns * w, i // columns * (h + 34)
        out.paste(image.convert('RGB').resize((w, h)), (x, y)); ImageDraw.Draw(out).text((x + 8, y + h + 5), caption, fill=(232, 232, 226), font=font)
    for i, line in enumerate(footer):
        ImageDraw.Draw(out).text((8, (h + 34) * rows + 28 * i + 2), line, fill=(255, 214, 120), font=font)
    out.save(dest, quality=90)


def review_dir(unit):
    """Shipped units keep their sheets in the repository; previews stay local."""
    shipped = (ROOT / 'References/NacelleJets' / unit / 'build.json').is_file()
    return ROOT / ('References/NacelleJets/review' if shipped else 'Local/NacelleJets/review-rollout')


def build(unit, render, shipped=False):
    cfg = CONFIG[unit]; faction = FACTIONS[cfg['faction']]; material = unit + '_nacjet'
    work = ROOT / 'Local/NacelleJets' / unit; review = review_dir(unit)
    work.mkdir(parents=True, exist_ok=True); review.mkdir(parents=True, exist_ok=True)
    mesh, skeleton, revision = stage_base(unit, work)
    jets, pose = emitters(unit, skeleton, mesh); housings = group(cfg, jets, mesh)
    paint, source = paint_colour(mesh, housings[0]['jets'][0][0]['bone'])
    cells = math.ceil(math.sqrt(len(housings))); atlas = {}; data, faces, owner, solids, counts = [], [], [], [], []
    for n, h in enumerate(housings):
        ref = h['jets'][0][0]; name = 'solid' if len(housings) == 1 else 'solid%d' % n
        solid = solid_config(h['shape'], h['centre'], h['fit'], h['seat']); (work / (name + '.json')).write_text(json.dumps(solid, indent=1))
        log = blender('nacellejet_blender.py', work / (name + '.json'), work / (name + '.npz'))
        print(''.join(line + '\n' for line in log.splitlines() if line.startswith(('boolean', 'nacelle'))), end='')
        npz = np.load(work / (name + '.npz')); tris = npz['tris']
        tri = npz['positions'][tris]; normal = npz['normals'][tris]; uv = npz['uvs'][tris] * (1, -1) + (0, 1)  # Ogre v runs down
        tag = tag_faces(tri, solid)
        images, _ = textures(unit, tri, uv, tag, solid, cfg.get('stripe') or h['shape']['stripe'], paint, faction)
        rows, index = vertex_rows(tri, normal, uv)
        if cells > 1:  # each solid gets its own cell of the shared maps
            rows[:, 6:8] = (rows[:, 6:8] + (n % cells, n // cells)) / cells
        for key, image in images.items():
            if cells > 1:
                atlas.setdefault(key, Image.new('RGB', (SIZE, SIZE), image.getpixel((0, 0))))
                atlas[key].paste(image.resize((SIZE // cells,) * 2, Image.LANCZOS), (n % cells * (SIZE // cells), n // cells * (SIZE // cells)))
            else:
                atlas[key] = image
        for jet, mirror in h['jets']:
            start = sum(len(d) for d in data); data.append(instance(rows, jet, h['centre'], mirror))
            faces.append((index[:, ::-1] if mirror else index) + start); owner.append(np.full(len(rows), jet['bone']))
        solids.append(solid); counts.append(dict(vertices=len(rows), triangles=len(index), zones={k: int((tag == v).sum()) for k, v in
                      (('paint', PAINT), ('bell', BELL), ('lip', LIP), ('groove', GROOVE), ('bore', BORE), ('throat', THROAT), ('vent', VENT))}))
        print(unit, ref['part'], 'housing', len(rows), 'vertices', len(index), 'triangles x', len(h['jets']), '; paint', [round(c) for c in paint],
              'underside fit error %.3f' % h['error'], 'seat', {k: round(v, 3) for k, v in solid.get('seated', h['seat']).items()})
    images = atlas
    for key, image in images.items():
        save_bc(image, work / f'{material}_{key}.dds'); image.save(work / f'{material}_{key}.png')
    (work / (material + '.material')).write_text('\n'.join(['import * from "CR_BZBase.material"', ''] + material_block(material)), newline='\n')
    preview_mesh(mesh, material, np.concatenate(data), np.concatenate(faces), np.concatenate(owner), work / (unit + '.mesh'))
    first = housings[0]; keep = ('part', 'bone', 'skin', 'pivot', 'emit', 'axes', 'source', 'rides', 'estimate', 'skipped')
    receipt = dict(unit=unit, faction=cfg['faction'], material=material, emitters=[{k: j[k] for k in keep if k in j} for j in jets],
                   flameDirection=[0, -1, 0], baseRevision=revision,
                   wingUnderside=dict(heightAtEmit=first['fit'][0], slopePerMetreOfChord=first['fit'][1], maxError=first['error']), paint=paint,
                   paintSource=source.relative_to(ROOT).as_posix() if source.is_relative_to(ROOT) else source.name,
                   housing=counts[0], shape=first['shape'], stripe=cfg.get('stripe') or first['shape']['stripe'])
    notes = notes_for(jets, housings, solids)
    if first['shape'].get('auto'):  # fitted shapes: how each solid seats, and who carries it
        receipt.update(flameDirection='-y of each emitter frame', notes=notes, housings=[
            dict(counts[n], parts=[j['part'] for j, _ in h['jets']], mirrored=[m for _, m in h['jets']], underside=h['fit'], maxError=h['error'],
                 seated=solids[n]['seated'], shape=h['shape']) for n, h in enumerate(housings)])
    (work / 'preview.json').write_text(json.dumps(receipt, indent=2) + '\n', newline='\n')
    if shipped:  # a preview run leaves the tracked receipt alone
        receipt['stageMesh'] = ship(unit, material, work)  # sha256 of the pre-rig Assets/ModelFixes mesh
        record = ROOT / 'References/NacelleJets' / unit / 'build.json'; record.parent.mkdir(exist_ok=True)
        record.write_text(json.dumps(receipt, indent=2) + '\n', newline='\n')
    for note in notes:
        print(unit, 'note:', note)
    if not render:
        return
    # Hand the renderer plain arrays, in the VDF pose: it only draws.
    parts = []; everything = []
    for i, (name, positions, normals, uvs, tris) in enumerate(posed_parts(shared.read_mesh(work / (unit + '.mesh')), pose)):
        if 'glass' in name.lower():
            continue
        file = work / f'part{i}.npz'; own = name == material; everything.append(positions)
        np.savez(file, positions=positions, normals=normals, uvs=uvs, tris=tris)
        texture = None if own else texture_path(name)
        if texture:
            Image.open(texture).convert('RGB').save(work / f'part{i}_D.png'); texture = work / f'part{i}_D.png'
        parts.append(dict(mesh=str(file), housing=own, diffuse=str(work / f'{material}_D.png') if own else texture and str(texture),
                          emissive=str(work / f'{material}_E.png') if own else None, normal=str(work / f'{material}_N.png') if own else None))
    points = np.array([j['posed']['emit'] for j in jets]); middle = points.mean(0); spread = float(np.linalg.norm(points - middle, axis=1).max())
    flame = unit_vectors(np.array([j['posed']['flame'] for j in jets]).mean(0)); everything = np.concatenate(everything)
    centre = (everything.min(0) + everything.max(0)) / 2; radius = float(np.linalg.norm(everything.max(0) - everything.min(0))) / 2
    scale = first['shape'].get('scale', 1.); away = unit_vectors(np.array((3.6, -1.8, -4.4)))
    views = [dict(file='emit-below', eye=list(middle + flame * 8), target=list(middle), ortho=max(3.4, 2 * spread + 1.9 * scale), marker=True, flame=False, housing=True),
             dict(file='craft', eye=list(centre + away * radius * 2), target=list(centre), fov=38, marker=False, flame=True, housing=True),
             dict(file='contact', eye=list(middle + away * max(4., spread * 2.6 + 3 * scale)), target=list(middle), fov=38, marker=True, flame=False, housing=True,
                  markerScale=max(1., (spread * 2.6 + 3 * scale) / 5))]
    close = [('below', (1., -1.1, -1.2)), ('outboard', (1.9, -.36, .45)), ('front', (.3, -.65, 1.75))]
    for n, h in enumerate(housings):  # close-ups ride the build frame of each solid's first emitter
        ref = h['jets'][0][0]; e = np.array(ref['posed']['emit']); Q = np.array(ref['posed']['axes']); size = h['shape'].get('scale', 1.)
        side = np.array((-1. if e[0] < -1e-3 else 1., 1, 1)); at = lambda v: list(e + Q @ (np.array(v) * side * size))
        views += [dict(file=f'flame-before{n}', eye=at((1.9, -.75, -2.3)), target=at((0, -.25, 0)), fov=38, marker=True, flame=True, housing=False),
                  dict(file=f'flame-after{n}', eye=at((1.9, -.75, -2.3)), target=at((0, -.25, 0)), fov=38, marker=True, flame=True, housing=True)]
        views += [dict(file=f'clay-{name}{n}', eye=at(eye), target=at((0, -.02, 0)), fov=32, marker=False, flame=False, housing=True, clay=True) for name, eye in close]
        views += [dict(file=f'paint-{name}{n}', eye=at(eye), target=at((0, -.02, 0)), fov=32, marker=False, flame=False, housing=True) for name, eye in close]
    (work / 'scene.json').write_text(json.dumps(dict(parts=parts, out=str(work), emit=points.tolist(), flameDir=[j['posed']['flame'] for j in jets], views=views,
                                                     flame=dict(halfWidth=.2, length=.9), size=[960, 600]), indent=1))
    blender('nacellejet_render.py', work / 'scene.json')
    shot = lambda name: Image.open(work / (name + '.png')); every = range(len(housings))
    where = '; '.join('%s (%.3f, %.3f, %.3f)' % (j['part'], *j['posed']['emit']) for j in jets)
    sheet([shot('emit-below'), shot('craft')] + [shot(f'flame-{k}{n}') for n in every for k in ('before', 'after')],
          ['Against the flame: magenta dot = engine flame emit point', 'All housings, flame cones drawn (length illustrative)']
          + ['Stock skin: the jet starts here (cone = flame at full throttle)', 'With the housing: the same emit point now sits in the nozzle bore'] * len(housings),
          review / f'{unit}-emit.jpg', 2, [where] + notes)
    sheet([shot(f'clay-{name}{n}') for n in every for name, _ in close], ['Mesh from below', 'Mesh from outboard', 'Mesh from the nose side'] * len(housings), review / f'{unit}-mesh.jpg', 3)
    sheet([shot(f'paint-{name}{n}') for n in every for name, _ in close], ['Textured, from below', 'Textured, from outboard', 'Textured, from the nose side'] * len(housings),
          review / f'{unit}-textured.jpg', 3)
    sheet([images[k].resize((480, 480)) for k in 'DNSE'], [f'{material}_D diffuse', f'{material}_N normal', f'{material}_S specular', f'{material}_E emissive'],
          review / f'{unit}-textures.jpg', 4)


def contact(units):
    """One sheet per faction: every unit's textured rear/underside view with the emit points
    marked, and a close-up of its first housing inset. Uses the renders of earlier runs."""
    for faction in dict.fromkeys(CONFIG[u]['faction'] for u in units):
        tiles, captions = [], []
        for u in units:
            work = ROOT / 'Local/NacelleJets' / u
            if CONFIG[u]['faction'] != faction or not (work / 'contact.png').is_file():
                continue
            tile = Image.open(work / 'contact.png').convert('RGB'); inset = Image.open(work / 'paint-below0.png').convert('RGB').resize((384, 240))
            tile.paste(inset, (tile.width - 392, tile.height - 248)); ImageDraw.Draw(tile).rectangle([tile.width - 393, tile.height - 249, tile.width - 8, tile.height - 8], outline=(255, 255, 255))
            receipt = json.loads((work / 'preview.json').read_text()); tiles.append(tile)
            captions.append(f"{u}: {len(receipt['emitters'])} emit point(s), scale {receipt['shape'].get('scale', 1):g}" + (' (see notes)' if receipt.get('notes') else ''))
        if tiles:
            dest = ROOT / 'Local/NacelleJets/review-rollout' / f'contact-{faction}.jpg'; dest.parent.mkdir(parents=True, exist_ok=True)
            sheet(tiles, captions, dest, 3); print('contact sheet', dest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--units', nargs='*', default=list(CONFIG)); parser.add_argument('--skip-render', action='store_true')
    parser.add_argument('--ship', action='store_true', help='install the housing as the pre-rig stage (mesh, textures, material)')
    parser.add_argument('--contact', action='store_true', help='only compose the per-faction contact sheets from finished renders')
    options = parser.parse_args()
    if options.contact:
        contact(options.units)
    else:
        for name in options.units:
            build(name, not options.skip_render, options.ship)
