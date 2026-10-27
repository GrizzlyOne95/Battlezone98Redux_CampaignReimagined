#!/usr/bin/env python3
"""Build the unit animation-slot model fixes (Assets/ModelFixes/*.vdf).

Stock Redux VDFs leave several animation slots that the engine plays empty or broken. This
script reads the stock files, edits only their ANIM chunk (and, for bvrecy, part-name case),
and writes the fixed copies. Reading and writing go through the BZ98R Blender ToolKit's
VDF serializer (bzrmodelporter.bzbwd2_serializer); this script only edits keyframes.

Engine rules this relies on (Redux exe, decompiled):
  * Producer::Simulate (0x005AC580) plays element 0 when deploying, element 4 once deployed
    and element 1 when undeploying; Armory::LaunchItem (0x00473210) plays 4 per launch.
  * A looping element (loop 0) plays start .. start+length-1, then time wraps straight back to
    start (period length-1 frames), so pose(start+length-1) must equal pose(start).
  * A frame past a part's last key shows the part's key 0 (its undeployed pose), so every
    keyed part must carry keys up to the last frame element 4 plays.
  * Rotation keys are (w, x, y, z), the conjugate of the part's parent-space orientation.

Edits:
  avmuf, bvmuf   element 4 arm swing re-keyed on every frame as a sine with the stock
                 amplitude (44.85 deg) and period (39 frames); stock was a triangle wave that
                 skipped one 4.6 deg frame at each wrap.
  bvrecy         part names that differ in case from the skeleton bones (bre11SM5, ge*, LGT,
                 POV) renamed to the skeleton's bRE11 spelling, in VGEO and ANIM; plus idle.
  svhaul         blank-named ANIM track renamed to sha11gs1: it is that hardpoint's motion
                 (starts on its VGEO rest position, 0.07/3.586, and pulls the cargo 4.375 m in
                 over frames 1-10) but with no name it binds to no part.
  avhaul, bvhaul gs1 hardpoint pulled in the same 4.375 m along -Z during the stock one-shot
                 elements 0 (0, 121) and 1 (120, -121), keyed on every frame (smoothstep);
                 Tug::Simulate (0x005ECA60) plays 0 on pickup and 1 on dropoff and waits for
                 each, so lengths and loop counts stay stock and 1 mirrors 0.
  cvhaul         stock has no ANIM chunk at all. The Tug ctor (0x005EC220) carries cargo on
                 the first node of the hardpoint type in the VDF tree: COX11GS1 at (0, 0.5,
                 -6.5), behind the tail, where the two engine booms (z -5.5 .. 1.4, x +-2.2)
                 leave an open bay behind the hull (rear face z -2.07). A new ANIM with the
                 av/bv elements 0 (0, 121) and 1 (120, -121) at 15 fps pulls COX11GS1 the same
                 4.375 m toward the hull (+Z here; the others carry in front and pull -Z) to
                 z -2.125, seating the cargo between the booms against the hull's rear face.
  cvhaul.skeleton  stock Redux skeleton (TRO/cvhaul.skeleton) plus bone COX11GS1 (handle 9,
                 child of COX11BDA, at the VDF part's rest position), so the animated part
                 names a bone like every other tug's gs1. Written by the toolkit's skeleton
                 serializer as v1.80 (stock is v1.10; bones otherwise unchanged).
  avrecy, bvrecy (smoke stack SM5 only; side panels hold), svrecy, cvrecy, svmuf, cvmuf, avcnst, bvcnst, cvcnst, svcnst
                 new looping element 4 idle that starts and ends on the deploy end pose.
  cvslf          new one-shot element 4 (Armory: played per launch) arm reach and return.

  python Tools/Build-UnitAnimSlots.py --stock-dir <dir with stock .vdf> [--game <Redux>] [--check]

--stock-dir holds the stock VDFs extracted from the Redux bzone.zfs; --game is the Redux
install whose BZ_ASSETS hold the stock skeletons (default the GOG install). --check rebuilds in
memory and fails if a shipped file differs. The toolkit is located by Tools/bzmodellibs.py
(BZ_TOOLKIT_DIR or a sibling BZ98RBlenderToolKit checkout).
"""
import argparse
import importlib
import io
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Assets", "ModelFixes")


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bzmodellibs  # noqa: E402

