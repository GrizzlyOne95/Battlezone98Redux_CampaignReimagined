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
Local/NacelleJets plus review renders (References/NacelleJets/review only with --ship,
Local/NacelleJets/review-rollout otherwise). It always starts from the unit's pre-rig
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
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'Tools'))
import ogrelayout
import reddevilcockpit as shared
import weaponrigs as wr
from bcdds import save_bc
from bzmodellibs import geo, geo_serializer, legacy, legacy_port

om, oms, VES = shared.om, shared.oms, shared.om.VES
BLENDER = Path(os.environ.get('CR_BLENDER') or r'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe')
PAINT, BELL, LIP, GROOVE, BORE, THROAT, VENT = range(7)
SIZE = 512

S = np.array([-1., 1., 1.])  # VDF space -> Ogre mesh space
MIRROR = np.array([-1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1])  # a vertex row mirrored in x

# Faction dressing that cannot be sampled from the hull texture.
# glow: the ring and its light, in the faction's engine flame colour (NSDF blue, Black Dogs
# blood red, CCA burnt orange, CRA green).
FACTIONS = {'nsdf': dict(stripe=(214, 214, 204), glow=(40, 140, 255)), 'blackdogs': dict(stripe=(176, 44, 36), glow=(215, 18, 18)),
            'cca': dict(stripe=(206, 176, 70), glow=(235, 110, 24)), 'cra': dict(stripe=(196, 150, 60), glow=(50, 225, 70))}
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
                 scale=scale, length=length, over=over, auto=True, stripe=(k(.14) * length, k(.21) * length))
    for part in ('bell', 'bore', 'groove'):
        shape[part] = {n: k(v) for n, v in BASE[part].items()}
    return dict(shape, **over)


def unit(faction, scale, length=1., also=(), shift=(), housing=True, note=None, ports=False, carrier=None, **over):
    """CONFIG entry. also: ((part-name regex, shape), ...) for nacelles that need their own shape.
    shift: ((part-name regex, move), ...) approved emit-point moves, built at the moved point and
    recorded as emitShift for the VDF change: metres along the emitter's up axis (against the
    flame), an (x, y, z) vector in its frame, 'skin' (up or down to just under the seat skin) or
    'nacelle' (a class 75 part moved to the class 67 rule point of the nacelle it rides), or
    'relocate': the flame leaves the bbox-rule point for the nearest flat, solid spot on the same
    nacelle skin where a housing seats cleanly with its nozzle on the new emit point (found by
    the build, mirrored left/right). A moved flame needs a class 75 part parented to the nacelle
    (it draws from its own position along its front axis, and one authored class 75 part
    suppresses every automatic under-nacelle emitter: BZ 1.5 decompile all_decompiled.c
    193462-193491; throttle scaling needs a nacelle parent, 193771-193776), so the build records one for every nacelle as vdfParts.
    housing=False: record the emit points and the sheet only. ports=True (with housing=False): the
    nacelles already model glowing exhaust ports; find them in the emissive map and propose
    moving each flame into the largest port its own nacelle carries, along the port's normal.
    carrier=dict(name, parent, at=((x, y), ...), gains=...): a unit with neither a class 67 nor a
    class 75 part (it draws no flame at all) gets a new class 67 nacelle part `name` under hull
    part `parent`, with its own bone and GEO, carrying a housing on the rear skin at each Ogre
    (x, y) of `at`, mirrored to -x (carrier_jets)."""
    return dict(faction=faction, shape=fitted(scale, length, **over), also=also, shift=shift, housing=housing, note=note, ports=ports, carrier=carrier)


