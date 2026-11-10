"""Hardpoint mount kit: a rocket pod, a cannon stub and a mortar tube welded onto a unit's hull,
with the weapon hardpoint moved to the mount's muzzle.

    python Tools/Build-HardpointMounts.py [--units avfigh ...] [--skip-render] [--ship]

Each piece is built once in its own attach frame (Tools/hardpointmount_blender.py: x right,
y the surface normal, z forward; its saddle buried in the hull below y = 0), so all units share
one UV layout and paint mask per piece. A unit only gives the attach frame (a point near the
hull, the surface normal, the fire direction), a scale, the body part the mount sits on and its
faction. The build:

  - starts from the unit's mesh before any mount (CONFIG base revision),
  - seats the piece on the hull (a ray along -normal), checks the saddle is buried across its
    whole footprint and that nothing of the hull or glass lies ahead of the muzzle,
  - appends it as one rigid submesh <unit>_hpmount on the owner bone, painted with the unit's
    own hull colour (sampled from its atlas) and faction stripe,
  - records References/HardpointMounts/<unit>.json and moves the hardpoint part to the muzzle
    in References/Hardpoints/<unit>.json (applied by Tools/Build-UnitAnimSlots.py),
  - renders before/after sheets and the kit sheet in Local/HardpointMounts/review.

--ship installs the mesh, the four <unit>_hpmount textures and the material block. For a rigged
unit (References/WeaponRigs/models.json) the mesh is the pre-rig stage: commit, pin it in
stage_revisions and re-run the rig (References/HardpointMounts/README is not needed: the steps
are the same as Build-NacelleJets.py --ship).
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, math, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'Tools'))
_spec = importlib.util.spec_from_file_location('nacellejets', ROOT / 'Tools/Build-NacelleJets.py')
nj = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(nj)
from bcdds import save_bc

wr, shared, legacy, VES, S = nj.wr, nj.shared, nj.legacy, nj.VES, nj.S
LOCAL = ROOT / 'Local/HardpointMounts'
RECEIPTS = ROOT / 'References/HardpointMounts'
PAINT, SADDLE, METAL, BORE, ACCENT = range(5)
TRIANGLE_CAP = 2000
INSET = .04  # the hardpoint sits this far (x scale) inside the muzzle, so a bone stub stays in the bore
NEUTRAL = dict(paint=(150., 152, 150), faction=dict(stripe=(196, 196, 190), glow=(0, 0, 0)))

# at: a point on or near the hull (Ogre mesh space in the VDF pose); the build seats the piece
# on the hull below it along -normal. fire: forward of the piece (made perpendicular to normal).
# base: the git revision of the unit's mesh before any mount.
CONFIG = {
    'avfigh': dict(piece='rocket', part='ARA11Gr1', owner='ARA11BDA', faction='nsdf', scale=.6,
                   at=(.46, .29, 1.4), normal=(.58, -.82, 0), fire=(0., 0, 1), fireThrough=('ARA11rof',),
                   base='628a1fa1646242e5405ce31f26dbf31f9f955abc'),
    'avhraz': dict(piece='cannon', part='Ahr11Gc1', owner='ahr11bda', faction='nsdf', scale=1.3,
                   at=(-1., 1.5, 2.3), normal=(-.99, 0, .11), fire=(0., 0, 1), base='75fb226a0be4ea9e885c6c055bd1be31753040bd'),
    'bvhraz': dict(piece='cannon', part='bhr11Gc1', owner='bhr11bda', faction='blackdogs', scale=1.3,
                   at=(-1., 1.5, 2.3), normal=(-.99, 0, .11), fire=(0., 0, 1), base='75fb226a0be4ea9e885c6c055bd1be31753040bd'),
    'bvrdev': dict(piece='mortar', part='brd11GM1', owner='brd11bda', faction='blackdogs', scale=1.,
                   at=(.9, 1.36, -.4), normal=(.29, .96, 0), fire=(0., 0, 1), base='f09fec92f1d6da20facde0d095c45f19a913c866'),
    'svfigh': dict(piece='rocket', part='SFL11GR1', owner='SFL11ROR', faction='cca', scale=.5, rollViews=('SFL11ROR',),
                   at=(0., .8, 2.35), normal=(0, .96, .27), fire=(0., 0, 1), base='628a1fa1646242e5405ce31f26dbf31f9f955abc'),
}
# avfigh carries its pod on the main body (ARA11BDA), on the +x lower sloped side facet (normal
# (.58, -.82, 0)) behind the rolling nose, so it does not roll with the nose (owner's call). Scale .6
# is the largest that keeps the pod above the hull's lowest point there with a muzzle low enough
# (y .19) to fire under the nose. fireThrough: the nose (class 66, +-23 deg) still dips into the
# pod's line of fire at -23..-18 deg (recorded as checks.parts.lineOfFireCrossedBy); no seat on this
# facet clears it at all angles and the ground at once. Stock Gc1's own line already crosses the nose at rest.
# Kit sheet only: the same pod upright on the left wing, a second mounting angle.
WING = dict(CONFIG['avfigh'], scale=.85, at=(-1.4, .95, -1.45), normal=(-.29, .93, -.23))


def without_mount(blob, unit):
    """Mesh bytes with the unit's trailing <unit>_hpmount submesh removed (toolkit round trip), so
    contracts that pin a unit's pre-mount mesh byte-for-byte can still check every original byte."""
    import io
    mesh = nj.oms.MeshSerializer(io.BytesIO(blob)).read()
    names = [s.material_name for s in mesh.submesh_list]
    assert names.count(f'{unit}_hpmount') == 1 and names[-1] == f'{unit}_hpmount', names
    mesh.submesh_list.pop()
    out = io.BytesIO(); nj.oms.MeshSerializer(out).write(mesh)
    return out.getvalue()


