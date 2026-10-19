#!/usr/bin/env python3
"""Build the building/production animation polish (Assets/ModelFixes): spinning turbines and
the CCA armory launch swing.

SDF/VDF, Ogre mesh/skeleton and GEO reading and writing all go through the shared model libraries
(Tools/bzmodellibs.py: BZ98RBlenderToolKit bzrmodelporter); nothing here packs ANIM or mesh bytes.
Stock inputs are read, never written: the stock SDF/VDF files are extracted from the Redux bzone.zfs
(--stock-dir, or read straight from the archive with the Modding Toolbox) and the stock cbwpow
mesh/skeleton come from the Redux install.

What each model gets:

  abwpow  (NSDF wind power)    ANIM element 4: the rotor awp11spc (carries awp11spd/spe) turns about
                               the vertical axis, 6 rpm.
  sbwpow  (CCA wind power)     ANIM element 4: the propeller swp11prp turns, 10 rpm. Stock already keys a
                               full turn in element 0, which PowerPlant never plays.
  sblpow  (CCA lightning)      ANIM element 4: the four base clamps sls11cla..d (own bones) carry round the
                               dome, 3 rpm. The tower's disc sls11twb is rotationally symmetric, so
                               turning it would show nothing. sblpowa/sblpowb share this through baseName.
  svslf   (CCA armory)         Redux's stock svslf.vdf has no ANIM chunk at all. One is built: element 4 (what
                               Producer plays when deploy finishes and Armory::LaunchItem plays on every pod
                               launch) swings slf11arm up and back once. One-shot (loop 1): both call sites
                               start 4 without stopping the previous play, so a looping 4 would leak an
                               active-list slot per launch. The swing is the N64 Battlezone SLF launch clip
                               (88 degree raise in 8 frames, return in 22), keyed on every frame.
  cbwpow  (CRA wind power)     The turbine (hub star, eight blades, spoked wheel) is loose geometry in the
                               one-bone mesh. It moves onto a new bone cwp11rot, a matching GEO is added to
                               the SDF (with a small cwp11rot.geo), and ANIM element 4 turns it, 7.5 rpm.
  abspow                       Left alone: PowerPlant plays element 4 once, so a spin after the unfold would
                               need either losing the unfold or a second element started by script.

PowerPlant::PowerPlant plays element 4 (loop 0 = forever). Every spin is keyed on every frame, the first and
last key are the same pose, and the element length is the keyed range, because ComputeFrameToPlay wraps at
start + length - 1. A part's keys must reach the last frame of the element: past a part's last key the
engine falls back to its FIRST key.

Key quaternions: the libraries have no transform -> ANIM key helper, so the convention is derived from the
stock files here (Transform.compute_orientation(), then (w, -x, -y, +z)). It matches 131 of the 145 stock
parts that hold a constant key, using each part's ANIM record matrix; Test-BuildingAnimations.py re-checks it against the stock files.

  python Tools/Build-BuildingAnimations.py [--stock-dir DIR] [--game <Redux dir>]
"""
import argparse
import importlib
import io
import math
import os
import sys
import tempfile
from collections import defaultdict

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bzmodellibs as libs  # noqa: E402

bwd2 = libs.bwd2
ser = libs.bwd2_serializer
ogremesh_ser = libs.ogremesh_serializer
ogreskel_ser = libs.ogreskeleton_serializer
geo = libs.geo
geo_ser = libs.geo_serializer
sp = importlib.import_module("bzrmodelporter.spacial")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Assets", "ModelFixes")
DEFAULT_GAME = r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"

FPS = 15.0

# name -> (parts, axis in the parts' parent frame, rpm, orbit). Frames per revolution = 60 * FPS / rpm.
# orbit=True: the parts sit off the axis, so their positions travel around it as well as turning.
SPINS = {
    "abwpow": (("awp11spc",), (0.0, 1.0, 0.0), 6.0, False),
    "sbwpow": (("swp11prp",), (0.0, 0.0, 1.0), 10.0, False),
    "sblpow": (("sls11cla", "sls11clb", "sls11clc", "sls11cld"), (0.0, 1.0, 0.0), 3.0, True),
    "cbwpow": (("cwp11rot",), (0.0, 0.0, 1.0), 7.5, False),
}