CONFIG = {
    'avfigh': dict(faction='nsdf', stripe=(.14, .21), shape=BASE),
    # Fitted shapes. scale ~ flame width (the engine draws every unit's flame the same size)
    # and the room under the nacelle; length stretches the pod along the chord.
    'avapc': unit('nsdf', 1.3, .8, housing=False, ports=True, note='no housing: each side pod already models glowing exhaust ports underneath; the flames are proposed into those'),
    'avartl': unit('nsdf', 1.2, housing=False, ports=True, note='no housing: each nacelle already models glowing exhaust ports; the flames are proposed into those'),
    'avltnk': unit('nsdf', 1., .6), 'avmine': unit('nsdf', 1.3), 'avrckt': unit('nsdf', 1.), 'avtank': unit('nsdf', 1., .8, shift=(('.', 'relocate'),)),
    # conform=True: the pod roof follows uneven skin (conform_underside) where no flat seat clears it.
    'avhraz': unit('nsdf', .9, .8, shift=(('.', 'relocate'),), conform=True), 'avtest': unit('nsdf', .8, shift=(('.', 'relocate'),)),
    'bvapc': unit('blackdogs', 1.3, .8, housing=False, ports=True, note='no housing: each side pod already models glowing exhaust ports underneath; the flames are proposed into those'),
    'bvartl': unit('blackdogs', 1.2, housing=False, ports=True, note='no housing: each nacelle already models glowing exhaust ports; the flames are proposed into those'),
    'bvltnk': unit('blackdogs', 1., .6), 'bvmine': unit('blackdogs', 1.3), 'bvraz': unit('blackdogs', .9), 'bvrckt': unit('blackdogs', 1.),
    'bvtank': unit('blackdogs', 1., .8, shift=(('.', 'relocate'),)),
    'bvhraz': unit('blackdogs', .9, .8, shift=(('.', 'relocate'),), conform=True),  # the avhraz mesh with Black Dog bones
    'svapc': unit('cca', 1.3), 'svartl': unit('cca', 1.3, shift=(('.', 'relocate'),)), 'svfigh': unit('cca', 1., shift=(('.', 'relocate'),)),
    'svhraz': unit('cca', .8, 1.2, shift=(('.', 'relocate'),)), 'svltnk': unit('cca', .8, .9, shift=(('.', 'relocate'),), conform=True),
    'svmine': unit('cca', 1.2, shift=(('.', 'relocate'),)), 'svmuf': unit('cca', 1.4, shift=(('.', 'relocate'),)), 'svrckt': unit('cca', 1.1),
    'svrecy': unit('cca', 1.5, shift=(('.', 'relocate'),)), 'svslf': unit('cca', 1.2), 'svscav': unit('cca', 1.3, shift=(('.', 'relocate'),)),
    'cvfigh': unit('cra', .9), 'cvhraz': unit('cra', 1.3), 'cvmine': unit('cra', .9, shift=(('.', 'relocate'),)),
    # Units that author class 75 flame parts.
    'bvrdev': unit('blackdogs', .9, housing=False, shift=(('en1$', -.2),),
                   note='no housing: all three class 75 parts fire through nozzles modelled on the rear body'),
    'svhaul': unit('cca', 1.2, shift=(('.', 'relocate'),)),
    # Flameless units: no class 67 or 75 part, so a new nacelle part carries rear housings.
    # cvltnk: on the grey rear plates of the side pods (the chord runs up the plate).
    'cvltnk': unit('cra', .7, .6, carrier=dict(name='CNA11NAC', parent='CNA11BDA', at=((1.0, 1.0),))),
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


def yaw_matrix(degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def place(jet):
    """(Re)compute the emitter's point, flame direction and frame in the VDF pose."""
    D, shift = jet['_pose']; e = np.array(jet['emit']); Q = np.array(jet.get('axes', np.eye(3)))
    jet['posed'] = dict(emit=(D @ e + shift).tolist(), flame=(-(D @ Q)[:, 1]).tolist(), axes=(D @ Q).tolist())
    return jet


def base_vdf(unit):
    """The VDF the emit points come from: the unit's Assets/ModelFixes VDF at the weapon-rig
    source revision (its animation fixes), else the stock one. Never the shipped VDF, which
    already carries the class 75 parts recorded here (Tools/Build-UnitAnimSlots.py adds them)."""
    revision = json.loads((ROOT / 'References/WeaponRigs/models.json').read_text())['source_revision']
    # A missing revision (shallow clone, bad pin) must fail, not fall back to stock emit points.
    subprocess.run(['git', 'rev-parse', '--verify', '--quiet', revision + '^{commit}'], cwd=ROOT, capture_output=True, check=True)
    proc = subprocess.run(['git', 'show', '--no-textconv', f'{revision}:Assets/ModelFixes/{unit}.vdf'], cwd=ROOT, capture_output=True)
    if proc.returncode == 0:
        return proc.stdout
    data = legacy_port.AssetSource(archives=[wr.GAME / 'bzone.zfs', wr.GAME / 'tro_cam.zfs'])(unit + '.vdf')
    assert data, (unit, 'has no stock VDF')
    return data


def carrier_jets(car, parts, W, skeleton, mesh, pose):
    """A unit with no class 67 and no class 75 part draws no flame (BZ 1.5 decompile
    all_decompiled.c 193458-193491 places automatic emitters under class 67 parts only). A new
    class 67 part car['name'] under hull part car['parent'] carries one housing per (x, y) of
    car['at'] and its -x mirror, seated on the rear skin found by a ray along +z. Each flame gets
    its own class 75 part under the new nacelle (one class 75 part suppresses the automatic
    emitter, 193462-193473; throttle scaling needs the class 67 parent, 193771-193776). The new
    bone (reused when a shipped skeleton already has it) follows the hull's VDF pose."""
    names = {p.name.lower() for p in parts}; assert car['name'].lower() not in names, (car['name'], 'is already a VDF part')
    parent = next(b for b in skeleton.bones if b.name.lower() == car['parent'].lower())
    own = next((b for b in skeleton.bones if b.name.lower() == car['name'].lower()), None)
    handle = own.handle if own else max(b.handle for b in skeleton.bones) + 1
    pose[handle] = pose[parent.handle]; whole = hull(mesh)[0]; out = []
    # Build frame columns: x = -mesh x, y (toward the skin) = +z, z (the pod's chord) = +y; the flame runs along -z.
    axes = [[-1., 0, 0], [0, 0, 1], [0, 1, 0]]
    for x, y in car['at']:
        for sx in (abs(x), -abs(x)):
            d = ahead(whole, np.array((sx, y, -20.)), np.array((0., 0, 1)))
            assert d is not None, (car['name'], 'no rear skin at', (sx, y))
            jet = dict(part='%s%+.2f' % (car['name'], sx), bone=handle, skin=parent.handle, emit=[sx, y, -20. + d - .02], axes=axes,
                       source='carrier', carrier=car['name'], toSkin=True, relocate=False)
            jet['_vdf'] = dict(parent=car['name'], frame=None, existing=None, names=names | {car['name'].lower()})
            jet['_pose'] = pose[handle]; out.append(place(jet))
    return out


def carrier_frames(jets, car, W, skeleton, pose):
    """Once seated: the new nacelle's pivot (on the centre line, at the mean seated emit point,
    so a small pitch keeps the housing roots in the skin), its VDF frame and part record, and
    its bone in the parent's frame (the toolkit serializer's native frame: x mirrored)."""
    own = [j for j in jets if j.get('carrier')]; Rp, tp = W[car['parent'].lower()]
    posed = np.mean([j['posed']['emit'] for j in own], 0); posed[0] = 0.; t = posed * S
    for j in own:
        j['_vdf']['frame'] = (Rp, t)
    handle = own[0]['bone']; D, shift = pose[handle]; pivot = np.linalg.solve(D, posed - shift)
    parent = next(b for b in skeleton.bones if b.name.lower() == car['parent'].lower())
    pos, q = wr.flash.bone_world(skeleton, parent.handle); local = quat_matrix(q).T @ (pivot - np.array(pos, float))
    for j in own:
        j['pivot'] = pivot.tolist()
    return dict(name=car['name'], klass=67, parent=car['parent'], matrix=np.eye(3).ravel().tolist() + ((t - tp) @ Rp.T).tolist(),
                pivot=pivot.tolist(), posedPivot=posed.tolist(), geo=car['name'].lower() + '.geo',
                bone=dict(name=car['name'], handle=handle, parent=parent.name, position=(local * S).tolist(), orientation=[1., 0, 0, 0]),
                gains=car.get('gains', dict(pitchThrotNacelleRun=.05, pitchSteerNacelleRun=.05, pitchThrotNacelleJump=.05, pitchSteerNacelleJump=.05)))


def nacelle_geo(record, data, faces, owner, unit):
    """The new nacelle's GEO: its housings' triangles in the part's own frame (VDF space: x is
    the mirrored Ogre x, so the winding flips), and the part's bounding box for the VDF record."""
    keep = owner[faces].min(1) == record['bone']['handle']; tris = faces[keep]
    points = (np.array(data[:, :3], float) - record['posedPivot']) * S; points = points.astype('<f4')
    used = np.unique(tris); remap = np.full(len(points), -1); remap[used] = np.arange(len(used)); points = points[used]; tris = remap[tris][:, ::-1]
    g = geo.Geo(); g.name = record['name'].lower(); g.vert_count = len(points); g.vertex_pos_buffer = points
    g.vertex_normal_buffer = (np.array(data[used, 3:6], float) * S).astype('<f4')
    for i, t in enumerate(tris):
        q = [points[k].astype('<f8') for k in t]; n = np.cross(q[1] - q[0], q[2] - q[0]); n = n / max(np.linalg.norm(n), 1e-12)
        face = g.create_face(i); face.color = geo.Color3(255, 255, 255); face.plane = geo.SurfacePlane(geo.Vector3(*(-n)), float(n.dot(q[0])))
        face.shade_type = face.texture_type = 0; face.texture_name = unit + 'nj.map'
        for k in t:
            face.create_face_node(int(k), int(k), geo.UV(float(data[used[k], 6]), float(data[used[k], 7])))
    raw = io.BytesIO(); geo_serializer.GeoSerializer(raw).write(g)
    lo, hi = points.min(0).astype(float), points.max(0).astype(float)
    record.update(center=((lo + hi) / 2).tolist(), halfSize=((hi - lo) / 2).tolist(), radius=float(np.linalg.norm(hi - lo) / 2), triangles=len(tris))
    return raw.getvalue()


def emitters(unit, skeleton, mesh, shifts=(), carrier=None):
    """Engine flame emit points in Ogre mesh space (skeleton bind pose), and the bind-to-VDF
    pose of every bone. One emitter per class 75 part when the VDF authors any, else one under
    every class 67 nacelle. Each carries the bone its housing rides, `axes` (build frame as
    columns: the flame runs along -y) when that frame is not the mesh frame, and `posed`: the
    same point and flame direction in the VDF pose."""
    source = legacy_port.AssetSource(folders=[ROOT / 'Assets/ModelFixes', ROOT / 'Assets/Models'],
                                     archives=[wr.GAME / 'bzone.zfs', wr.GAME / 'tro_cam.zfs'])
    parts = legacy.read_vdf(base_vdf(unit)).band(0); W, by = vdf_world(parts); pose = vdf_pose(skeleton, W)
    authored = [p for p in parts if p.klass == 75]; out = []
    if carrier and not authored and not any(p.klass == 67 for p in parts):
        return sorted(carrier_jets(carrier, parts, W, skeleton, mesh, pose), key=lambda e: -e['emit'][0]), pose
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

        def under_nacelle(name):  # the class 67 rule: nacelle up axis x GEO bounding box min y
            geo = source(name + '.geo')
            if geo is None:  # no GEO to read the bounding box from: lowest vertex the nacelle bone owns
                own = hull(mesh, bone.handle)[0].reshape(-1, 3); assert len(own), (name, 'has neither a GEO nor mesh triangles')
                drop = float(((own - pivot) @ quat_matrix(q))[:, 1].min()); jet['estimate'] = 'GEO file missing: emit height taken from the lowest mesh vertex the nacelle bone owns'
            else:
                drop = float(np.asarray(legacy.read_geo(geo).positions, float)[:, 1].min())
            if max(abs(c) for c in q[:3]) < 1e-5:
                jet['emit'] = [float(pivot[0]), float(pivot[1]) + drop, float(pivot[2])]
            else:  # rotated bind pose: the drop and the flame follow the nacelle's own up axis
                Rb = quat_matrix(q); jet.update(emit=(pivot + Rb[:, 1] * drop).tolist(), axes=Rb.tolist())

        if authored:
            # Its own transform; the flame runs along the part's front axis (BZ 1.5 decompile
            # all_decompiled.c 255588-255605: flame end = position + front * 2 * flameLength * scale;
            # class 75 parts collected at 193702-193706). UNVERIFIED against the Redux renderer.
            R, t = W[part.name.lower()]; M = (R.T * S[:, None]) * S[None, :]; y = -M[:, 2]; z = M[:, 1]
            jet.update(source='class 75 part', emit=(D.T @ (t * S - shift)).tolist(), axes=(D.T @ np.c_[np.cross(y, z), y, z]).tolist())
            if owner is not part:
                jet['rides'] = owner.name
        else:
            under_nacelle(part.name)
        move = next((value for pattern, value in shifts if re.search(pattern, part.name, re.I)), None)
        if move is not None:  # an approved move: build there, keep the stock point for the record
            jet['stockEmit'] = jet['emit']; Q = np.array(jet.get('axes', np.eye(3)))
            if move in ('skin', 'relocate'):
                jet['toSkin'] = True; jet['relocate'] = move == 'relocate'
            elif move == 'nacelle':
                assert owner.klass == 67, (part.name, 'does not ride a class 67 nacelle')
                jet.pop('axes', None); under_nacelle(owner.name)
            else:
                jet['emit'] = (np.array(jet['emit']) + Q @ np.array(move if np.ndim(move) else (0, move, 0), float)).tolist()
        nacelle = by[part.parent.lower()] if authored else part  # the part a class 75 flame part hangs from
        jet['_vdf'] = dict(parent=nacelle.name, frame=W[nacelle.name.lower()], existing=part.name if authored else None, names={p.name.lower() for p in parts})
        jet['_pose'] = (D, shift); out.append(place(jet))
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


def underside(tri, emit, shape, plane=None, roof=None):
    """Least-squares height of the wing underside over the pod footprint: along the chord, and
    across it too for a fitted shape. Returns the fit, its worst error and the seat: share of
    the footprint with skin above it, and share where the buried roof would come out of the
    far side. With plane, measures against that fit instead. A conform shape seats on the lowest
    skin and builds its roof from the skin heights instead (conform_underside)."""
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
    if shape.get('conform'):
        return conform_underside(tri, emit, shape, rows, A, total, plane, roof)
    fit = np.array(plane) if plane is not None else np.linalg.lstsq(A, rows[:, 1], rcond=None)[0]
    error = float(np.abs(rows[:, 1] - A @ fit).max())
    if auto and plane is not None:  # against a seated plane only skin above it (the roof would float) counts
        error = float((rows[:, 1] - A @ fit).max())
    if auto and plane is None:  # seat on the highest skin so the roof is buried everywhere; the pod deepens to suit
        fit[0] += (rows[:, 1] - A @ fit).max()
    seat = dict(cover=len(rows) / total, pokes=float((A @ fit + shape['bury'] > rows[:, 3] - .003).mean()))
    if auto:
        seat['spread'] = float((A @ fit - rows[:, 1]).max())
    if plane is None:
        assert error < (shape['scale'] * .3 if auto else shape['bury'] * .5), ('wing underside is not flat enough to bury the pod roof', error)
        assert not auto or seat['cover'] >= .35, ('too little skin above the pod footprint to seat on', seat)
        assert seat['pokes'] == 0, ('the buried pod roof would come out of the far side of the wing', seat)
    return [float(f) for f in fit], error, seat


ROOF_STEP, ROOF_ALONG = .02, .04  # conformal roof: skin sampling step; pod section spacing along the chord


def roof_across(shape):
    """Roof vertices across a conformal pod section (about 4 cm apart at the widest section)."""
    return max(3, math.ceil(2 * max(s[1] for s in shape['sections']) / .04) + 1)


def roof_at(roof, x, z):
    """Bilinear height of a conformal roof grid (absolute build frame) at x, z; clamped at its edges."""
    h = np.asarray(roof['h']); g = roof['step']
    fx = np.clip((np.asarray(x, float) - roof['x0']) / g, 0, h.shape[0] - 1); fz = np.clip((np.asarray(z, float) - roof['z0']) / g, 0, h.shape[1] - 1)
    i = np.minimum(fx.astype(int), h.shape[0] - 2); j = np.minimum(fz.astype(int), h.shape[1] - 2); t = fx - i; u = fz - j
    return h[i, j] * (1 - t) * (1 - u) + h[i + 1, j] * t * (1 - u) + h[i, j + 1] * (1 - t) * u + h[i + 1, j + 1] * t * u


def skin_columns(tri, xs, zs):
    """Lowest skin height and the next surface above it (more than 1 cm higher) over every
    (x, z) grid point; NaN / inf where there is none."""
    X, Z = np.meshgrid(xs, zs, indexing='ij'); low = np.full(X.shape, np.nan); above = np.full(X.shape, np.inf)
    keep = (tri[:, :, 0].max(1) >= xs[0]) & (tri[:, :, 0].min(1) <= xs[-1]) & (tri[:, :, 2].max(1) >= zs[0]) & (tri[:, :, 2].min(1) <= zs[-1])
    a, b, c = tri[keep, 0], tri[keep, 1], tri[keep, 2]
    d = (b[:, 2] - c[:, 2]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 2] - c[:, 2]); ok = np.abs(d) > 1e-12; d = np.where(ok, d, 1)
    for i, x in enumerate(xs):
        z = zs[:, None]
        u = ((b[:, 2] - c[:, 2]) * (x - c[:, 0]) + (c[:, 0] - b[:, 0]) * (z - c[:, 2])) / d
        v = ((c[:, 2] - a[:, 2]) * (x - c[:, 0]) + (a[:, 0] - c[:, 0]) * (z - c[:, 2])) / d
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1); y = np.where(hit, u * a[:, 1] + v * b[:, 1] + (1 - u - v) * c[:, 1], np.inf)
        y0 = y.min(1); low[i] = np.where(np.isfinite(y0), y0, np.nan)
        above[i] = np.where(y > y0[:, None] + .01, y, np.inf).min(1)
    return low, above