def without_mount_material(text, unit):
    """Material script text with the unit's appended `material <unit>_hpmount` block removed."""
    import re
    stripped, n = re.subn(rf'(?m)^material {unit}_hpmount : \S+\n\{{[^{{}}]*\}}\n*', '', text)
    assert n == 1, f'{unit}_hpmount material block'
    return stripped


def piece(name, cache={}):
    """The kit piece in its own frame (Tools/hardpointmount_blender.py), built once per run."""
    if name not in cache:
        out = LOCAL / 'kit' / f'{name}.npz'; out.parent.mkdir(parents=True, exist_ok=True)
        nj.blender('hardpointmount_blender.py', name, out); d = dict(np.load(out))
        d['uvs'] = d['uvs'] * (1, -1) + (0, 1)  # Ogre v runs down
        d['tri'] = d['positions'][d['tris']]; d['norm'] = d['normals'][d['tris']]; d['uv'] = d['uvs'][d['tris']]
        assert len(d['tris']) <= TRIANGLE_CAP, (name, len(d['tris']), 'triangles: over the kit cap')
        cache[name] = d
    return cache[name]


def load(unit, cfg):
    """The unit's mesh before any mount, its skeleton, the shipped VDF parts and the VDF pose."""
    work = LOCAL / unit; work.mkdir(parents=True, exist_ok=True)
    blob = subprocess.run(['git', 'show', '--no-textconv', f"{cfg['base']}:Assets/ModelFixes/{unit}.mesh"], cwd=ROOT, capture_output=True, check=True).stdout
    (work / 'base.mesh').write_bytes(blob); mesh = shared.read_mesh(work / 'base.mesh')
    assert not any(s.material_name.endswith('_hpmount') for s in mesh.submesh_list), (unit, 'base mesh already carries a mount')
    folders = (ROOT / 'Assets/ModelFixes', ROOT / 'Assets/Models', wr.GAME / 'BZ_ASSETS/common/models')
    sk = next((f / mesh.skeleton_name for f in folders if (f / mesh.skeleton_name).is_file()), None)
    sk = sk or next(p for p in folders[2].rglob('*.skeleton') if p.name.lower() == mesh.skeleton_name.lower())
    skeleton = wr.read_skeleton(sk)
    vdf = ROOT / f'Assets/ModelFixes/{unit}.vdf'  # no CR VDF yet: the stock one (Build-UnitAnimSlots makes the override)
    parts = legacy.read_vdf((vdf if vdf.exists() else wr.GAME / 'StockODFFiles' / f'{unit}.vdf').read_bytes()).band(0)
    W, by = nj.vdf_world(parts)
    return work, mesh, skeleton, parts, W, by, nj.vdf_pose(skeleton, W)


def posed_hull(mesh, pose, glass=False):
    """Posed triangles of the hull (no mount; glass only when asked: the line of fire)."""
    out = [p[t] for mat, p, n, uv, t in nj.posed_parts(mesh, pose)
           if not mat.endswith('_hpmount') and (glass or 'glass' not in mat.lower())]
    return np.concatenate(out)


def frame(normal, fire):
    """Rows right, up (the surface normal), front of the attach frame, Ogre mesh space."""
    n = nj.unit_vectors(np.array(normal, float)); f = np.array(fire, float); f = nj.unit_vectors(f - n * (f @ n))
    return np.array([np.cross(n, f), n, f])


def place(cfg, hull):
    """Seat the attach frame on the hull: the surface point under cfg['at'] along -normal."""
    M = frame(cfg['normal'], cfg['fire']); start = np.array(cfg['at'], float) + M[1] * 1.5
    d = nj.ahead(hull, start, -M[1]); assert d is not None, ('no hull under', cfg['at'])
    seat = start - M[1] * d; assert np.linalg.norm(seat - cfg['at']) < .35, ('hull surface far from the attach point', seat.round(3), cfg['at'])
    return seat, M


def to_posed(points, seat, M, scale):
    return np.asarray(points) * scale @ M + seat


def checks(kit, seat, M, scale, hull, glass_hull):
    """Saddle buried across its footprint, a clear line of fire; returns the measurements."""
    tri = kit['tri']; zone = kit['zone']; bury = float(kit['bury'])
    foot = np.unique(np.round(tri[zone == SADDLE].reshape(-1, 3), 6), axis=0); foot = foot[foot[:, 1] < -bury + 1e-4]
    assert len(foot) >= 4, 'saddle has no buried footprint'
    depth = []
    for p in to_posed(foot, seat, M, scale):  # from the saddle floor outward: the hull skin must lie above it
        d = nj.ahead(hull, p, M[1]); depth.append(np.inf if d is None else d)
    depth = np.array(depth); top = float(tri[zone == SADDLE][..., 1].max()) * scale
    assert np.isfinite(depth).all(), ('saddle floor not under the hull everywhere: a floating corner', int((~np.isfinite(depth)).sum()))
    assert (depth < bury * scale + top - .005).all(), ('hull skin above the saddle top: the mount sinks too deep', depth.max())
    muzzle = to_posed(kit['muzzle'], seat, M, scale); fire = nj.unit_vectors(kit['fire'] @ M)
    side = np.cross(fire, M[0]); side = nj.unit_vectors(side)
    blocked = [nj.ahead(glass_hull, muzzle + fire * .01 + o, fire) for o in (0 * side, side * .03, -side * .03, M[0] * .03, -M[0] * .03)]
    assert all(b is None for b in blocked), ('hull or glass in front of the muzzle', blocked)
    ground = float(to_posed(kit['positions'], seat, M, scale)[:, 1].min() - hull[..., 1].min())
    assert ground >= -1e-4, ('mount hangs below the hull: it would touch the ground first', round(ground, 4))
    return dict(footprint=len(foot), skinAboveFloor=[float(depth.min()), float(depth.max())], saddleTop=top, muzzle=muzzle.tolist(), fire=fire.tolist(),
                groundClearance=round(ground, 4))