# N64 SLF launch clip (ROTBD mod_v10 svslf.blend, action slf11topAction, joint 1): X rotation in radians
# per frame 0..30, rest = 1.5708. The rear (-Z) of the arm swings up 88 degrees in 8 frames, then lowers.
N64_LAUNCH = [1.5708, 1.3752, 1.1673, 0.9507, 0.7302, 0.5110, 0.2982, 0.0961, 0.0316, 0.0961, 0.1621, 0.2295,
              0.2982, 0.3681, 0.4391, 0.5110, 0.5836, 0.6567, 0.7302, 0.8038, 0.8774, 0.9507, 1.0236, 1.0958,
              1.1673, 1.2378, 1.3071, 1.3752, 1.4419, 1.5071, 1.5708]


# ---------------------------------------------------------------------------- math
def rot_matrix(axis, angle):
    n = math.sqrt(sum(a * a for a in axis))
    x, y, z = (a / n for a in axis)
    c, s = math.cos(angle), math.sin(angle)
    t = 1 - c
    return [[t * x * x + c, t * x * y - s * z, t * x * z + s * y],
            [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
            [t * x * z - s * y, t * y * z + s * x, t * z * z + c]]


def apply(m, v):
    return tuple(sum(m[r][c] * v[c] for c in range(3)) for r in range(3))


def columns(t):
    """(right, up, front) of a Transform as vectors in the parent frame."""
    return (t.rx, t.ry, t.rz), (t.ux, t.uy, t.uz), (t.fx, t.fy, t.fz)


def key_of(right, up, front):
    """The ANIM key quaternion (w, x, y, z) of a part whose axes are right/up/front in its parent frame."""
    q = sp.Transform(*right, *up, *front, 0, 0, 0).compute_orientation()
    return (q.w, -q.x, -q.y, q.z)


# ---------------------------------------------------------------------------- bwd2 files
def read_bwd(data, kind):
    cls = ser.SDFSerializer if kind == "sdf" else ser.VDFSerializer
    return cls(io.BytesIO(data)).read()


def write_bwd(model, kind):
    cls = ser.SDFSerializer if kind == "sdf" else ser.VDFSerializer
    out = io.BytesIO()
    cls(out).write(model)
    return out.getvalue()


class Tracks:
    """Per-part key lists of an AnimObj, editable then committed back (the shared key tables are rebuilt
    in part order)."""

    def __init__(self, anim, empty=False):
        self.anim = anim
        self.rots, self.poss, self.scales = {}, {}, {}
        for name, mesh in anim.mesh_map.items():
            if empty:
                self.rots[name], self.poss[name], self.scales[name] = [], [], []
                continue
            self.rots[name] = [(k.frame, (k.orientation.w, k.orientation.x, k.orientation.y, k.orientation.z))
                               for k in mesh.get_orientations()]
            self.poss[name] = [(k.frame, (k.position.x, k.position.y, k.position.z)) for k in mesh.get_positions()]
            self.scales[name] = [(k.frame, (k.scale.x, k.scale.y, k.scale.z)) for k in mesh.get_scales()]

    def commit(self):
        a = self.anim
        a.orientation_keyframe_list, a.scale_keyframe_list, a.position_keyframe_list = [], [], []
        for name, mesh in a.mesh_map.items():
            mesh.orientation_start, mesh.orientation_length = len(a.orientation_keyframe_list), len(self.rots[name])
            for f, q in sorted(self.rots[name]):
                a.create_orientation_keyframe(f, sp.Quaternion(*q))
            mesh.scale_start, mesh.scale_length = len(a.scale_keyframe_list), len(self.scales[name])
            for f, v in sorted(self.scales[name]):
                a.create_scale_keyframe(f, sp.Vector3(*v))
            mesh.position_start, mesh.position_length = len(a.position_keyframe_list), len(self.poss[name])
            for f, v in sorted(self.poss[name]):
                a.create_position_keyframe(f, sp.Vector3(*v))


def set_element(anim, index, start, length, loop, speed):
    """Create or replace ANIM element `index`. The part flags are 1 for every part, as stock avslf."""
    el = anim.create_animation(index)
    el.start, el.length, el.loop, el.speed = start, length, loop, speed
    el.mesh_index_list[:] = [1 if k < len(anim.mesh_map) else 0 for k in range(32)]
    return el


def spin_keys(t, axis, frames):
    """Rotation keys (frame, stored quaternion) for one revolution about `axis` (parent frame) on every
    frame 0..frames, the last equal to the first. The part keeps its bind: R_axis(theta) applied after it."""
    r, u, f = columns(t)
    out = []
    for fr in range(frames + 1):
        m = rot_matrix(axis, 2.0 * math.pi * fr / frames)
        q = key_of(apply(m, r), apply(m, u), apply(m, f))
        if out and sum(a * b for a, b in zip(q, out[-1][1])) < 0:
            q = tuple(-c for c in q)  # stay in one hemisphere, so SLERP between keys never takes the long way
        out.append((fr, q))
    return out


def new_anim(name):
    """A fresh AnimObj. Library gap: bzbwd2.AnimObj() names its key-table pointers *_keyframes_ptr while
    the serializer reads *_keyframe_ptr, so a new one cannot be written until upstream is fixed; set the
    names the serializer wants (all zero, as every stock file)."""
    anim = bwd2.AnimObj()
    anim.name = name
    anim._orientation_keyframe_ptr = anim._scale_keyframe_ptr = anim._position_keyframe_ptr = 0
    return anim


# ---------------------------------------------------------------------------- spin SDFs
def orbit_keys(pos, axis, frames):
    """Position keys for a part at `pos` carried one revolution round `axis` through the parent origin."""
    return [(fr, apply(rot_matrix(axis, 2.0 * math.pi * fr / frames), pos)) for fr in range(frames + 1)]


def spin_sdf(data, name):
    parts, axis, rpm, orbit = SPINS[name]
    frames = int(round(60.0 * FPS / rpm))
    sdf = read_bwd(data, "sdf")
    if sdf.anim_obj is None:
        sys.exit("%s has no ANIM chunk" % name)
    anim = sdf.anim_obj
    tracks = Tracks(anim)
    for part_name in parts:
        # the bind is the ANIM record's own matrix (the GEO record's differs on some stock parts)
        t = anim.mesh_map[part_name].frame_transform
        tracks.rots[part_name] = spin_keys(t, axis, frames)
        if orbit:
            tracks.poss[part_name] = orbit_keys((t.px, t.py, t.pz), axis, frames)
    # Every part's keys must reach the last frame of the element.
    for n in anim.mesh_map:
        poss = tracks.poss[n]
        if poss and max(f for f, _ in poss) < frames:
            poss.append((frames, poss[0][1]))
        rots = tracks.rots[n]
        if n not in parts and rots and max(f for f, _ in rots) < frames:
            rots.append((frames, rots[0][1]))
    tracks.commit()
    anim.animation_map.pop(4, None)
    set_element(anim, 4, 0, frames + 1, 0, FPS)
    return write_bwd(sdf, "sdf")


# ---------------------------------------------------------------------------- svslf
READY_DEG = 20.0                 # the deployed ("ready") elevation of the arm; the model's bind pose is 0
DEPLOY_FRAMES = 76               # element 0: 75 intervals at 15 fps = timeDeploy 5 s
LAUNCH_START = DEPLOY_FRAMES     # element 4 starts where the unfold ended (same pose)
SWING_UP = [N64_LAUNCH[0] - a for a in N64_LAUNCH]   # radians the rear of the arm is raised, 0 .. 1.539 .. 0
SWING_PEAK = max(SWING_UP)


def lift_key(r, u, f, alpha):
    """Key for the arm raised by `alpha` radians (rear, -Z, up). Stock keys are the engine's inverse of the
    SDF-frame rotation: Redux writes bone orientation (w, -x, y, z), so a lift is a NEGATIVE rotation about X
    in the Hamilton frame used here (confirmed live: +alpha swung the arm under the body)."""
    m = rot_matrix((1.0, 0.0, 0.0), -alpha)
    return key_of(apply(m, r), apply(m, u), apply(m, f))


def hemisphere(keys):
    out = []
    for fr, q in keys:
        if out and sum(a * b for a, b in zip(q, out[-1][1])) < 0:
            q = tuple(-c for c in q)
        out.append((fr, q))
    return out


def arm_lifts():
    """(frame, lift in radians) for the three elements, on one shared timeline."""
    ready = math.radians(READY_DEG)
    out = []
    for fr in range(DEPLOY_FRAMES):                      # element 0 (and 1 reversed): eased unfold 0 -> ready
        t = fr / (DEPLOY_FRAMES - 1)
        out.append((fr, ready * (t * t * (3 - 2 * t))))
    for k, up in enumerate(SWING_UP):                    # element 4: ready -> N64 peak (88 deg) -> ready
        out.append((LAUNCH_START + k, ready + up * (math.radians(88.0) - ready) / SWING_PEAK))
    return out


def svslf_vdf(data, mesh_check=None):
    vdf = read_bwd(data, "vdf")
    if vdf.get_object_by_name("slf11arm") is None:
        sys.exit("svslf.vdf has no slf11arm GEO")
    anim = new_anim("svslf.t")
    vdf.anim_obj = anim
    for obj in vdf.primary_objects():
        anim.create_animation_mesh(obj.name).frame_transform = obj.transform
    tracks = Tracks(anim, empty=True)
    last = LAUNCH_START + len(N64_LAUNCH) - 1
    lifts = arm_lifts()
    for obj in vdf.primary_objects():
        t = obj.transform
        pos = (t.px, t.py, t.pz)
        tracks.poss[obj.name] = [(0, pos), (last, pos)]
        r, u, f = columns(t)
        rest = key_of(r, u, f)
        if abs(rest[0]) < 0.9999:
            tracks.rots[obj.name] = [(0, rest), (last, rest)]
        if obj.name == "slf11arm":
            tracks.rots[obj.name] = hemisphere([(fr, lift_key(r, u, f, a)) for fr, a in lifts])
    tracks.commit()
    set_element(anim, 0, 0, DEPLOY_FRAMES, 1, FPS)                       # Producer: deploy start
    set_element(anim, 1, DEPLOY_FRAMES - 1, -DEPLOY_FRAMES, 1, FPS)      # Producer: undeploy (the unfold backwards)
    set_element(anim, 4, LAUNCH_START, len(N64_LAUNCH), 1, FPS)          # Producer deploy done + Armory::LaunchItem
    return write_bwd(vdf, "vdf")


def arm_lowest_points(game):
    """Per-frame lowest point of the arm geometry through the three elements (Ogre frame, engine rule:
    bone orientation = (w, -x, y, z) of the stored key). Returns (hinge y, rest lowest y, [(frame, lowest y)])."""
    models = os.path.join(game, "BZ_ASSETS", "common", "models")
    with open(os.path.join(models, "svslf.mesh"), "rb") as fh:
        mesh = ogremesh_ser.MeshSerializer(fh).read()
    with open(os.path.join(models, "svslf.skeleton"), "rb") as fh:
        skel = ogreskel_ser.SkeletonSerializer(fh).read()
    sm = mesh.get_submesh(0)
    pos = vertex_positions(sm)
    arm = skel.get_bone_by_name("slf11arm")
    verts = sorted({v.vertex_index for v in sm.bone_assignments_unsorted() if v.bone_index == arm.handle})
    p = pos[verts]
    pivot = np.zeros(3)
    b = arm
    while b is not None:
        pivot += (b.position.x, b.position.y, b.position.z)
        b = b.parent
    out = []
    for fr, a in arm_lifts():
        # the key's engine rotation is a lift of +a about Ogre X (see lift_key)
        c, s = math.cos(a), math.sin(a)
        y = pivot[1] + (p[:, 1] - pivot[1]) * c - (p[:, 2] - pivot[2]) * s
        out.append((fr, float(y.min())))
    return float(pivot[1]), float(p[:, 1].min()), out


# ---------------------------------------------------------------------------- cbwpow
def vertex_positions(sm):
    vd = sm.vertex_data
    el = vd.vertex_declaration.get_position_vertex_element()
    vb = vd.get_vertex_buffer(el.source)
    raw = np.frombuffer(vb.get_buffer(), dtype=np.uint8).reshape(vd.vertex_count, vb.vertex_size)
    return raw[:, el.offset:el.offset + 12].copy().view("<f4").reshape(-1, 3)


def cbwpow_models(game, out):
    models = os.path.join(game, "BZ_ASSETS", "common", "models", "TRO")
    with open(os.path.join(models, "cbwpow.mesh"), "rb") as fh:
        mesh = ogremesh_ser.MeshSerializer(fh).read()
    with open(os.path.join(models, "cbwpow.skeleton"), "rb") as fh:
        skel = ogreskel_ser.SkeletonSerializer(fh).read()
    sm = mesh.get_submesh(0)
    pos = vertex_positions(sm)
    faces = sm.get_index_array().reshape(-1, 3)
    # connected components over welded positions
    parent = {}

    def find(k):
        while parent.setdefault(k, k) != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    key = lambda i: tuple(np.round(pos[i], 3).tolist())
    for f in faces:
        ks = [key(i) for i in f]
        for k in ks[1:]:
            parent[find(k)] = find(ks[0])
    comp = defaultdict(set)
    for f in faces:
        comp[find(key(f[0]))].update(int(i) for i in f)
    rotor = [v for v in comp.values()
             if len(v) < 5000 and pos[list(v)][:, 2].min() > -4.1 and pos[list(v)][:, 2].max() < -3.7]
    allv = sorted(set().union(*rotor))
    p = pos[allv]
    lo, hi = p.min(axis=0), p.max(axis=0)
    cx, cy, cz = (lo + hi) / 2
    radius = float(max(hi[0] - cx, cx - lo[0], hi[1] - cy, cy - lo[1]))
    # the rotor must be a disc about its centre: wheel, star hub and eight blades
    assert abs(cx) < 0.05 and 2.0 < radius < 3.5 and len(rotor) == 10, (cx, cy, cz, radius, len(rotor))
    moved = set(allv)
    for vba in sm.bone_assignments_unsorted():
        if vba.vertex_index in moved:
            vba.bone_index = 1
    bone = skel.create_bone("cwp11rot", 1, sp.Vector3(0.0, float(round(cy, 5)), float(round(cz, 5))))
    skel.parent_bone(bone, skel.get_bone_by_name("cwp11bda"))
    with open(os.path.join(out, "cbwpow.mesh"), "wb") as fh:
        ogremesh_ser.MeshSerializer(fh).write(mesh)
    with open(os.path.join(out, "cbwpow.skeleton"), "wb") as fh:
        ogreskel_ser.SkeletonSerializer(fh).write(skel)
    print("cbwpow: rotor = %d components, %d vertices, centre (%.3f, %.3f, %.3f), radius %.2f -> bone cwp11rot"
          % (len(rotor), len(allv), cx, cy, cz, radius))
    return (0.0, float(cy), float(cz)), radius, tuple(float(x) for x in hi - lo)


def make_geo(name, radius, depth):
    """A small octagonal prism (native collision/fallback for the cwp11rot part), in the part's frame."""
    g = geo.Geo()
    g.name = name
    n, r, h = 8, radius * 0.92, depth / 2.0
    pts = [(r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n), z) for z in (-h, h) for k in range(n)]
    g.vert_count = len(pts)
    g.vertex_pos_buffer = np.array(pts, dtype="<3f")
    g.vertex_normal_buffer = np.array([(p[0] / r, p[1] / r, 0.0) for p in pts], dtype="<3f")
    tris = []
    for k in range(n):
        a, b = k, (k + 1) % n
        tris += [(a, b, b + n), (a, b + n, a + n)]
    for k in range(1, n - 1):
        tris += [(0, k + 1, k), (n, n + k, n + k + 1)]
    for i, t in enumerate(tris):
        face = g.create_face(i)
        face.color = sp.Color3(255, 255, 255)
        a, b, c = (np.array(pts[j]) for j in t)
        nv = np.cross(b - a, c - a)
        nv = nv / (np.linalg.norm(nv) or 1.0)
        face.plane = geo.SurfacePlane(sp.Vector3(*(-nv)), float(nv.dot(a)))
        face.texture_name = name + ".map"
        for j in t:
            face.create_face_node(j, j, sp.UV(0.0, 0.0))
    out = io.BytesIO()
    geo_ser.GeoSerializer(out).write(g)
    return out.getvalue()