SER = bzmodellibs.bwd2_serializer
BWD2 = bzmodellibs.bwd2
SKS = bzmodellibs.ogreskeleton_serializer
SP = importlib.import_module("bzrmodelporter.spacial")  # on sys.path once the toolkit loads

FPS = 15.0

# ----------------------------------------------------------------------------- quaternion math


def qmul(a, b):
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (aw * bw - ax * bx - ay * by - az * bz, aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx, aw * bz + ax * by - ay * bx + az * bw)


def qconj(a):
    return (a[0], -a[1], -a[2], -a[3])


def qnorm(a):
    n = math.sqrt(sum(x * x for x in a))
    return tuple(x / n for x in a)


def aa(axis, ang):
    s = math.sin(ang / 2)
    return (math.cos(ang / 2), axis[0] * s, axis[1] * s, axis[2] * s)


def qrot(q, v):
    return qmul(qmul(q, (0.0, *v)), qconj(q))[1:]


def slerp(a, b, t):
    d = sum(x * y for x, y in zip(a, b))
    if d < 0:
        a, d = tuple(-x for x in a), -d   # the engine negates the first operand
    if 1 - d <= 1e-5:
        return qnorm(tuple(x + (y - x) * t for x, y in zip(a, b)))
    th = math.acos(min(1.0, d))
    s = math.sin(th)
    return tuple((math.sin((1 - t) * th) * x + math.sin(t * th) * y) / s for x, y in zip(a, b))