# Gimbal parts the engine moves (HoverCraft::UpdateGimbals, BZ1 1.5 all_decompiled.c:193563):
# class 66 rolls about its own z (:193638-193641), 67 pitches about its own x (:193659-193676),
# 68 rolls about its own z (:193688-193690). Every sweep uses +-cp.NOSE_ROLL_DEG (:194995/:195005);
# that is the 66 nose roll, the 67/68 amplitude is UNVERIFIED (same envelope assumed).
GIMBAL_AXIS = {66: 2, 67: 0, 68: 2}
# Another weapon's line of fire: forward rays from its hardpoint and 6 cm around it (a barrel's width).
GUN_RAYS = [np.array(o) for o in ((0, 0, 0.), (.06, 0, 0), (-.06, 0, 0), (0, .06, 0), (0, -.06, 0))]


def part_triangles(mesh, pose, skeleton, parts, skip=None):
    """Posed triangles (glass included) per VDF part name (lower case): a triangle goes to the
    dominant bone of its first vertex, and a bone that is not a VDF part to its nearest VDF ancestor."""
    names = {p.name.lower() for p in parts}; bones = {b.handle: b for b in skeleton.bones}
    def part_of(h):
        if h not in bones:  # no bone assignment: static, checked at rest only
            return '(unbound)'
        b = bones[h]
        while b.name.lower() not in names and b.parent is not None:
            b = bones[b.parent]
        return b.name.lower()
    out = {}
    for sub, (mat, p, n, uv, t) in zip(mesh.submesh_list, nj.posed_parts(mesh, pose)):
        if mat == skip:
            continue
        own = np.full(len(p), -1); w = np.zeros(len(p))
        for a in sub.bone_assignments():
            if a.weight > w[a.vertex_index]: w[a.vertex_index] = a.weight; own[a.vertex_index] = a.bone_index
        for h in np.unique(own[t[:, 0]]):
            out.setdefault(part_of(int(h)), []).append(p[t[own[t[:, 0]] == h]])
    return {k: np.concatenate(v) for k, v in out.items()}


def _rotation(axis, degrees):
    k = nj.unit_vectors(np.asarray(axis, float)); K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]]); a = math.radians(degrees)
    return np.eye(3) + math.sin(a) * K + (1 - math.cos(a)) * K @ K


def part_clearance(mount, groups, parts, W, owner, seat, normal, saddle_top, muzzle, fire, own_part, fire_through=()):
    """The mount (posed triangles) against every other part of the unit:
      - at rest it touches no triangle of a part other than its owner,
      - above its saddle (beyond the buried root) it touches no triangle of its owner,
      - it is not in the forward line of fire of the unit's other weapon hardpoints (G?n parts),
      - for each gimbal part (66/67/68) and its children, swept through +-cp.NOSE_ROLL_DEG:
        when the mount rides on it, the mount keeps cp.NOSE_CLEARANCE from all that does not move
        with it; otherwise that part keeps cp.NOSE_CLEARANCE from the mount and stays out of the
        mount's line of fire (5 rays) at every angle, unless the gimbal is in fire_through (the
        angles that cross it are still recorded).
    Returns (measurements, errors)."""
    import combatcockpits as cp, re
    owner = owner.lower(); errors = []; centre = mount.reshape(-1, 3).mean(0)
    guns = {}
    for p in parts:
        if re.search(r'g[a-z]\d$', p.name.lower()) and p.name.lower() != own_part.lower():
            hits = [nj.ahead(mount, W[p.name.lower()][1] * S + o, np.array((0, 0, 1.))) for o in GUN_RAYS]
            hits = [h for h in hits if h is not None]; d = min(hits) if hits else None
            guns[p.name] = None if d is None else round(float(d), 4)
            if d is not None:
                errors.append(f'mount sits in the line of fire of {p.name}, {d:.3f} m ahead')
    reach = np.linalg.norm(mount.reshape(-1, 3) - centre, axis=1).max()
    span = lambda tris: np.linalg.norm(tris - tris.mean(1, keepdims=True), axis=2).max(1)  # a big panel's edge can touch the mount far from its centroid
    near = lambda tris, pad: tris[np.linalg.norm(tris.mean(1) - centre, axis=1) - span(tris) < reach + pad]
    rest = {}
    for name, tris in sorted(groups.items()):
        if name in (owner, own_part.lower()) or not len(near(tris, .5)):  # own_part: the stock hardpoint's marker box, which the mount replaces
            continue
        rest[name] = round(float(cp.rotor_sweep(mount, near(tris, .5), np.zeros(3), (0, 0, 1.), [0.], .3).min()), 4)
        if rest[name] <= 0:
            errors.append(f'mount intersects {name} at rest')
    h = (mount - seat) @ normal; upper = mount[h.min(1) > saddle_top]
    hull = near(groups.get(owner, np.zeros((0, 3, 3))), .5)
    body = float(cp.rotor_sweep(upper, hull, np.zeros(3), (0, 0, 1.), [0.], .3).min()) if len(upper) and len(hull) else .3
    if body <= 0:
        errors.append(f'mount body (above its saddle) intersects its owner {owner}')
    angles = np.arange(-cp.NOSE_ROLL_DEG, cp.NOSE_ROLL_DEG + .5, 1.); sweep = {}; blocked = {}; low = None
    fire = nj.unit_vectors(np.asarray(fire, float)); side = nj.unit_vectors(np.cross(fire, normal)); up = nj.unit_vectors(np.cross(side, fire))
    rays = [np.asarray(muzzle) + fire * .01 + o for o in (0 * side, side * .03, -side * .03, up * .03, -up * .03)]
    for gimbal in (p for p in parts if p.klass in GIMBAL_AXIS):
        moving = {gimbal.name.lower()}
        while True:
            more = {p.name.lower() for p in parts if (p.parent or '').lower() in moving} - moving
            if not more:
                break
            moving |= more
        R, t = W[gimbal.name.lower()]; pivot = t * S; axis = nj.unit_vectors(R[GIMBAL_AXIS[gimbal.klass]] * S)
        if owner in moving:
            static = near(np.concatenate([v for k, v in groups.items() if k not in moving] + [np.zeros((0, 3, 3))]), 1.)
            gap = float(cp.rotor_sweep(mount, static, pivot, axis, angles, .2).min()) if len(static) else .2
            ground = min(float(((mount.reshape(-1, 3) - pivot) @ _rotation(axis, a).T + pivot)[:, 1].min()) for a in angles)
            low = round(ground - min(float(v[..., 1].min()) for v in groups.values()), 4)
        else:
            every = np.concatenate([groups[k] for k in moving if k in groups] + [np.zeros((0, 3, 3))])
            swing = 2 * math.sin(math.radians(cp.NOSE_ROLL_DEG) / 2) * np.linalg.norm(np.cross(every.mean(1) - pivot, axis), axis=1)
            tris = every[np.linalg.norm(every.mean(1) - centre, axis=1) - swing - span(every) < reach + 1.]
            gap = float(cp.rotor_sweep(tris, mount, pivot, axis, angles, .2).min()) if len(tris) else .2
            # the line of fire is tested against the whole swept part, however far ahead it is
            crossed = [float(a) for a in angles if len(every) and any(nj.ahead((every - pivot) @ _rotation(axis, a).T + pivot, r, fire) is not None for r in rays)]
            if crossed:
                blocked[gimbal.name] = [min(crossed), max(crossed), len(crossed)]
                if gimbal.name.lower() not in {f.lower() for f in fire_through}:
                    errors.append(f'{gimbal.name} (class {gimbal.klass}) crosses the line of fire at {len(crossed)} angles, {min(crossed):+.0f}..{max(crossed):+.0f} deg')
        sweep[gimbal.name] = round(gap, 4)
        if gap < cp.NOSE_CLEARANCE:
            errors.append(f'{gimbal.name} (class {gimbal.klass}) sweep: mount within {gap:.4f} m (need {cp.NOSE_CLEARANCE})')
    out = dict(restGap=rest, ownerBodyGap=round(body, 4), gunLines=guns, sweepDegrees=cp.NOSE_ROLL_DEG, sweepGap=sweep, lineOfFireCrossedBy=blocked)
    if low is not None:
        out['rolledGroundClearance'] = low
    return out, errors