def cbwpow_sdf(data, pivot, radius, extents):
    """Add the GEO cwp11rot (parent cwp11bda) and the ANIM chunk with the turn."""
    sdf = read_bwd(data, "sdf")
    assert sdf.object_count() == 1
    body = sdf.get_object_by_name("cwp11bda")
    # Library gap: append_object() leaves the new records without the .parent string the serializer writes,
    # so every band's new slot goes through create_geo_object; unused bands copy their NULL slot 0.
    for lod in range(3):
        for rep in range(2):
            ref = sdf.get_object(lod, rep, 0, raw=True)
            new = sdf.create_geo_object(lod, rep, 1, "NULL", "NULL")
            new.class_id, new.object_flags = ref.class_id, ref.object_flags
    obj = sdf.create_geo_object(0, 0, 1, "cwp11rot", "cwp11bda")
    obj.parentname = "cwp11bda"
    obj.transform = sp.Transform(1, 0, 0, 0, 1, 0, 0, 0, 1, pivot[0], pivot[1], pivot[2])
    obj.center_pos = sp.Vector3(0.0, 0.0, 0.0)
    obj.radius = radius
    obj.half_size = sp.Vector3(extents[0] / 2, extents[1] / 2, extents[2] / 2)
    obj.class_id, obj.object_flags = body.class_id, body.object_flags
    obj.ddr, obj.target, obj.time = body.ddr, sp.Vector3(), 0.0
    (part_name,), axis, rpm, _ = SPINS["cbwpow"]
    frames = int(round(60.0 * FPS / rpm))
    anim = new_anim("cbwpow.t")
    sdf.anim_obj = anim
    for o in sdf.primary_objects():
        anim.create_animation_mesh(o.name).frame_transform = o.transform
    tracks = Tracks(anim, empty=True)
    for o in sdf.primary_objects():
        pos = (o.transform.px, o.transform.py, o.transform.pz)
        tracks.poss[o.name] = [(0, pos), (frames, pos)]
        if o.name == part_name:
            tracks.rots[o.name] = spin_keys(o.transform, axis, frames)
    tracks.commit()
    set_element(anim, 4, 0, frames + 1, 0, FPS)
    return write_bwd(sdf, "sdf")