def conform_underside(tri, emit, shape, rows, A, total, plane, roof):
    """The conformal seat (opt-in shape key conform, for skin too uneven for one flat seat): the
    seat plane follows the chord and lies at or under the lowest skin over the footprint, and the
    pod roof is a height grid that follows the skin (the window maximum of the lowest skin over a
    roof-vertex spacing, so the roof between its vertices stays buried too) plus bury. Everything
    the pod meets is then above its seat plane. With plane and roof, measures against those."""
    assert shape.get('auto'), 'conform needs an auto shape (three-column seat fit)'
    if plane is None:
        fit = np.r_[np.linalg.lstsq(A[:, :2], rows[:, 1], rcond=None)[0], 0.]
        fit[0] -= (A @ fit - rows[:, 1]).max()
    else:
        fit = np.array(plane, float)
    error = float((A @ fit - rows[:, 1]).max())  # skin under the seat plane: 0 when seated on it
    g = ROOF_STEP; ox, oz = shape.get('offset', (0., 0.)); half = max(s[1] for s in shape['sections']); zs = [s[0] for s in shape['sections']]
    w = max(2 * half / (roof_across(shape) - 1), ROOF_ALONG) + g; r = math.ceil(w / g - 1e-9)
    xs = emit[0] + ox + np.arange(-half - w, half + w + 1e-6, g); zz = emit[2] + oz + np.arange(min(zs) - w, max(zs) + w + 1e-6, g)
    low, above = skin_columns(tri, xs, zz); X, Z = np.meshgrid(xs, zz, indexing='ij'); under = fit[0] + fit[1] * (Z - emit[2]) + fit[2] * (X - emit[0])
    if roof is None:
        pad = np.pad(np.where(np.isnan(low), -np.inf, low), r, constant_values=-np.inf); top = np.full(low.shape, -np.inf)
        for di in range(2 * r + 1):
            for dj in range(2 * r + 1):
                top = np.maximum(top, pad[di:di + low.shape[0], dj:dj + low.shape[1]])
        roof = dict(x0=float(xs[0]), z0=float(zz[0]), step=g, h=np.maximum(top, under).tolist())
    outline = sorted((s[0], s[1]) for s in shape['sections'])
    inside = (np.abs(X - emit[0] - ox) <= np.interp(Z - emit[2] - oz, *zip(*outline), left=-1, right=-1))
    pokes = float((inside & (roof_at(roof, X, Z) + shape['bury'] > above - .003)).sum() / max(inside.sum(), 1))
    # roofGap: skin above the buried roof (a reused twin roof on a skin that rises higher here); 0 when buried
    lift = np.where(inside & ~np.isnan(low), np.nan_to_num(low, nan=-np.inf) - roof_at(roof, X, Z) - shape['bury'], -np.inf)
    seat = dict(cover=len(rows) / total, pokes=pokes, spread=float((rows[:, 1] - A @ fit).max()), roofGap=float(max(lift.max(), 0.)), roof=roof)
    if plane is None:
        assert seat['cover'] >= .35, ('too little skin above the pod footprint to seat on', {k: v for k, v in seat.items() if k != 'roof'})
        assert pokes == 0, ('the buried pod roof would come out of the far side of the wing', {k: v for k, v in seat.items() if k != 'roof'})
    return [float(f) for f in fit], error, seat