def seat_paint(mesh, pose, seat, normal):
    """Paint and marking colour of the hull skin around the seat (not an atlas-wide average):
    area-weighted texels of the nearby faces that look along the attach normal. paint is the
    dominant calm colour; accent the median of the contrasting near-grey marking texels in a
    wider ring (the hull's own worn white on dark paint, its dark trim on pale paint)."""
    tris, uvs, paths = [], [], []
    for mat, p, n, uv, t in nj.posed_parts(mesh, pose):
        path = nj.texture_path(mat)
        if path and 'glass' not in mat.lower() and not mat.endswith('_hpmount'):
            tris.append(p[t]); uvs.append(uv[t]); paths += [path] * len(t)
    tri, uv, paths = np.concatenate(tris), np.concatenate(uvs), np.array([str(p) for p in paths])
    c = tri.mean(1); facing = nj.unit_vectors(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]))
    distance = np.linalg.norm(c - seat, axis=1); along = np.abs(facing @ normal)
    def texels(sel, count=4000):
        path = max(set(paths[sel]), key=list(paths[sel]).count); sel = sel & (paths == path)
        image = np.asarray(Image.open(path).convert('RGB'), float); h, w = image.shape[:2]
        area = np.linalg.norm(np.cross(tri[sel][:, 1] - tri[sel][:, 0], tri[sel][:, 2] - tri[sel][:, 0]), axis=1)
        pick = np.random.default_rng(1).choice(sel.sum(), count, p=area / area.sum()); weights = np.random.default_rng(2).dirichlet((1, 1, 1), count)
        s = (weights[..., None] * uv[sel][pick]).sum(1) % 1
        return image[(s[:, 1] * h).astype(int).clip(0, h - 1), (s[:, 0] * w).astype(int).clip(0, w - 1)], path
    for radius in (.45, .7, 1.):
        sel = (distance < radius) & (along > .5)
        if sel.sum() >= 8:
            break
    texel, path = texels(sel)
    calm = (texel.max(1) - texel.min(1) < 90) & (texel.max(1) > 20)  # not hazard trim or decals, not black gaps
    body = texel[calm] if calm.sum() >= .2 * len(texel) else texel
    key = (body // 24).astype(int) @ (1, 16, 256); body = body[key == np.bincount(key).argmax()]
    paint = np.median(body, 0)
    ring, _ = texels((distance < 1.6) & (along > .3), 12000)
    grey = (ring.max(1) - ring.min(1) < 40) & (ring.max(1) > 20)
    if paint.mean() < 110:  # dark paint: the marking is the hull's own worn pale
        mark = ring[grey & (ring.mean(1) > max(120., paint.mean() * 1.6))]
        fallback = np.clip(paint * 1.8, 0, 200)
    else:  # pale paint: the marking is the hull's own dark trim
        mark = ring[grey & (ring.mean(1) < paint.mean() * .45)]
        fallback = paint * .35
    accent = np.median(mark, 0) if len(mark) >= 40 else fallback
    return [float(v) for v in paint], [float(v) for v in accent], path, int(len(mark))


def textures(name, kit, paint, faction):
    """D/N/S/E for one piece in one palette. Lines follow the piece's own creases and zone
    borders, in its own frame (nj.mesh_edges); noise is seeded by name."""
    tri, uv, tag = kit['tri'], kit['uv'], kit['zone']; SIZE = nj.SIZE
    face, weight = nj.raster(uv); filled = face >= 0; zone = np.where(filled, tag[np.where(filled, face, 0)], -1)
    rng = np.random.default_rng(int(hashlib.sha256(name.encode()).hexdigest()[:8], 16))
    mottle = nj.blurred(rng.random((SIZE, SIZE)), 5); mottle = (mottle - mottle.mean()) / mottle.std()
    blotch = nj.blurred(rng.random((SIZE, SIZE)), 14); blotch = (blotch - blotch.mean()) / blotch.std()
    grain = rng.normal(0, 1, (SIZE, SIZE)); k = 4
    seam, wear, rivet = (Image.new('L', (SIZE * k,) * 2) for _ in range(3))
    for fi, corner, convex, border in nj.mesh_edges(tri, tag, 35):
        a, b, c = (uv[fi][(corner + j) % 3] * SIZE * k for j in range(3))
        if border or not convex:
            ImageDraw.Draw(seam).line([tuple(a), tuple(b)], fill=255, width=int(2.2 * k))
        if convex and tag[fi] != BORE:
            ImageDraw.Draw(wear).line([tuple(a), tuple(b)], fill=255, width=int(2.6 * k))
        pa, pb, pc = (tri[fi][(corner + j) % 3] for j in range(3)); length = np.linalg.norm(pb - pa)
        height = np.linalg.norm(np.cross(pb - pa, pc - pa)) / max(length, 1e-9)
        if tag[fi] == PAINT and convex and not border and length > .12 and height > .04:
            inset, count = .016 / height, int(length / .06)
            for s in (np.arange(count) + .5) / count:
                q = (a * (1 - s) + b * s) * (1 - inset) + c * inset; r = 1.5 * k
                ImageDraw.Draw(rivet).ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=255)
    down = lambda im: np.asarray(im.resize((SIZE, SIZE), Image.LANCZOS), float) / 255
    seam, wear, rivet = down(seam), down(wear), down(rivet)
    grime = nj.blurred(seam, 5); chipped = np.clip(nj.blurred(wear, 1.2) * (1.1 + .9 * mottle) - .25, 0, 1)
    paint = np.array(paint, float); body = paint * (1 + .07 * blotch[..., None] + .04 * mottle[..., None])
    colour = np.zeros((SIZE, SIZE, 3)); spec = np.zeros((SIZE, SIZE))
    for value, base, shine in ((PAINT, body, 46), (SADDLE, body * .78, 36), (METAL, np.array((68., 71, 76)) * (1 + .06 * mottle[..., None]), 120),
                               (BORE, np.array((22., 21, 22)) + 0 * body, 14), (ACCENT, np.array(faction['stripe'], float) * (1 + .05 * mottle[..., None]), 60)):
        mask = zone == value; colour[mask] = np.broadcast_to(base, colour.shape)[mask]; spec[mask] = np.broadcast_to(shine, spec.shape)[mask]
    worn = (chipped * np.isin(zone, (PAINT, SADDLE, ACCENT)))[..., None]
    colour = colour * (1 - worn) + np.array((148., 150, 146)) * worn
    colour *= ((1 - .5 * grime) * (1 - .7 * seam))[..., None] * (1 - .35 * rivet[..., None]) * (1 + .03 * grain[..., None])
    spec = (spec + 90 * worn[..., 0]) * (1 - .6 * seam)
    height = nj.blurred(rivet, .8) * .7 - nj.blurred(seam, .9)
    gy, gx = np.gradient(height); n = nj.unit_vectors(np.dstack([-gx * 3.5, -gy * 3.5, np.ones_like(gx)]))
    images = dict(D=colour, N=(n * .5 + .5) * 255, S=np.repeat(spec[..., None], 3, 2), E=np.zeros((SIZE, SIZE, 3)))
    return {key: Image.fromarray(np.uint8(np.clip(nj.padded(v, filled), 0, 255))) for key, v in images.items()}, zone