# ---------------------------------------------------------------------------- driver
def stock_files(args):
    if args.stock_dir:
        return args.stock_dir
    libs.legacy  # noqa: B018  (puts the Modding Toolbox on sys.path)
    from battlezone.archives.zfs import ZFSArchive
    tmp = tempfile.mkdtemp(prefix="cr_stock_")
    arc = ZFSArchive(os.path.join(args.game, "bzone.zfs"))
    want = {"abwpow.sdf", "sbwpow.sdf", "sblpow.sdf", "svslf.vdf", "cbwpow.sdf"}
    arc.extract([e for e in arc if e.name.lower() in want], tmp)
    return tmp


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", default=DEFAULT_GAME)
    ap.add_argument("--stock-dir", help="directory with the stock abwpow/sbwpow/sblpow/cbwpow .sdf and svslf.vdf "
                                        "extracted from the Redux bzone.zfs")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()
    out = args.out
    os.makedirs(out, exist_ok=True)
    stock = stock_files(args)
    rd = lambda n: open(os.path.join(stock, n), "rb").read()
    wr = lambda n, b: open(os.path.join(out, n), "wb").write(b)
    for name in ("abwpow", "sbwpow", "sblpow"):
        wr(name + ".sdf", spin_sdf(rd(name + ".sdf"), name))
        print("%s.sdf: element 4 = %s turn, %g rpm" % (name, "+".join(SPINS[name][0]), SPINS[name][2]))
    wr("svslf.vdf", svslf_vdf(rd("svslf.vdf")))
    hinge, rest_low, lows = arm_lowest_points(args.game)
    worst = min(lows, key=lambda x: x[1])
    print("svslf.vdf: element 0 unfold %d frames (0 -> %g deg), element 1 = reverse, element 4 launch %d frames "
          "(%g -> 88 -> %g deg), all one-shot" % (DEPLOY_FRAMES, READY_DEG, len(N64_LAUNCH), READY_DEG, READY_DEG))
    print("  arm lowest point: hinge y %.3f, rest %.3f, worst over all frames %.3f at frame %d" % (hinge, rest_low, worst[1], worst[0]))
    assert worst[1] > rest_low - 0.35, "the arm swings under the body (lowest point %.2f)" % worst[1]
    pivot, radius, ext = cbwpow_models(args.game, out)
    wr("cbwpow.sdf", cbwpow_sdf(rd("cbwpow.sdf"), pivot, radius, ext))
    wr("cwp11rot.geo", make_geo("cwp11rot", radius, ext[2]))
    print("cbwpow.sdf: GEO cwp11rot + element 4 turn, %g rpm" % SPINS["cbwpow"][2])


if __name__ == "__main__":
    main()