def solid_config(shape, emit, fit, seat, low=None):
    """Absolute dimensions for the Blender step and for the face tagging."""
    out = dict(shape, emit=emit, underside=fit)
    if shape.get('auto'):
        # gap: skin height above the emit point. The pod is as deep as it takes to carry the
        # nozzle at the emit point. Where the emit point is at or inside the skin the nozzle
        # hangs just under the skin instead (its throat stays buried; the flame then starts
        # above the throat) and `inside` says by how much.
        s = shape['scale']; gap = fit[0] - emit[1]; datum = min(emit[1], fit[0] - .05 * s, np.inf if low is None else low - .04 * s)
        k = (fit[0] - datum + .09 * s) / (.12 * s)
        out.update(emit=[emit[0], datum, emit[2]], sections=[(z, a, d * k) for z, a, d in shape['sections']],
                   vent=dict(shape['vent'], drop=shape['vent']['drop'] * min(k, 1), height=shape['vent']['height'] * min(k, 1)),
                   dropBuried=seat['cover'] > .999, seated=dict({n: v for n, v in seat.items() if n != 'roof'}, gap=gap, inside=emit[1] - datum, depthScale=k))
        if 'roof' in seat:  # conformal roof: the skin height grid, and how finely the pod follows it
            out.update(roof=seat['roof'], across=roof_across(shape), along=ROOF_ALONG)
        emit = out['emit']
    for part, keys in (('bell', ('top', 'lip')), ('bore', ('roof',)), ('groove', ('y0', 'y1'))):
        out[part] = dict(shape[part], **{k: emit[1] + shape[part][k] for k in keys})
    if shape.get('auto'):
        # A bore that is not wholly under the pod body (offset pod) would come out of the top of
        # the bell beside the pod and show the skin through the hole: keep its roof inside the bell.
        s = shape['scale']; ox, oz = shape.get('offset', (0., 0.)); r = shape['bore']['rRoof']; flat = [z for z, a, d in shape['sections'] if a >= .299 * s]
        if abs(ox) + r > .3 * s * shape['flat'] - .02 * s or -oz + r > max(flat) or -oz - r < min(flat):
            out['bore']['roof'] = emit[1] - .025 * s
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