def hamilton_from_columns(r, u, f):
    m = [[r[0], u[0], f[0]], [r[1], u[1], f[1]], [r[2], u[2], f[2]]]
    t = m[0][0] + m[1][1] + m[2][2]
    if t > 0:
        s = math.sqrt(t + 1) * 2
        q = (0.25 * s, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s)
    elif m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1 + m[0][0] - m[1][1] - m[2][2]) * 2
        q = ((m[2][1] - m[1][2]) / s, 0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s)
    elif m[1][1] > m[2][2]:
        s = math.sqrt(1 + m[1][1] - m[0][0] - m[2][2]) * 2
        q = ((m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s)
    else:
        s = math.sqrt(1 + m[2][2] - m[0][0] - m[1][1]) * 2
        q = ((m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s)
    return qnorm(q)


def sample(keys, frame, rot):
    """Engine evaluation of one track: interpolate inside the keyed range, key 0 outside it."""
    for (fa, va), (fb, vb) in zip(keys, keys[1:]):
        if fa <= frame <= fb:
            t = 0.0 if fb == fa else (frame - fa) / (fb - fa)
            return slerp(va, vb, t) if rot else tuple(x + (y - x) * t for x, y in zip(va, vb))
    return keys[0][1]


# ----------------------------------------------------------------------------- toolkit glue


def chunk_span(data, tag):
    """(start, end) of the first chunk with this tag, walking BWD2 chunk headers."""
    pos = 0
    while pos + 8 <= len(data):
        size = int.from_bytes(data[pos + 4:pos + 8], "little")
        if data[pos:pos + 4] == tag:
            return pos, pos + size
        if size < 8:
            break
        pos += size
    raise ValueError("no %r chunk" % tag)


class Model:
    """A stock VDF read with the toolkit, with its ANIM tracks as plain per-part key lists."""

    def __init__(self, path):
        self.path = path
        self.ser = SER.SDFSerializer if path.lower().endswith(".sdf") else SER.VDFSerializer
        self.bwd = self.ser(io.BytesIO(open(path, "rb").read())).read()
        self.stock_anim = self.bwd.anim_obj is not None
        if not self.stock_anim:
            a = self.bwd.anim_obj = BWD2.AnimObj()
            a.name = os.path.splitext(os.path.basename(path))[0]
            # Toolkit gap: AnimObj() names these *_keyframes_ptr but write_anim reads
            # *_keyframe_ptr (only read_anim sets those), so a fresh AnimObj cannot be written.
            a._orientation_keyframe_ptr = a._scale_keyframe_ptr = a._position_keyframe_ptr = 0
        a = self.bwd.anim_obj
        self.order = list(a.mesh_map.keys())
        self.renamed = False
        self.tracks = {}
        for name, mesh in a.mesh_map.items():
            self.tracks[name] = dict(
                mesh=mesh,
                rot=[(k.frame, (k.orientation.w, k.orientation.x, k.orientation.y, k.orientation.z))
                     for k in a.slice_mesh_orientation_keyframes(mesh)],
                scl=[(k.frame, (k.scale.x, k.scale.y, k.scale.z)) for k in a.slice_mesh_scale_keyframes(mesh)],
                pos=[(k.frame, (k.position.x, k.position.y, k.position.z))
                     for k in a.slice_mesh_position_keyframes(mesh)])

    # elements
    def element(self, index):
        return self.bwd.anim_obj.animation_map.get(index)

    def set_element(self, index, start, length, loop):
        a = self.bwd.anim_obj
        e = a.animation_map.get(index) or a.create_animation(index)
        e.start, e.length, e.loop, e.speed = start, length, loop, FPS
        a.animation_map = dict(sorted(a.animation_map.items()))
        return e

    def deploy_end(self):
        e = self.element(0)
        return e.start + e.length - 1

    # geometry
    def geo(self, name):
        for obj in self.bwd.primary_objects(raw=True):
            if obj.name == name:
                return obj
        return None

    def bind(self, name):
        t = self.geo(name).transform
        q = hamilton_from_columns((t.rx, t.ry, t.rz), (t.ux, t.uy, t.uz), (t.fx, t.fy, t.fz))
        return qconj(q), (t.px, t.py, t.pz)

    def local_h(self, name, frame):
        """Hamilton parent-space orientation of a part at a frame."""
        tr = self.tracks.get(name)
        if tr and tr["rot"]:
            return qconj(sample(tr["rot"], frame, True))
        return qconj(self.bind(name)[0])

    def world_h(self, name, frame):
        g = self.geo(name)
        if g is None:
            return (1.0, 0.0, 0.0, 0.0)
        h = self.local_h(name, frame)
        if self.geo(g.parent) is not None and g.parent != name:
            h = qmul(self.world_h(g.parent, frame), h)
        return h

    def up_in_parent(self, name, frame):
        """World up (+Y) expressed in the part's parent space at a frame."""
        g = self.geo(name)
        hp = self.world_h(g.parent, frame) if self.geo(g.parent) is not None else (1.0, 0.0, 0.0, 0.0)
        return qrot(qconj(hp), (0.0, 1.0, 0.0))

    # tracks
    def add_track(self, name, upto):
        """A new ANIM part for a VGEO part stock never keys: bind pose held from 0 to upto."""
        rot, pos = self.bind(name)
        mesh = self.bwd.anim_obj.create_animation_mesh(name)
        t = self.geo(name).transform
        mesh.frame_transform = SP.Transform(*t.to_rufp_xyz())
        self.order.append(name)
        self.tracks[name] = dict(mesh=mesh, rot=[(0, rot), (upto, rot)], scl=[], pos=[(0, pos), (upto, pos)])

    def rename(self, old, new):
        self.renamed = True
        self.order[self.order.index(old)] = new
        self.tracks[new] = self.tracks.pop(old)
        self.tracks[new]["mesh"].name = new
        for obj in self.bwd.all_geo_objects(raw=True):
            if obj.name == old:
                obj.name = new
            if obj.parent == old:
                obj.parent = new

    def rename_track(self, old, new):
        """Rename an ANIM track only (VGEO untouched, so the stock bytes still splice)."""
        if self.geo(new) is None:
            raise ValueError("%s: no VGEO part named %r" % (self.path, new))
        self.order[self.order.index(old)] = new
        self.tracks[new] = self.tracks.pop(old)

    def hold_all(self, upto):
        """Every keyed track carries a constant key at upto, so frames past the deploy end do
        not fall back to key 0."""
        for tr in self.tracks.values():
            for kind in ("rot", "scl", "pos"):
                keys = tr[kind]
                if keys and keys[-1][0] < upto:
                    keys.append((upto, keys[-1][1]))

    def to_bytes(self):
        a = self.bwd.anim_obj
        a.mesh_map = {}
        a.orientation_keyframe_list, a.scale_keyframe_list, a.position_keyframe_list = [], [], []
        for name in self.order:
            tr = self.tracks[name]
            mesh = tr["mesh"]
            mesh.name = name
            a.mesh_map[name] = mesh
            mesh.orientation_start, mesh.orientation_length = len(a.orientation_keyframe_list), len(tr["rot"])
            for f, q in tr["rot"]:
                a.create_orientation_keyframe(f, SP.Quaternion(*q))
            mesh.scale_start, mesh.scale_length = len(a.scale_keyframe_list), len(tr["scl"])
            for f, v in tr["scl"]:
                a.create_scale_keyframe(f, SP.Vector3(*v))
            mesh.position_start, mesh.position_length = len(a.position_keyframe_list), len(tr["pos"])
            for f, v in tr["pos"]:
                a.create_position_keyframe(f, SP.Vector3(*v))
        out = io.BytesIO()
        self.ser(out).write(self.bwd)
        new = out.getvalue()
        if self.renamed:
            return new
        # Only the ANIM chunk changed: splice the toolkit's ANIM into the stock bytes so every
        # other byte (including stock garbage after string terminators) stays identical.
        old = open(self.path, "rb").read()
        n0, n1 = chunk_span(new, b"ANIM")
        if not self.stock_anim:
            # No stock ANIM: insert the new one where the toolkit writes it, right after VGEO.
            o1 = chunk_span(old, b"VGEO")[1]
            return old[:o1] + new[n0:n1] + old[o1:]
        o0, o1 = chunk_span(old, b"ANIM")
        return old[:o0] + new[n0:n1] + old[o1:]


# ----------------------------------------------------------------------------- motion builders


def bump(t, harmonic=1):
    """0 at t = 0 and t = 1, smooth and periodic, peaks at 1."""
    return (1 - math.cos(2 * math.pi * harmonic * t)) / 2


def keyed_cycle(m, name, start, period, fn):
    """Replace a part's keys after start with one key per frame up to start+period; fn(t, rot,
    pos) -> (rot, pos) with t in [0, 1]. The last key is set bit-equal to the start key."""
    tr = m.tracks[name]
    base_rot = sample(tr["rot"], start, True) if tr["rot"] else None
    base_pos = sample(tr["pos"], start, False) if tr["pos"] else None
    new_rot, new_pos = [], []
    for f in range(start + 1, start + period):
        r, p = fn((f - start) / period, base_rot, base_pos)
        if r is not None:
            prev = new_rot[-1][1] if new_rot else base_rot
            if sum(x * y for x, y in zip(r, prev)) < 0:
                r = tuple(-x for x in r)   # keep consecutive keys in one hemisphere
            new_rot.append((f, r))
        if p is not None:
            new_pos.append((f, p))
    if tr["rot"]:
        tr["rot"] = [k for k in tr["rot"] if k[0] <= start] + new_rot + [(start + period, base_rot)]
    if tr["pos"]:
        tr["pos"] = [k for k in tr["pos"] if k[0] <= start] + new_pos + [(start + period, base_pos)]


def retrace(m, name, start, deg=6.0, metres=0.3, harmonic=1):
    """Ease part-way back along the part's own deploy path (always a pose deploy visits) and
    forward again, as far as the first of: deg degrees of rotation or metres of travel from
    the deploy end pose."""
    tr = m.tracks[name]
    rk, pk = [k for k in tr["rot"] if k[0] <= start], [k for k in tr["pos"] if k[0] <= start]
    end_r, end_p = (sample(rk, start, True) if rk else None), (sample(pk, start, False) if pk else None)

    def excursion(d):
        r = math.degrees(qangle(sample(rk, start - d, True), end_r)) / deg if rk else 0.0
        p = math.dist(sample(pk, start - d, False), end_p) / metres if pk else 0.0
        return max(r, p)
    depth = 0.0
    while excursion(depth) < 1.0:
        depth += 0.01
        if depth > start:
            raise ValueError("%s: deploy path never moves that far from its end pose" % name)

    def fn(t, r, p):
        f = start - depth * bump(t, harmonic)
        return (sample(rk, f, True) if rk else None), (sample(pk, f, False) if pk else None)
    return fn


def qangle(a, b):
    sign = 1.0 if sum(x * y for x, y in zip(a, b)) >= 0 else -1.0
    chord = math.sqrt(sum((x - sign * y) ** 2 for x, y in zip(a, b)))
    return 4.0 * math.asin(min(1.0, chord / 2.0))


def compose(*fns):
    def fn(t, r, p):
        for g in fns:
            r2, p2 = g(t, r, p)
            r, p = (r2 if r2 is not None else r), (p2 if p2 is not None else p)
        return r, p
    return fn


def yaw(axis_parent, amp_deg, harmonic=1):
    """Swing about a parent-space axis through the part origin: stored' = stored x conj(aa)."""
    def fn(t, r, p):
        ang = math.radians(amp_deg) * math.sin(2 * math.pi * harmonic * t)
        return qnorm(qmul(r, qconj(aa(axis_parent, ang)))), None
    return fn


def add_idle(m, period, parts):
    """Looping element 4 from the deploy end. parts: {name: fn-or-callable(m, E)}."""
    e_end = m.deploy_end()
    if m.element(2) is None:
        m.set_element(2, 0, -1, 1)
    if m.element(3) is None:
        m.set_element(3, e_end, -1, 1)
    m.set_element(4, e_end, period + 1, 0)
    for name, make in parts.items():
        keyed_cycle(m, name, e_end, period, make(m, e_end))
    m.hold_all(e_end + period)


def R(deg=6.0, metres=0.3, harmonic=1):
    return lambda name: (lambda m, e: retrace(m, name, e, deg, metres, harmonic))


def Y(amp, harmonic=1, extra=None):
    def make(name):
        def build(m, e):
            fns = [extra(name)(m, e)] if extra else []
            return compose(*fns, yaw(m.up_in_parent(name, e), amp, harmonic))
        return build
    return make


def idle(m, period, spec):
    add_idle(m, period, {name: maker(name) for name, maker in spec.items()})


# ----------------------------------------------------------------------------- per-model edits


def fix_muf(m, prefix):
    """Stock element 4 (35, 40): a triangle wave whose data period is 40 frames but which the
    engine plays with period 39, so each wrap skips a 4.6 deg frame. Re-key as a sine with the
    stock amplitude and the engine period; AR2 swings opposite to AR1 as in stock."""
    e = m.element(4)
    start, period = e.start, e.length - 1
    amp = math.radians(44.85)
    for arm, sign in (("AR1", -1.0), ("AR2", 1.0)):
        name = prefix + arm
        rest = sample(m.tracks[name]["rot"], start, True)

        def fn(t, r, p, sign=sign, rest=rest):
            return qnorm(qmul(rest, aa((1.0, 0.0, 0.0), sign * amp * math.sin(2 * math.pi * t)))), None
        keyed_cycle(m, name, start, period, fn)


def fix_bvrecy_case(m):
    for low in ["ge1"] + ["Ge%d" % k for k in range(2, 8)] + ["LGT", "POV", "SM5"]:
        m.rename("bre11" + low, "bRE11" + low)


def recy_ab(m, p):
    low = p.lower()
    """Only the smoke stack (SM5, which rises 4.9 m during deploy) breathes; the deployed side
    panels (bdb, bdc, bdd) and every other part hold their deploy end pose."""
    idle(m, 74, {p + "SM5": R(metres=0.4, harmonic=2)})


def cnst_ab(m, p):
    idle(m, 119, {p + "twr": Y(25)})


def build_cvslf(m):
    """Armory::LaunchItem plays element 4 once per launch: the arm swings out 60 deg along
    its deploy direction (about its X axis, the way deploy first swings it) and back."""
    e_end = m.deploy_end()
    length = 21
    m.set_element(2, 0, -1, 1)
    m.set_element(3, e_end, -1, 1)
    m.set_element(4, e_end, length, 1)

    def reach(t, r, p):
        return qnorm(qmul(r, aa((1.0, 0.0, 0.0), -math.radians(60) * bump(t)))), None
    keyed_cycle(m, "CAM11ARM", e_end, length - 1, reach)
    m.hold_all(e_end + length - 1)


TUG_TRAVEL = 4.375  # svhaul's stock hardpoint travel (3.586 -> -0.789 along Z)
TUG_ELEMENTS = ((0, 0, 121), (1, 120, -121))  # avhaul/bvhaul stock pickup/dropoff, 15 fps


def tug_lift(m, gs1, direction=-1.0):
    """Pull the cargo hardpoint TUG_TRAVEL metres toward the hull along its parent's Z
    (direction -1: cargo carried in front, as on av/bv/sv; +1: carried behind, as on cvhaul)
    across element 0, one key per frame with a smoothstep ease; element 1 plays the same
    frames in reverse. A VDF with neither tug element gets the av/bv elements, and a missing
    gs1 track is added (position keys only, as on av/bv)."""
    if m.element(0) is None and m.element(1) is None:
        if gs1 not in m.tracks:
            m.add_track(gs1, TUG_ELEMENTS[0][2] - 1)
            m.tracks[gs1]["rot"] = []
        for index, start, length in TUG_ELEMENTS:
            e = m.set_element(index, start, length, 1)
            e.mesh_index_list = [1] * len(m.order) + [0] * (32 - len(m.order))
    e0, e1 = m.element(0), m.element(1)
    first, last = e0.start, e0.start + e0.length - 1
    if (e1.start, e1.start + e1.length + 1) != (last, first):
        raise ValueError("%s: element 1 does not mirror element 0" % m.path)
    rest = m.bind(gs1)[1]
    tr = m.tracks[gs1]
    if any(math.dist(v, rest) > 1e-4 for _, v in tr["pos"]):
        raise ValueError("%s: %s is not a static hold in stock" % (m.path, gs1))
    keys = []
    for f in range(first, last + 1):
        t = (f - first) / (last - first)
        e = t * t * (3 - 2 * t)
        keys.append((f, (rest[0], rest[1], rest[2] + direction * TUG_TRAVEL * e)))
    tr["pos"] = keys


def build_svcnst(m):
    m.add_track("scv11twr", m.deploy_end())
    idle(m, 119, {"scv11twr": Y(25)})


BUILDS = {
    "avmuf.vdf": lambda m: fix_muf(m, "AMU11"),
    "bvmuf.vdf": lambda m: fix_muf(m, "BMU11"),
    "avrecy.vdf": lambda m: recy_ab(m, "aRE11"),
    "bvrecy.vdf": lambda m: (fix_bvrecy_case(m), recy_ab(m, "bRE11")),
    "svhaul.vdf": lambda m: m.rename_track(next(n for n in m.order if not n.strip()), "sha11gs1"),
    "avhaul.vdf": lambda m: tug_lift(m, "aha11gs1"),
    "bvhaul.vdf": lambda m: tug_lift(m, "bha11gs1"),
    "cvhaul.vdf": lambda m: tug_lift(m, "COX11GS1", direction=1.0),
    "svrecy.vdf": lambda m: idle(m, 89, {"SRE11RAD": Y(15, 1, R(5, harmonic=2)), "SRE11AR1": R(), "SRE11AR2": R(5)}),
    "cvrecy.vdf": lambda m: idle(m, 74, {"CRE11AMR": R(), "CRE11ARL": R()}),
    "svmuf.vdf": lambda m: idle(m, 59, {"smu11bsh": R(metres=0.25, harmonic=2), "smu11drl": R(), "smu11drr": R()}),
    "cvmuf.vdf": lambda m: idle(m, 74, {"CMF11LD1": R(), "CMF11LD2": R()}),
    "avcnst.vdf": lambda m: cnst_ab(m, "acv11"),
    "bvcnst.vdf": lambda m: cnst_ab(m, "bcv11"),
    "cvcnst.vdf": lambda m: idle(m, 119, {"CCN11BDC": Y(20)}),
    "svcnst.vdf": build_svcnst,
    "cvslf.vdf": build_cvslf,
}


DEFAULT_GAME = r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"


def add_vdf_bone(stock_dir, vdf, part):
    """A skeleton edit adding bone `part` under its VDF parent, at its VDF rest position."""
    def edit(sk):
        if sk.bone_name_exists(part):
            raise ValueError("skeleton already has %s" % part)
        m = Model(os.path.join(stock_dir, vdf))
        rot, pos = m.bind(part)
        if min(abs(rot[0] - 1.0), abs(rot[0] + 1.0)) > 1e-6:
            raise ValueError("%s: %s is rotated; only a translated bone is handled" % (vdf, part))
        bone = sk.create_bone(part, max(b.handle for b in sk.bones()) + 1, pos=SP.Vector3(*pos))
        sk.get_bone_by_name(m.geo(part).parent).add_child(bone)
    return edit


# shipped skeleton: (stock path under BZ_ASSETS/common/models, stock_dir -> edit(skeleton))
SKELETONS = {
    "cvhaul.skeleton": ("TRO/cvhaul.skeleton", lambda d: add_vdf_bone(d, "cvhaul.vdf", "COX11GS1")),
}


def build(stock_dir, name, game=DEFAULT_GAME):
    if name in SKELETONS:
        rel, edit = SKELETONS[name]
        src = os.path.join(game, "BZ_ASSETS", "common", "models", *rel.split("/"))
        sk = SKS.SkeletonSerializer(io.BytesIO(open(src, "rb").read())).read()
        edit(stock_dir)(sk)
        out = io.BytesIO()
        SKS.SkeletonSerializer(out).write(sk)
        return out.getvalue()
    m = Model(os.path.join(stock_dir, name))
    BUILDS[name](m)
    return m.to_bytes()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stock-dir", required=True, help="folder with the stock .vdf files (from bzone.zfs)")
    ap.add_argument("--game", default=DEFAULT_GAME, help="Redux install (stock skeletons under BZ_ASSETS)")
    ap.add_argument("--check", action="store_true", help="fail if a shipped file differs from a rebuild")
    ap.add_argument("only", nargs="*", help="build only these files")
    args = ap.parse_args()
    bad = 0
    for name in args.only or sorted(BUILDS) + sorted(SKELETONS):
        data = build(args.stock_dir, name, args.game)
        out = os.path.join(OUT, name)
        if args.check:
            same = os.path.exists(out) and open(out, "rb").read() == data
            print(("ok      " if same else "DIFFERS ") + name)
            bad += not same
        else:
            open(out, "wb").write(data)
            print("wrote", os.path.relpath(out, ROOT), len(data), "bytes")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