def save_textures(images, material, work):
    paths = {}
    for key, image in images.items():
        save_bc(image, work / f'{material}_{key}.dds'); image.save(work / f'{material}_{key}.png'); paths[key] = work / f'{material}_{key}.png'
    return paths


def hardpoint_entry(unit, cfg, by, W, point, receipt=None):
    """References/Hardpoints part: the hardpoint at point (Ogre, VDF pose), parented to the
    owner with the owner's own orientation (stock hardpoints carry an identity rotation)."""
    part, owner = by[cfg['part'].lower()], by[cfg['owner'].lower()]
    Rp, tp = W[owner.name.lower()]; t = (np.array(point) * S - tp) @ Rp.T
    path = ROOT / 'References/Hardpoints' / f'{unit}.json'
    receipt = receipt or (json.loads(path.read_text()) if path.exists() else None) or dict(
        note='Hardpoint alignment (Tools/Build-UnitAnimSlots.py apply_hardpoints). owner = the VDF part that carries the weapon geometry; parent must equal it (Tools/Test-UnitAnimSlots.py).',
        model=unit, base='stock', parts=[])
    old = next((p for p in receipt['parts'] if p['name'] == part.name), None)
    entry = dict(name=part.name, klass=part.klass, existing=True, was=old['was'] if old else part.parent, owner=owner.name, parent=owner.name,
                 matrix=[1., 0., 0., 0., 1., 0., 0., 0., 1.] +[round(float(v), 6) for v in t])
    receipt['parts'] = [p for p in receipt['parts'] if p['name'] != part.name] + [entry]
    return path, receipt


def mount_rows(kit, seat, M, scale, D, shift):
    """Welded vertex rows and indices of the piece, in the owner bone's bind space."""
    posed = to_posed(kit['tri'].reshape(-1, 3), seat, M, scale).reshape(-1, 3, 3)
    normal = nj.unit_vectors(kit['norm'] @ M)
    return nj.vertex_rows((posed - shift) @ D, normal @ D, kit['uv']), posed