def seat_paint(mesh, jet, centre, mirror, shape, fit):
    """Hull paint where the housing sits: the median texel of the seat skin under and around
    the pod footprint, so the pod matches the surface it is seated on."""
    tri, uv, sub = hull(mesh, jet.get('skin', jet['bone'])); local = to_build(tri, jet, centre, mirror); c = local.mean(1)
    ox, oz = shape.get('offset', (0., 0.)); half = max(s[1] for s in shape['sections']); zs = [s[0] for s in shape['sections']]
    plane = fit[0] + fit[1] * (c[:, 2] - centre[2]) + fit[2] * (c[:, 0] - centre[0])
    normal = unit_vectors(np.cross(local[:, 1] - local[:, 0], local[:, 2] - local[:, 0]))
    whole = hull(mesh)[0]; normal *= np.sign(np.einsum('ij,ij->', whole[:, 0], np.cross(whole[:, 1], whole[:, 2]))) * (-1 if mirror else 1)  # outward
    for grow in (2.5, 4.):
        sel = ((np.abs(c[:, 0] - centre[0] - ox) < half * grow) & (c[:, 2] - centre[2] - oz > min(zs) * grow) & (c[:, 2] - centre[2] - oz < max(zs) * grow)
               & (np.abs(c[:, 1] - plane) < .12 * grow) & (normal[:, 1] < -.3))  # the skin seen from below, not inner faces
        if sel.sum() >= 4:
            break
    else:
        return paint_colour(mesh, jet.get('skin', jet['bone']))
    n = np.bincount(sub[sel]).argmax(); sel &= sub == n; path = texture_path(mesh.submesh_list[n].material_name)
    assert path, (mesh.submesh_list[n].material_name, 'has no diffuse map in this mod')
    image = np.asarray(Image.open(path).convert('RGB'), float); h, w = image.shape[:2]
    area = np.linalg.norm(np.cross(local[sel][:, 1] - local[sel][:, 0], local[sel][:, 2] - local[sel][:, 0]), axis=1)
    pick = np.random.default_rng(1).choice(sel.sum(), 4000, p=area / area.sum()); weights = np.random.default_rng(2).dirichlet((1, 1, 1), 4000)
    sample = (weights[..., None] * uv[sel][pick]).sum(1) % 1
    texel = image[(sample[:, 1] * h).astype(int).clip(0, h - 1), (sample[:, 0] * w).astype(int).clip(0, w - 1)]
    calm = (texel.max(1) - texel.min(1) < 90) & (texel.max(1) > 45)  # hazard trim and decals (avhraz's yellow rail) are saturated, gaps and baked shadow near black; hull paint is neither
    if calm.sum() >= .2 * len(texel):
        texel = texel[calm]
    key = (texel // 40).astype(int) @ (1, 8, 64); texel = texel[key == np.bincount(key).argmax()]  # the dominant colour, not a blend of two paints
    return [float(v) for v in np.median(texel, 0)], path  # the median: decals and panel lines are the minority


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
    # the faction's flame colour, a hot core: brighter and less saturated toward the centre
    hot = glow * 255 / glow.max(); bore_deep = hot * .3; throat = hot * .42 * core
    throat_light = (hot * (1 - .6 * core ** 2) + 255 * .6 * core ** 2) * (.35 + .65 * core)
    for value, base, shine in ((PAINT, body, 46 + 14 * band), (BELL, metal, 120), (LIP, np.array((118., 114, 106)) * (1 + .08 * mottle[..., None]), 160),
                               (GROOVE, glow * .45, 40), (BORE, np.array((26., 24, 24)) * (1 - depth) + bore_deep * depth, 22),
                               (THROAT, throat, 30), (VENT, np.array((15., 16, 18)) + 0 * body, 10)):
        mask = zone == value; colour[mask] = np.broadcast_to(base, colour.shape)[mask]; spec[mask] = np.broadcast_to(shine, spec.shape)[mask]
    emissive[zone == GROOVE] = glow * .95
    emissive[zone == BORE] = (hot * .45 * depth ** 2.5)[zone == BORE]
    emissive[zone == THROAT] = np.broadcast_to(throat_light, emissive.shape)[zone == THROAT]
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


def crossings(a, b, tri):
    """Points where the segments a->b pass through triangles."""
    lo = np.minimum(a, b).min(0); hi = np.maximum(a, b).max(0); tri = tri[(tri.max(1) >= lo).all(1) & (tri.min(1) <= hi).all(1)]
    e1 = tri[:, 1] - tri[:, 0]; e2 = tri[:, 2] - tri[:, 0]; out = [np.zeros((0, 3))]
    for start in range(0, len(a) if len(tri) else 0, 128):
        o = a[start:start + 128, None]; d = (b[start:start + 128] - a[start:start + 128])[:, None]
        h = np.cross(d, e2[None]); det = (e1[None] * h).sum(-1); ok = np.abs(det) > 1e-14; f = 1 / np.where(ok, det, 1)
        s = o - tri[None, :, 0]; u = f * (s * h).sum(-1); q = np.cross(s, e1[None]); v = f * (d * q).sum(-1); w = f * (e2[None] * q).sum(-1)
        i, j = np.nonzero(ok & (u > 1e-6) & (v > 1e-6) & (u + v < 1 - 1e-6) & (w > 1e-6) & (w < 1 - 1e-6))
        out.append(o[i, 0] + d[i, 0] * w[i, j][:, None])
    return np.concatenate(out)


def stock_local(stock, jet, centre, mirror):
    """Every stock triangle (VDF pose) in the build frame of a housing carried by jet."""
    flip = np.array((-1., 1, 1) if mirror else (1., 1, 1))
    return ((stock - np.array(jet['posed']['emit'])) @ np.array(jet['posed']['axes'])) * flip + centre


def bore_low(local, centre, shape, fit, spread=0.):
    """Lowest stock mesh over the bore, from just under the emit point up to the seat: the
    nozzle has to hang below it so nothing shows in the throat."""
    r = shape['bore']['rMouth']; g = np.arange(-r, r + 1e-9, .02); x, z = np.meshgrid(g, g); keep = x * x + z * z <= r * r
    x = centre[0] + x[keep]; z = centre[2] + z[keep]; top = fit[0] + (abs(fit[1]) + abs(fit[2])) * r + shape['bury']
    hit = crossings(np.c_[x, np.full(len(x), centre[1] - .1 * shape['scale'] - spread), z], np.c_[x, np.full(len(x), top), z], local)
    return float(hit[:, 1].min()) if len(hit) else None


def check_flame_path(solid, local):
    """No stock triangle may pass through the bore, the throat or the open flame cone below the lip."""
    bell, bore = solid['bell'], solid['bore']; cx, _, cz = solid['emit']; lip = bell['lip']; roof = bore['roof']; reach = .9
    wide = bore['rMouth'] - .004; narrow = bore['rRoof'] - .004; a, b = [], []
    for dx in np.arange(-wide, wide + 1e-9, .02):  # along the flame
        for dz in np.arange(-wide, wide + 1e-9, .02):
            rho = math.hypot(dx, dz)
            if rho < wide:
                top = roof if rho <= narrow else lip + (roof - lip) * (wide - rho) / (wide - narrow)
                a.append((cx + dx, top, cz + dz)); b.append((cx + dx, lip - reach * min(1., (wide - rho) / (wide - .03)), cz + dz))
    for y in np.arange(lip - reach + .02, roof, .03):  # across it
        r = narrow + (wide - narrow) * (roof - y) / (roof - lip) if y >= lip else .03 + (wide - .03) * (1 - (lip - y) / reach)
        for angle in np.linspace(0, math.pi, 8, endpoint=False):
            c, s = math.cos(angle) * r, math.sin(angle) * r; a.append((cx + c, y, cz + s)); b.append((cx - c, y, cz - s))
    hit = crossings(np.array(a), np.array(b), local)
    assert not len(hit), ('stock mesh passes through the nozzle bore or the flame cone', dict(crossings=len(hit), belowLip=[round(float(lip - v), 2) for v in (hit[:, 1].max(), hit[:, 1].min())],
                               around=[round(float(v), 2) for v in (hit.mean(0) - solid['emit'])]))


def check_surface(solid, tri, local):
    """The housing's exposed surface may meet stock mesh only where it is seated: no crossing
    more than a few centimetres below the seat plane. (The band used to grow with the seat's
    unevenness, so an uneven seat let the pod walls cut 0.14 m into the skin and passed: avhraz.)"""
    fit = solid['underside']; ex, _, ez = solid['emit']; band = .02 + .03 * solid.get('scale', 1.)
    lo = tri.reshape(-1, 3).min(0) - .005; hi = tri.reshape(-1, 3).max(0) + .005; near = local[(local.max(1) >= lo).all(1) & (local.min(1) <= hi).all(1)]
    edges = lambda v: (v[:, [0, 1, 2]].reshape(-1, 3), v[:, [1, 2, 0]].reshape(-1, 3))
    hit = np.concatenate([crossings(*edges(tri), near), crossings(*edges(near), tri)]) if len(near) else np.zeros((0, 3))
    depth = fit[0] + fit[1] * (hit[:, 2] - ez) + fit[2] * (hit[:, 0] - ex) - hit[:, 1]; clip = depth > band
    assert not clip.any(), ('the housing cuts through stock mesh below its seat', dict(crossings=int(clip.sum()), deepest=round(float(depth.max()), 3),
                            around=[round(float(v), 2) for v in (hit[clip].mean(0) - (ex, solid['emit'][1], ez))]))


def seat(jet, shape, yaw, mesh, stock, work, n, like=None, slide=None, dry=False):
    """One attempt at seating a housing of this shape on jet (rotated yaw degrees about the
    flame axis), or at carrying the solid of housing `like`. Raises AssertionError when the
    seat, the flame path or the exposed surface fails a check."""
    trial = dict(jet); mirror = jet['emit'][0] * like['centre'][0] < 0 if like else jet['emit'][0] < -1e-3; s = shape['scale']
    flip = np.array((-1., 1, 1) if mirror else (1., 1, 1)); axes = np.array(jet.get('axes', np.eye(3)))
    if yaw:
        axes = axes @ yaw_matrix(-yaw if mirror else yaw); trial.update(axes=axes.tolist(), yaw=-yaw if mirror else yaw)
    slide = like.get('slide') if like else slide
    if slide:  # a relocated emit point: (outboard, nose) metres along the seat from the stock point
        trial['emit'] = (np.array(jet['emit']) + axes @ np.array((slide[0] * (-1. if jet['emit'][0] < -1e-3 else 1.), 0, slide[1]))).tolist()
    centre = np.array(like['centre']) if like else np.array(trial['emit']) * flip
    skin = to_build(hull(mesh, jet.get('skin', jet['bone']))[0], trial, centre, mirror)
    fit, error, how = underside(skin, centre, shape, like and like['fit'], like and like['solid'].get('roof'))
    rise = like['rise'] if like else fit[0] - centre[1] if jet.get('toSkin') else 0.
    if jet.get('toSkin'):  # the approved move to the skin: the housing is built at the moved point
        trial['emit'] = (np.array(trial['emit']) + axes[:, 1] * rise).tolist(); centre = centre + (0, 0 if like else rise, 0)
    place(trial); local = stock_local(stock, trial, centre, mirror); low = bore_low(local, centre, shape, fit, how['spread'])
    if like:
        assert error < shape['bury'] * .5 and abs(how['cover'] - like['seat']['cover']) < .08 and not how['pokes'] and not how.get('roofGap'), 'seats differently'
        assert low is None or low - .04 * s >= like['solid']['emit'][1] - 1e-6, 'stock mesh over the bore sits lower here'
        check_flame_path(like['solid'], local); check_surface(like['solid'], like['tri'], local)
        return trial, mirror
    solid = solid_config(shape, centre.tolist(), fit, how, low); check_flame_path(solid, local)
    if dry:
        return solid['seated']
    name = 'solid%d' % n; (work / (name + '.json')).write_text(json.dumps(solid, indent=1))
    log = blender('nacellejet_blender.py', work / (name + '.json'), work / (name + '.npz')); npz = np.load(work / (name + '.npz'))
    check_surface(solid, npz['positions'][npz['tris']], local)
    return dict(base=shape, shape=shape, jets=[(trial, mirror)], centre=centre.tolist(), fit=fit, error=error, seat=how, solid=solid, name=name,
                tri=npz['positions'][npz['tris']], log=log, yaw=yaw, rise=rise, slide=slide)


def fit_housing(jet, shape, mesh, stock, work, n):
    """Seat a housing on jet. When the configured shape clips stock mesh the pod is slid along
    the seat, then scaled down, then turned about the flame axis; the nozzle stays centred on
    the emit point throughout. The first variant that passes every check is used."""
    s = shape['scale']; ox, oz = shape.get('offset', (0., 0.)); vary = lambda **k: fitted(k.get('scale', s), shape['length'], **dict(shape['over'], **{n: v for n, v in k.items() if n != 'scale'}))
    if jet.get('relocate'):
        return relocate(jet, vary(offset=(0., 0.)) if (ox or oz) else shape, mesh, stock, work, n)
    tries = [(shape, 0, None)]
    tries += [(vary(offset=(round(ox + dx * s, 3), round(oz + dz * s, 3))), 0, 'pod slid (%+.2f, %+.2f) m along the seat' % (dx * s, dz * s))
              for step in (.1, .2) for dx, dz in ((step, 0), (-step, 0), (0, step), (0, -step))]
    tries += [(vary(scale=round(s * k, 3)), 0, 'scale %g -> %g' % (s, round(s * k, 3))) for k in (.85, .7, .8 / s) if s * k >= .8 and k < .999]
    tries += [(shape, yaw, 'pod turned %d degrees about the flame axis' % yaw) for yaw in (90, -90, 180)]
    failures = []
    for variant, yaw, label in tries:
        try:
            h = seat(jet, variant, yaw, mesh, stock, work, n)
        except (AssertionError, SystemExit) as problem:
            failures.append((label or 'as configured', problem.args[0] if problem.args and not isinstance(problem.args[0], str) else ([line for line in str(problem).splitlines() if 'AssertionError' in line] or [str(problem)[-200:]])[-1])); continue
        h['base'] = shape; trial, mirror = h['jets'][0]; jet.update(trial); h['jets'][0] = (jet, mirror)
        if label:
            h['adjusted'] = f"{label}, because as configured: {failures[0][1]}"
        return h
    raise AssertionError((jet['part'], 'no housing clears the stock mesh here', failures[0], '%d variants tried' % len(tries), failures[1:]))


def relocate(jet, shape, mesh, stock, work, n):
    """Seat a housing at the nearest spot on the nacelle skin that is flat and solid enough for
    it: the whole footprint covered, the skin within a few centimetres of the seat plane and
    nothing over the bore, so the nozzle sits centred on the new emit point right under the
    skin. Spots are tried nearest first, a slightly uneven one counting as 0.35 m further away
    and a poor one as 1 m."""
    s = shape['scale']; found = []; failures = []
    for dx in np.arange(-8, 9) * .1:
        for dz in np.arange(-8, 9) * .1:
            if math.hypot(dx, dz) <= .801:
                try:
                    how = seat(jet, shape, 0, mesh, stock, work, n, slide=(float(dx), float(dz)), dry=True)
                except AssertionError as problem:
                    if not dx and not dz:
                        failures.append(('at the stock point', problem.args[0]))
                    continue
                spread = 0 if shape.get('conform') else how['spread']  # a conformal roof follows uneven skin
                flat = 0 if how['cover'] > .999 and spread <= .05 * s and how['inside'] <= .08 * s else 1 if how['cover'] >= .95 and spread <= .1 * s and how['inside'] <= .15 * s else 2
                found.append((flat, math.hypot(dx, dz), float(dx), float(dz), how))
    for flat, far, dx, dz, how in sorted(found, key=lambda f: f[1] + (0, .35, 1.)[f[0]])[:10]:  # nearest first; a flat seat is worth 0.35 m
        try:
            h = seat(jet, shape, 0, mesh, stock, work, n, slide=(dx, dz))
        except (AssertionError, SystemExit) as problem:
            failures.append(('%+.1f, %+.1f' % (dx, dz), problem.args[0] if problem.args and not isinstance(problem.args[0], str) else ([line for line in str(problem).splitlines() if 'AssertionError' in line] or [str(problem)[-200:]])[-1])); continue
        h['base'] = jet['_base']; trial, mirror = h['jets'][0]; jet.update(trial); h['jets'][0] = (jet, mirror)
        if flat:
            h['adjusted'] = 'no flat, fully covered spot within 0.8 m: seated on the best there is (%s)' % ('slightly uneven or overhanging' if flat == 1 else 'uneven skin, deep nozzle')
        jet['reason'] = ('stock point: ' + str(failures[0][1])[:160]) if failures and failures[0][0] == 'at the stock point' else \
            'stays over the stock point (nothing nearer seats better); moved onto the skin only' if not far else 'stock point does not give a flat, fully covered seat with a clear bore'
        return h
    raise AssertionError((jet['part'], 'no spot on this nacelle within 0.8 m seats a housing that clears the stock mesh', failures[:6]))


def group(cfg, jets, mesh, pose, work):
    """Housings to build: emitters that seat alike (same shape, same skin under the pod, as it
    is or mirrored, the same clearances) share one solid; the first of each group is the one
    it is built on. An emitter whose flame runs into mesh within half a metre sits in modelled
    geometry (a duct or nozzle the author drew) and gets no housing; it is flagged instead."""
    out = []; whole = hull(mesh)[0]; stock = np.concatenate([p[tris] for name, p, _, _, tris in posed_parts(mesh, pose) if 'glass' not in name.lower()])
    for jet in jets:
        blocked = ahead(whole, np.array(jet['emit']), -np.array(jet.get('axes', np.eye(3)))[:, 1])
        if blocked is not None and .05 < blocked < .5 and not jet.get('toSkin'):  # nearer than that is the seat skin itself
            jet['skipped'] = f'sits in modelled geometry: mesh {blocked:.3f} m along the flame, no housing'; continue
        shape = next((s for pattern, s in cfg.get('also', ()) if re.search(pattern, jet['part'], re.I)), cfg['shape'])
        if shape.get('auto'):
            jet['_base'] = shape
            for h in out:
                if h['base'] is shape:
                    try:
                        trial, mirror = seat(jet, h['shape'], h['yaw'], mesh, stock, work, 0, h)
                    except AssertionError:
                        continue
                    jet.update(trial); h['jets'].append((jet, mirror)); break
            else:
                out.append(fit_housing(jet, shape, mesh, stock, work, len(out)))
            continue
        skin = hull(mesh, jet.get('skin', jet['bone']))[0]
        for h in out:
            mirror = jet['emit'][0] * h['centre'][0] < 0
            if h['shape'] is shape:
                try:
                    _, error, seat_ = underside(to_build(skin, jet, h['centre'], mirror), h['centre'], shape, h['fit'], h['seat'].get('roof'))
                except AssertionError:
                    continue
                if error < shape['bury'] * .5 and abs(seat_['cover'] - h['seat']['cover']) < .08 and not seat_['pokes'] and not seat_.get('roofGap'):
                    h['jets'].append((jet, mirror)); break
        else:  # its own solid, built on the +X side so one CONFIG offset serves both sides
            mirror = jet['emit'][0] < -1e-3; centre = np.array(jet['emit']) * ((-1., 1, 1) if mirror else (1., 1, 1))
            fit, error, seat_ = underside(to_build(skin, jet, centre, mirror), centre, shape)
            out.append(dict(base=shape, shape=shape, jets=[(jet, mirror)], centre=centre.tolist(), fit=fit, error=error, seat=seat_))
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
    out += [f"{j['part']}: emit point moved (%+.3f, %+.3f, %+.3f) m from the stock point (%.3f, %.3f, %.3f); not yet in the VDF" % (*j['emitShift']['delta'], *j['emitShift']['stock'])
            for j in jets if 'emitShift' in j]
    out += [f"{h['jets'][0][0]['part']}: {h['adjusted']}" for h in housings if h.get('adjusted')]
    out += [f"{j['part']}: class 75 flame part" + (f", rides the bone of {j['rides']}" if 'rides' in j else '') for j in jets if j.get('source')]
    for h, solid in zip(housings, solids):
        seat = solid.get('seated'); name = h['jets'][0][0]['part']
        if not seat:
            continue
        if seat['inside'] > .005:
            out.append(f"{name}: the nozzle hangs {seat['inside']:.2f} m below the emit point so stock mesh stays out of its throat (skin {seat['gap']:+.3f} m from the emit point)")
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
    font = ImageFont.truetype('arial.ttf', 20); w, h = images[0].size; rows = -(-len(images) // columns); lines = []
    for note in footer:  # wrap each note to the sheet width
        line = ''
        for word in note.split():
            if line and font.getlength(line + ' ' + word) > w * columns - 16:
                lines.append(line); line = '    ' + word
            else:
                line = (line + ' ' + word) if line else word
        lines.append(line)
    footer = lines
    out = Image.new('RGB', (w * columns, (h + 34) * rows + 28 * len(footer)), (24, 26, 28))
    for i, (image, caption) in enumerate(zip(images, captions)):
        x, y = i % columns * w, i // columns * (h + 34)
        out.paste(image.convert('RGB').resize((w, h)), (x, y)); ImageDraw.Draw(out).text((x + 8, y + h + 5), caption, fill=(232, 232, 226), font=font)
    for i, line in enumerate(footer):
        ImageDraw.Draw(out).text((8, (h + 34) * rows + 28 * i + 2), line, fill=(255, 214, 120), font=font)
    out.save(dest, quality=90)


def review_dir(shipping):
    """A --ship run writes the tracked sheets that match the shipped stage; previews stay local,
    so a preview of a shipped unit never leaves its tracked sheets out of step."""
    return ROOT / ('References/NacelleJets/review' if shipping else 'Local/NacelleJets/review-rollout')


def emit_shifts(jets):
    """Record each approved emit-point move: the VDF still carries the stock point."""
    for j in jets:
        if 'stockEmit' in j:
            D, shift = j['_pose']; a = D @ np.array(j['stockEmit']) + shift; b = np.array(j['posed']['emit'])
            j['emitShift'] = dict(stock=a.tolist(), moved=b.tolist(), delta=(b - a).tolist(), flame=j['posed']['flame'], space='Ogre mesh space in the VDF pose (VDF x = -x), metres')
            if 'stockFlame' in j:
                j['emitShift']['stockFlame'] = j['stockFlame']
            if j.get('reason'):
                j['emitShift']['reason'] = j['reason']


def vdf_parts(jets):
    """The class 75 flame parts the VDF needs once any emit point has moved: one per emitter,
    parented to its nacelle (an authored class 75 part suppresses every automatic emitter, so the
    unmoved ones are recorded too, at their stock points). matrix is the part's local transform
    in the VDF's own layout (rows right, up, front, then the position; world = local @ parent);
    the flame runs along front."""
    if not any('emitShift' in j or j.get('carrier') for j in jets):  # a carrier's flames always need parts
        return None
    out = []; taken = set(jets[0]['_vdf']['names'])
    for j in jets:
        v = j['_vdf']; Rp, tp = v['frame']; Q = np.array(j['posed']['axes']); front = -Q[:, 1]; up = Q[:, 2]
        Rc = ((np.c_[np.cross(up, front), up, front] * S[:, None]) * S[None, :]).T; local = (np.array(j['posed']['emit']) * S - tp) @ Rp.T
        name = v['existing']
        if name is None:
            n = v['parent']; f = 'F' if n[:5].isupper() else 'f'; name = (n[:5] + f + n[-2:])[:8]; k = 0
            while name.lower() in taken:  # two nacelles alike in their first five and last two letters
                name = (n[:5] + f + n[-2:])[:7] + str(k); k += 1
            taken.add(name.lower())
        part = dict(name=name, klass=75, parent=v['parent'], position=local.tolist(), orientation=(Rc @ Rp.T).tolist(),
                    matrix=(Rc @ Rp.T).ravel().tolist() + local.tolist(), existing=v['existing'] is not None, moved='emitShift' in j)
        if 'emitShift' in j:
            D, shift = j['_pose']; part['stockPosition'] = (((D @ np.array(j['stockEmit']) + shift) * S - tp) @ Rp.T).tolist()
        out.append(part)
    return out


def ports(mesh, skeleton, pose):
    """Glowing ports the model already carries: blobs of lit texels in each submesh's emissive
    map, located on the mesh in the VDF pose (centre, outward normal, radius, owning part)."""
    out = []; rng = np.random.default_rng(0)
    for sub, (name, positions, normals, uvs, tris) in zip(mesh.submesh_list, posed_parts(mesh, pose)):
        diffuse = texture_path(name); glow = diffuse and Path(str(diffuse).replace('_D.', '_E.').replace('DIFF', 'EMIS'))
        if not glow or not glow.is_file() or 'glass' in name.lower():
            continue
        image = np.asarray(Image.open(glow).convert('RGB'), float); h, w = image.shape[:2]; owner = np.full(len(positions), -1); weight = np.zeros(len(positions))
        for a in sub.bone_assignments():
            if a.weight > weight[a.vertex_index]:
                weight[a.vertex_index] = a.weight; owner[a.vertex_index] = a.bone_index
        tri = positions[tris]; area = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1) / 2; pts, nrm, own, col = [], [], [], []
        for i in range(len(tris)):
            b = rng.dirichlet((1, 1, 1), int(min(400, max(6, area[i] / .0004)))); uv = (b @ uvs[tris[i]]) % 1
            texel = image[(uv[:, 1] * h).astype(int).clip(0, h - 1), (uv[:, 0] * w).astype(int).clip(0, w - 1)]; lit = texel.max(1) > 150
            if lit.any():
                pts.append((b @ tri[i])[lit]); nrm.append((b @ normals[tris[i]])[lit]); own.append(np.full(lit.sum(), owner[tris[i, 0]])); col.append(texel[lit])
        if not pts:
            continue
        pts, nrm, own, col = map(np.concatenate, (pts, nrm, own, col))
        # one port = one connected lit patch (samples sit ~2 cm apart; a 5 cm link keeps the
        # unlit rim between neighbouring ports as a gap, so a big port and its small ones stay apart)
        pairs = cKDTree(pts).query_pairs(.05, output_type='ndarray'); n = len(pts)
        _, label = connected_components(coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])), shape=(n, n)), directed=False)
        groups = [label == k for k in np.unique(label)]
        while groups:
            member = groups.pop()
            if member.sum() >= 15:
                # two port rings that touch join into one patch: split one that is long in its own plane
                q = pts[member] - pts[member].mean(0); value, vector = np.linalg.eigh(q.T @ q / len(q))
                if value[2] > 2.2 * value[1]:
                    side = q @ vector[:, 2] > 0
                    for _ in range(5):  # two-means along the long axis
                        a, b = q[side].mean(0) @ vector[:, 2], q[~side].mean(0) @ vector[:, 2]; side = q @ vector[:, 2] > (a + b) / 2
                    if side.all() or not side.any():
                        side[:len(side) // 2] = ~side[:len(side) // 2]
                    index = np.flatnonzero(member); one = np.zeros_like(member); one[index[side]] = True
                    groups += [one, member & ~one]; continue
                c = pts[member].mean(0); bone = int(np.bincount(own[member] + 1).argmax()) - 1
                out.append(dict(centre=c.tolist(), normal=unit_vectors(nrm[member].mean(0)).tolist(), radius=float(np.percentile(np.linalg.norm(pts[member] - c, axis=1), 95)),
                                part=skeleton.bones[bone].name if bone >= 0 else None, bone=bone, colour=[round(float(v)) for v in col[member].mean(0)]))
    return out


def into_ports(jets, found):
    """Propose each flame into the largest glowing port its own nacelle carries, along the port's normal."""
    notes = []
    for j in jets:
        mine = sorted((p for p in found if p['bone'] == j.get('skin', j['bone']) and p['normal'][1] < .3), key=lambda p: -p['radius'])  # a lit patch facing up is a marking, not an exhaust
        if not mine:
            notes.append(f"{j['part']}: its nacelle carries no glowing port; the flame stays at the stock point, on bare mesh"); continue
        port = mine[0]; n = np.array(port['normal']); D, shift = j['_pose']; y = -n; up = np.array((0., 0, 1) if abs(n[1]) > .9 else (0., 1, 0))
        z = unit_vectors(up - (up @ y) * y); Q = np.c_[np.cross(y, z), y, z]; below = math.degrees(math.asin(max(-1., min(1., -n[1]))))
        j['stockEmit'] = j['emit']; j['stockFlame'] = j['posed']['flame']; j.update(emit=(D.T @ (np.array(port['centre']) - shift)).tolist(), axes=(D.T @ Q).tolist()); place(j)
        j['reason'] = 'into the largest of the %d glowing ports modelled on this nacelle (radius %.2f m)' % (len(mine), port['radius'])
        facing = 'aft' if n[2] < -.5 else 'forward' if n[2] > .5 else 'down' if n[1] < -.5 else 'sideways or up'
        notes.append(f"{j['part']}: {len(mine)} glowing ports on this nacelle ({', '.join('r %.2f' % p['radius'] for p in mine)}), facing {facing}, {below:.0f} degrees below horizontal; "
                     + 'they are on the engine nacelle, not on a weapon part, so they read as thruster exhausts. '
                     + ('The proposed flame leaves along the port normal, so it points aft, not down: right for an exhaust, but it is no longer a hover jet under the craft.' if below < 30 else
                        'The proposed flame leaves along the port normal, down and aft.' if below < 70 else 'The proposed flame leaves straight down.'))
    return notes


def emit_only(unit, cfg, mesh, skeleton, jets, pose, work, review, revision, render, shipped=False):
    """A unit that gets no housing: its emit points (and approved moves) on record and on a sheet.
    The mesh is not changed; --ship only writes the tracked receipt, whose vdfParts the VDF builder reads."""
    found = ports(mesh, skeleton, pose) if cfg.get('ports') else []; marks = [dict(at=j['posed']['emit'], colour=(0, .9, 1), radius=.05) for j in jets] if found else []
    extra = into_ports(jets, found) if found else []; marks += [dict(at=q['centre'], colour=(1, 1, 0), radius=.025) for q in found]
    emit_shifts(jets); keep = ('part', 'bone', 'pivot', 'emit', 'axes', 'source', 'rides', 'emitShift')
    notes = [f"{unit}: {cfg['note']}"] + extra + notes_for(jets, [], [])
    receipt = dict(unit=unit, faction=cfg['faction'], emitters=[{k: j[k] for k in keep if k in j} for j in jets],
                   baseRevision=revision, housings=[], ports=found, vdfParts=vdf_parts(jets), notes=notes)
    (work / 'preview.json').write_text(json.dumps(receipt, indent=2) + '\n', newline='\n')
    if shipped:
        record = ROOT / 'References/NacelleJets' / unit / 'build.json'; record.parent.mkdir(exist_ok=True)
        record.write_text(json.dumps(receipt, indent=2) + '\n', newline='\n')
    for note in notes:
        print(unit, 'note:', note)
    if not render:
        return
    parts = []
    for i, (name, positions, normals, uvs, tris) in enumerate(posed_parts(mesh, pose)):
        if 'glass' in name.lower():
            continue
        file = work / f'part{i}.npz'; np.savez(file, positions=positions, normals=normals, uvs=uvs, tris=tris); texture = texture_path(name)
        if texture:
            Image.open(texture).convert('RGB').save(work / f'part{i}_D.png'); texture = str(work / f'part{i}_D.png')
        parts.append(dict(mesh=str(file), housing=False, diffuse=texture))
    points = np.array([j['posed']['emit'] for j in jets]); middle = points.mean(0); flame = unit_vectors(np.array([j['posed']['flame'] for j in jets]).mean(0))
    views = [dict(file='emit-below', eye=list(middle + flame * 5 + (0, -1.5, 0)), target=list(middle), fov=40, marker=True, flame=False, housing=False, markerScale=1.6),
             dict(file='craft', eye=list(middle + flame * 5 + (3, -1.5, 0)), target=list(middle), fov=40, marker=True, flame=True, housing=False, markerScale=1.6)]
    if found:
        views += [dict(file='under', eye=list(middle + (0, -7, -1.5)), target=list(middle), fov=40, marker=True, flame=True, housing=False, markerScale=1.6),
                  dict(file='side', eye=list(middle + (8, -.5, -1.)), target=list(middle), fov=40, marker=True, flame=True, housing=False, markerScale=1.6)]
    views += [dict(file=f'close{n}', eye=list(e + np.array(j['posed']['flame']) * 2.2 + (1.2 if e[0] >= 0 else -1.2, -.9, 0)), target=list(e), fov=30, marker=True, flame=True, housing=False)
              for n, (e, j) in enumerate(zip(points, jets))]
    if found:  # the same close-ups without the cone, so the port it sits in shows
        views += [dict(v, file=v['file'].replace('close', 'bare'), flame=False) for v in views if v['file'].startswith('close')]
    (work / 'scene.json').write_text(json.dumps(dict(parts=parts, out=str(work), emit=points.tolist(), flameDir=[j['posed']['flame'] for j in jets], views=views, marks=marks,
                                                     flame=dict(halfWidth=.2, length=.9), size=[960, 600]), indent=1))
    blender('nacellejet_render.py', work / 'scene.json')
    sheet([Image.open(work / (v['file'] + '.png')) for v in views],
          ['Magenta = emit points' + ('; cyan = stock; yellow = ports' if found else ''), 'Flames along each part\'s front axis']
          + (['From below', 'From the side'] if found else []) + ['%s at (%.3f, %.3f, %.3f)' % (j['part'], *j['posed']['emit']) for j in jets]
          + (['%s, no flame: the port under the magenta dot' % j['part'] for j in jets] if found else []), review / f'{unit}-emit.jpg', 2, notes)


def build(unit, render, shipped=False):
    cfg = CONFIG[unit]; faction = FACTIONS[cfg['faction']]; material = unit + '_nacjet'
    work = ROOT / 'Local/NacelleJets' / unit; review = review_dir(shipped)
    work.mkdir(parents=True, exist_ok=True); review.mkdir(parents=True, exist_ok=True)
    for stale in (work / 'contact.png', work / 'preview.json'):  # a unit that fails a check leaves no earlier preview behind
        stale.unlink(missing_ok=True)
    mesh, skeleton, revision = stage_base(unit, work)
    jets, pose = emitters(unit, skeleton, mesh, cfg.get('shift', ()), cfg.get('carrier'))
    if cfg.get('housing') is False:
        return emit_only(unit, cfg, mesh, skeleton, jets, pose, work, review, revision, render, shipped)
    housings = group(cfg, jets, mesh, pose, work)
    nacelle = None
    if any(j.get('carrier') for j in jets):
        assert all(j['bone'] == jets[0]['bone'] for j in jets) and not any('skipped' in j for j in jets), 'every carrier housing rides the new nacelle'
        W = vdf_world(legacy.read_vdf(base_vdf(unit)).band(0))[0]; nacelle = carrier_frames(jets, cfg['carrier'], W, skeleton, pose)
        nacelle['skeletonSource'] = next(p for p in (wr.GAME / 'BZ_ASSETS/common/models').rglob('*.skeleton')
                                         if p.name.lower() == mesh.skeleton_name.lower()).relative_to(wr.GAME / 'BZ_ASSETS/common/models').as_posix()
        nacelle['skeleton'] = mesh.skeleton_name
    if not housings[0]['shape'].get('auto'):
        paint, source = paint_colour(mesh, housings[0]['jets'][0][0]['bone'])
    cells = math.ceil(math.sqrt(len(housings))); atlas = {}; data, faces, owner, solids, counts = [], [], [], [], []
    for n, h in enumerate(housings):
        ref = h['jets'][0][0]; name = h.get('name') or ('solid' if len(housings) == 1 else 'solid%d' % n)
        if 'solid' in h:  # seated and built by the search, on the paint of the skin it sits on
            solid, log = h['solid'], h['log']; paint, source = seat_paint(mesh, ref, np.array(h['centre']), h['jets'][0][1], h['shape'], h['fit'])
        else:
            solid = solid_config(h['shape'], h['centre'], h['fit'], h['seat']); (work / (name + '.json')).write_text(json.dumps(solid, indent=1))
            log = blender('nacellejet_blender.py', work / (name + '.json'), work / (name + '.npz'))
        h['paint'] = paint
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
    if nacelle:  # the housings in the VDF pose, for the new nacelle's GEO
        posed = [p for name, p, _, _, _ in posed_parts(shared.read_mesh(work / (unit + '.mesh')), pose) if name == material][0]
        rows = np.concatenate(data).astype(float); rows[:, :3] = posed; rows[:, 3:6] = rows[:, 3:6] @ pose[nacelle['bone']['handle']][0].T
        (work / nacelle['geo']).write_bytes(nacelle_geo(nacelle, rows, np.concatenate(faces), np.concatenate(owner), unit))
    first = housings[0]; keep = ('part', 'bone', 'skin', 'pivot', 'emit', 'axes', 'yaw', 'source', 'carrier', 'rides', 'estimate', 'skipped', 'emitShift')
    paint = first['paint']; emit_shifts(jets)
    receipt = dict(unit=unit, faction=cfg['faction'], material=material, emitters=[{k: j[k] for k in keep if k in j} for j in jets],
                   flameDirection=[0, -1, 0], baseRevision=revision,
                   wingUnderside=dict(heightAtEmit=first['fit'][0], slopePerMetreOfChord=first['fit'][1], maxError=first['error']), paint=paint,
                   paintSource=source.relative_to(ROOT).as_posix() if source.is_relative_to(ROOT) else source.name,
                   housing=counts[0], shape=first['shape'], stripe=cfg.get('stripe') or first['shape']['stripe'])
    notes = notes_for(jets, housings, solids)
    parts = vdf_parts(jets)
    if parts:
        receipt['vdfParts'] = parts
    if nacelle:  # Tools/Build-UnitAnimSlots.py adds the part and the bone; the ODF carries the gains
        receipt['newNacelles'] = [nacelle]
    if first['shape'].get('auto'):  # fitted shapes: how each solid seats, and who carries it
        receipt.update(flameDirection='-y of each emitter frame', notes=notes, housings=[
            dict(counts[n], parts=[j['part'] for j, _ in h['jets']], mirrored=[m for _, m in h['jets']], underside=h['fit'], maxError=h['error'],
                 seated=solids[n]['seated'], shape=h['shape'], paint=h['paint'], adjusted=h.get('adjusted')) for n, h in enumerate(housings)])
    (work / 'preview.json').write_text(json.dumps(receipt, indent=2) + '\n', newline='\n')
    if shipped:  # a preview run leaves the tracked receipt alone
        receipt['stageMesh'] = ship(unit, material, work)  # sha256 of the pre-rig Assets/ModelFixes mesh
        for n in receipt.get('newNacelles', ()):
            shutil.copyfile(work / n['geo'], ROOT / 'Assets/ModelFixes' / n['geo'])
        record = ROOT / 'References/NacelleJets' / unit / 'build.json'; record.parent.mkdir(exist_ok=True)
        record.write_text(json.dumps(receipt, indent=2) + '\n', newline='\n')
        if (ROOT / 'References/HardpointMounts' / f'{unit}.json').is_file():  # stage_base predates the mount
            sys.exit(f'{unit}: the new stage was rebuilt from the pre-mount weapon-rig source revision and has dropped its '
                     f'hardpoint mount ({unit}_hpmount). Commit this stage, set CONFIG["{unit}"]["base"] in '
                     f'Tools/Build-HardpointMounts.py to that commit, and re-run '
                     f'"python Tools/Build-HardpointMounts.py --units {unit} --ship" before the weapon-rig sequence.')
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