def views_for(centre, radius, at, fire, normal, reach):
    """A 3/4 view of the whole unit and a close-up on the mount, from the side the mount faces."""
    side = 1. if normal[0] >= 0 else -1.; up = 1. if normal[1] >= -.5 else -1.
    v34 = nj.unit_vectors(np.array((side, .55 * up, 1.)))
    close = nj.unit_vectors(np.array(normal) * .9 + np.array((side * .7, 0, 0)) + np.array(fire) * .6)
    return [dict(file='three_quarter', eye=(centre + v34 * radius * 2.2).tolist(), target=centre.tolist(), fov=40),
            dict(file='close', eye=(np.array(at) + close * max(1.6, reach * 3)).tolist(), target=list(at), fov=40)]


def render(work, tag, parts, views, emit=(), fire=(), marks=()):
    scene = dict(out=str(work / tag), emit=[list(e) for e in emit], flameDir=[list(f) for f in fire], flame=dict(halfWidth=.025, length=1.6),
                 size=[900, 700], parts=parts, marks=list(marks),
                 views=[dict(v, marker=True, flame=bool(emit), housing=False) for v in views])
    (work / tag).mkdir(exist_ok=True); (work / tag / 'scene.json').write_text(json.dumps(scene))
    nj.blender('nacellejet_render.py', work / tag / 'scene.json')
    return [Image.open(work / tag / (v['file'] + '.png')) for v in views]


def gimbal_roll(skeleton, parts, W, name, degrees):
    """(bone handles moving with gimbal part `name` and its children, pivot, rotation) for hull_parts."""
    moving = {name.lower()}
    while more := {p.name.lower() for p in parts if (p.parent or '').lower() in moving} - moving:
        moving |= more
    names = {p.name.lower() for p in parts}; bones = {b.handle: b for b in skeleton.bones}
    def part_of(b):
        while b.name.lower() not in names and b.parent is not None:
            b = bones[b.parent]
        return b.name.lower()
    gimbal = next(p for p in parts if p.name.lower() == name.lower()); R, t = W[name.lower()]
    axis = nj.unit_vectors(R[GIMBAL_AXIS[gimbal.klass]] * S)
    return {h for h, b in bones.items() if part_of(b) in moving}, t * S, _rotation(axis, degrees)


def hull_parts(mesh, pose, work, tag, roll=None):
    out = []
    for i, (sub, (mat, p, n, uv, t)) in enumerate(zip(mesh.submesh_list, nj.posed_parts(mesh, pose))):
        if 'glass' in mat.lower() or mat.endswith('_hpmount'):
            continue
        if roll:
            handles, pivot, R = roll; own = np.full(len(p), -1); w = np.zeros(len(p))
            for a in sub.bone_assignments():
                if a.weight > w[a.vertex_index]: w[a.vertex_index] = a.weight; own[a.vertex_index] = a.bone_index
            moves = np.isin(own, list(handles)); p = p.copy(); n = n.copy()
            p[moves] = (p[moves] - pivot) @ R.T + pivot; n[moves] = n[moves] @ R.T
        np.savez(work / f'{tag}{i}.npz', positions=p, normals=n, uvs=uv, tris=t); tex = nj.texture_path(mat)
        out.append(dict(mesh=str(work / f'{tag}{i}.npz'), housing=False, diffuse=str(tex) if tex else None))
    return out


def mount_part(work, name, kit, seat, M, scale, tex):
    pts = to_posed(kit['positions'], seat, M, scale); nrm = nj.unit_vectors(kit['normals'] @ M)
    np.savez(work / f'{name}.npz', positions=pts, normals=nrm, uvs=kit['uvs'], tris=kit['tris'])
    return dict(mesh=str(work / f'{name}.npz'), housing=False, diffuse=str(tex['D']), normal=str(tex['N']))


def mirrored(cfg):
    """The second side of a symmetric pair: the attach frame reflected across x = 0 (the piece is
    left-right symmetric, so the reflected frame is a proper rotation of it, no flipped winding)."""
    flip = lambda v: (-v[0],) + tuple(v[1:])
    return dict(cfg, part=cfg['mirror']['part'], owner=cfg['mirror']['owner'], at=flip(cfg['at']), normal=flip(cfg['normal']), fire=flip(cfg['fire']))


def side(unit, cfg, kit, mesh, skeleton, parts, W, pose, hull, glass_hull):
    """One mount of a unit: seat, checks, clearance against the other parts, welded rows."""
    seat, M = place(cfg, hull); scale = cfg['scale']; measured = checks(kit, seat, M, scale, hull, glass_hull)
    mount_tris = to_posed(kit['tri'].reshape(-1, 3), seat, M, scale).reshape(-1, 3, 3)
    measured['parts'], clash = part_clearance(mount_tris, part_triangles(mesh, pose, skeleton, parts), parts, W, cfg['owner'], seat, M[1],
                                              measured['saddleTop'], measured['muzzle'], measured['fire'], cfg['part'], cfg.get('fireThrough', ()))
    assert not clash, (unit, cfg['part'], clash)
    bone = next(b for b in skeleton.bones if b.name.lower() == cfg['owner'].lower())
    D, shift = pose[bone.handle]; (rows, index), posed = mount_rows(kit, seat, M, scale, D, shift)
    muzzle = np.array(measured['muzzle']); fire = np.array(measured['fire'])
    return dict(cfg=cfg, seat=seat, M=M, measured=measured, bone=bone, rows=rows, index=index, muzzle=muzzle, fire=fire, point=muzzle - fire * INSET * scale)


def build(unit, render_sheets, shipping):
    cfg = CONFIG[unit]; kit = piece(cfg['piece']); work, mesh, skeleton, parts, W, by, pose = load(unit, cfg)
    hull = posed_hull(mesh, pose); glass_hull = posed_hull(mesh, pose, glass=True)
    sides = [side(unit, c, kit, mesh, skeleton, parts, W, pose, hull, glass_hull) for c in [cfg] + ([mirrored(cfg)] if 'mirror' in cfg else [])]
    first = sides[0]; seat, M, measured, muzzle, fire, point, scale = first['seat'], first['M'], first['measured'], first['muzzle'], first['fire'], first['point'], cfg['scale']
    rows = np.concatenate([s['rows'] for s in sides]); index = np.concatenate([s['index'] + sum(len(o['rows']) for o in sides[:i]) for i, s in enumerate(sides)])
    owners = np.concatenate([np.full(len(s['rows']), s['bone'].handle) for s in sides])
    material = unit + '_hpmount'; paint, accent, atlas, marks = seat_paint(mesh, pose, seat, M[1])
    images, zone = textures(unit, kit, paint, dict(nj.FACTIONS[cfg['faction']], stripe=accent)); tex = save_textures(images, material, work)
    (work / (material + '.material')).write_text('\n'.join(['import * from "CR_BZBase.material"', ''] + nj.material_block(material)), newline='\n')
    nj.preview_mesh(mesh, material, rows, index, owners, work / f'{unit}.mesh')
    shipped = RECEIPTS / f'{unit}.json'  # the shipped VDF already carries an earlier mount's hardpoint: keep the stock point
    shipped = json.loads(shipped.read_text()) if shipped.exists() else None
    hp_receipt = None
    for i, s in enumerate(sides):
        hp_path, hp_receipt = hardpoint_entry(unit, s['cfg'], by, W, s['point'], hp_receipt)
        old = (shipped if i == 0 else shipped.get('mirror')) if shipped else None
        s['old'] = old['stockHardpoint'] if old else (W[s['cfg']['part'].lower()][1] * S).tolist()
    old_hp = first['old']
    receipt = dict(note='Hardpoint mount (Tools/Build-HardpointMounts.py). Ogre mesh space in the VDF pose (VDF x = -x), metres. '
                        'The hardpoint sits INSET x scale inside the muzzle, on the fire axis.',
                   unit=unit, piece=cfg['piece'], part=by[cfg['part'].lower()].name, owner=by[cfg['owner'].lower()].name,
                   faction=cfg['faction'], base=cfg['base'], material=material, triangles=int(len(kit['tris'])) * len(sides), fireThrough=list(cfg.get('fireThrough', ())),
                   frame=dict(at=list(cfg['at']), seat=seat.round(6).tolist(), normal=M[1].round(6).tolist(), front=M[2].round(6).tolist(), scale=scale),
                   bury=float(kit['bury']) * scale, muzzle=muzzle.round(6).tolist(), fire=fire.round(6).tolist(), inset=INSET * scale,
                   hardpoint=np.round(point, 6).tolist(), stockHardpoint=np.round(old_hp, 6).tolist(),
                   paint=[round(c, 1) for c in paint], accent=[round(c, 1) for c in accent], markTexels=marks, paintFrom=Path(atlas).name, checks=measured)
    if len(sides) > 1:  # the mirrored mount: the second half of the submesh's triangles
        s = sides[1]
        receipt['mirror'] = dict(part=by[s['cfg']['part'].lower()].name, owner=by[s['cfg']['owner'].lower()].name,
                                 frame=dict(at=list(s['cfg']['at']), seat=s['seat'].round(6).tolist(), normal=s['M'][1].round(6).tolist(), front=s['M'][2].round(6).tolist(), scale=scale),
                                 muzzle=s['muzzle'].round(6).tolist(), fire=s['fire'].round(6).tolist(), hardpoint=np.round(s['point'], 6).tolist(),
                                 stockHardpoint=np.round(s['old'], 6).tolist(), checks=s['measured'])
    if shipping:
        receipt['meshSha256'] = nj.ship(unit, material, work)
        RECEIPTS.mkdir(parents=True, exist_ok=True)
        (RECEIPTS / f'{unit}.json').write_text(json.dumps(receipt, indent=2) + '\n', newline='\n')
        hp_path.write_text(json.dumps(hp_receipt, indent=2) + '\n', newline='\n')
    else:
        (work / 'receipt.json').write_text(json.dumps(receipt, indent=2)); (work / 'hardpoints.json').write_text(json.dumps(hp_receipt, indent=2))
    for s in sides:
        print(f"{unit}: {cfg['piece']} {len(kit['tris'])} tris on {s['bone'].name}, seat {s['seat'].round(3)}, muzzle {s['muzzle'].round(3)}, {s['cfg']['part']} moved {np.round(s['old'], 3)} -> {np.round(s['point'], 3)}, "
              f"ground {s['measured']['groundClearance']:+.3f}, parts {s['measured']['parts']}")
    print(f"{unit}: paint {np.round(paint)} accent {np.round(accent)} ({marks} marking texels)")
    if render_sheets:
        review = LOCAL / 'review'; review.mkdir(parents=True, exist_ok=True)
        lo, hi = hull.reshape(-1, 3).min(0), hull.reshape(-1, 3).max(0); centre = (lo + hi) / 2; radius = np.linalg.norm(hi - lo) / 2
        middle = to_posed((kit['positions'].min(0) + kit['positions'].max(0)) / 2, seat, M, scale)
        reach = np.linalg.norm(kit['positions'].max(0) - kit['positions'].min(0)) / 2 * scale
        views = views_for(centre, radius, middle.tolist(), fire, M[1], reach)
        base = hull_parts(mesh, pose, work, 'h')
        olds = [dict(at=s['old'], colour=(1, .2, .2), radius=.07) for s in sides]
        before = render(work, 'before', base, views, marks=olds)
        pods = [mount_part(work, f'mount{i}', kit, s['seat'], s['M'], scale, tex) for i, s in enumerate(sides)]
        after = render(work, 'after', base + pods, views, emit=[s['point'] for s in sides], fire=[s['fire'] for s in sides], marks=[dict(m, radius=.05) for m in olds])
        rolled, captions = [], []; target = np.array(views[1]['target'])
        wide = [dict(views[1], file='wide', eye=(target + (np.array(views[1]['eye']) - target) * 1.7 + (0, 0, .4)).tolist(), target=(target + (0, 0, .4)).tolist())]
        rolling = set(measured['parts']['lineOfFireCrossedBy']) | set(cfg.get('rollViews', ()))
        for gimbal in sorted(rolling):  # the gimbal next to the line of fire (or carrying the mount), at both ends of its sweep
            for a in (-measured['parts']['sweepDegrees'], measured['parts']['sweepDegrees']):
                handles, pivot, R = roll = gimbal_roll(skeleton, parts, W, gimbal, a)
                shot = hull_parts(mesh, pose, work, f'r{a:+.0f}_', roll=roll)
                moved = [dict(p) for p in pods]
                for i, s in enumerate(sides):  # a mount on the rolling part turns with it
                    if s['bone'].handle in handles:
                        d = dict(np.load(moved[i]['mesh'])); d['positions'] = (d['positions'] - pivot) @ R.T + pivot; d['normals'] = d['normals'] @ R.T
                        moved[i]['mesh'] = str(work / f'mount{i}_r{a:+.0f}.npz'); np.savez(moved[i]['mesh'], **d)
                still = [s for s in sides if s['bone'].handle not in handles]  # fire lines only where the mount did not turn
                rolled += render(work, f'rolled{a:+.0f}', shot + moved, wide, emit=[s['point'] for s in still], fire=[s['fire'] for s in still])
                captions.append(f'after: seat and {gimbal} rolled to {a:+.0f} deg')
        pair = f" and {receipt['mirror']['part']} mirrored" if len(sides) > 1 else ''
        nj.sheet(before + after + rolled, ['before: 3/4', 'before: close-up', 'after: 3/4', 'after: close-up'] + captions, review / f'{unit}.jpg', 2,
                 footer=[f"{unit}: {cfg['piece']} on {receipt['owner']} ({len(kit['tris'])} tris{pair}), paint {np.round(paint).astype(int).tolist()} and marking {np.round(accent).astype(int).tolist()} sampled beside the seat on {receipt['paintFrom']}; {measured['groundClearance']:+.2f} m above the hull's lowest point",
                         f"{receipt['part']} moved from {np.round(old_hp, 2).tolist()} (white dot) to the muzzle {np.round(point, 2).tolist()} (where the orange fire-direction line starts)",
                         f"gimbal sweep +-{measured['parts']['sweepDegrees']} deg, nearest gap {measured['parts']['sweepGap']}; line of fire crossed by {measured['parts']['lineOfFireCrossedBy'] or 'nothing'} ([first, last angle, count])"])
    return receipt


def kit_sheet():
    """Each piece alone in neutral grey and both faction paints, and the rocket pod on avfigh's lower side facet
    and on its wing root (the same piece and UV layout from a second attach frame)."""
    work = LOCAL / 'kit'; images, captions = [], []
    palettes = [('neutral', NEUTRAL['paint'], NEUTRAL['faction']), ('nsdf', (60., 92, 96), nj.FACTIONS['nsdf']), ('blackdogs', (58., 58, 60), nj.FACTIONS['blackdogs'])]
    for name in ('rocket', 'cannon', 'mortar'):
        kit = piece(name); lo, hi = kit['positions'].min(0), kit['positions'].max(0); step = (hi[0] - lo[0]) * 1.5 + .15
        parts = []
        for i, (label, paint, faction) in enumerate(palettes):  # side by side along x, left to right
            tex = save_textures(textures(f'kit_{name}_{label}', kit, paint, faction)[0], f'kit_{name}_{label}', work)
            M = np.eye(3); seat = np.array(((1 - i) * step, 0, 0))
            parts.append(mount_part(work, f'{name}_{label}', kit, seat, M, 1., tex))
        Image.fromarray(np.uint8(textures(f'kit_{name}_mask', kit, (255, 255, 255), dict(stripe=(0, 0, 0)))[1] == PAINT) * 255).save(work / f'{name}_paintmask.png')
        target = (lo + hi) / 2; reach = np.linalg.norm(hi - lo + (2 * step, 0, 0)) / 2
        eye = target + nj.unit_vectors(np.array((-.3, .45, .85))) * reach * 3.2
        shot = render(work, f'sheet_{name}', parts, [dict(file='kit', eye=eye.tolist(), target=target.tolist(), fov=40)])
        images += shot; captions.append(f'{name}: {len(kit["tris"])} tris; neutral / NSDF / Black Dogs')
    cfg = CONFIG['avfigh']; kit = piece('rocket'); w, mesh, skeleton, parts_, W, by, pose = load('avfigh', cfg)
    hull = posed_hull(mesh, pose); base = hull_parts(mesh, pose, w, 'k')
    tex = {k: str(w / f'avfigh_hpmount_{k}.png') for k in 'DN'}
    for label, c in (('side', cfg), ('wing', WING)):
        seat, M = place(c, hull); checks(kit, seat, M, c['scale'], hull, posed_hull(mesh, pose, glass=True))
        side = nj.unit_vectors(np.array((1., -.35, .8) if label == 'side' else (-1., .5, .8)))
        images += render(w, f'kit_{label}', base + [mount_part(w, f'kit_{label}', kit, seat, M, c['scale'], tex)],
                         [dict(file=label, eye=(seat + side * 3.2).tolist(), target=seat.tolist(), fov=45)])
        captions.append(f'avfigh rocket pod, {label} frame (normal {np.round(M[1], 2).tolist()})')
    nj.sheet(images, captions, LOCAL / 'review' / 'kit.jpg', 3, footer=['One UV layout and paint mask per piece; per unit only the attach frame, scale and palette change. The wing mount is a preview only.'])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--units', nargs='*', default=sorted(CONFIG)); ap.add_argument('--skip-render', action='store_true')
    ap.add_argument('--ship', action='store_true'); ap.add_argument('--kit-sheet', action='store_true')
    args = ap.parse_args()
    for unit in args.units:
        build(unit, not args.skip_render, args.ship)
    if args.kit_sheet:
        kit_sheet()


if __name__ == '__main__':
    main()
