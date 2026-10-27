#!/usr/bin/env python3
"""Static checks for the building/production animation polish (Assets/ModelFixes).

Spin models (abwpow, sbwpow, sblpow, cbwpow): ANIM element 4 exists (PowerPlant plays element 4),
loops forever, runs one revolution per the documented rpm, the spun part has a rotation key on every
frame, its first and last pose match, it turns exactly 360 degrees in even steps about the documented
axis, no other part's rotation changes, and every position-keyed part has a key at the last frame (the
engine falls back to the first key past a part's last key).

svslf: ANIM element 4 exists and is ONE-SHOT (Producer and Armory::LaunchItem both start 4 without stopping
the previous play), slf11arm is keyed on every frame, starts and ends at rest, swings the N64 launch range,
and is the only moving part.

cbwpow: the turbine is its own bone/GEO (skeleton, SDF, geo and mesh bone assignments agree).

abspow must not ship an override (its unfold is stock).

  python Tools/Test-BuildingAnimations.py
"""
import io
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tools"))
import bzmodellibs  # noqa: E402

FIXES = os.path.join(ROOT, "Assets", "ModelFixes")
failures = []

# name -> (spin part, axis in the parent frame, rpm); keep in step with Build-BuildingAnimations.py
SPINS = {
    "abwpow": (("awp11spc",), (0.0, 1.0, 0.0), 6.0, False),
    "sbwpow": (("swp11prp",), (0.0, 0.0, 1.0), 10.0, False),
    "sblpow": (("sls11cla", "sls11clb", "sls11clc", "sls11cld"), (0.0, 1.0, 0.0), 3.0, True),
    "cbwpow": (("cwp11rot",), (0.0, 0.0, 1.0), 7.5, False),
}


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL " + msg)


def load(name):
    """The toolbox's read-only parse of a shipped SDF/VDF."""
    legacy = bzmodellibs.legacy
    path = os.path.join(FIXES, name)
    model = legacy.read_vdf(path) if name.endswith(".vdf") else legacy.read_sdf(path)
    check(bool(model.sequences), name + " has no ANIM chunk")
    return model


def qmul(a, b):
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (aw * bw - ax * bx - ay * by - az * bz, aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx, aw * bz + ax * by - ay * bx + az * bw)


def conj(q):
    return (q[0], -q[1], -q[2], -q[3])


def angle(a, b):
    """Rotation angle between two quaternions (sign-insensitive), radians, via the chord."""
    sign = 1.0 if sum(x * y for x, y in zip(a, b)) >= 0 else -1.0
    chord = math.sqrt(sum((x - sign * y) ** 2 for x, y in zip(a, b)))
    return 4.0 * math.asin(min(1.0, chord / 2.0))


def element(model, index):
    hits = [s for s in model.sequences if s.index == index]
    check(len(hits) == 1, "ANIM needs exactly one element %d (found %d)" % (index, len(hits)))
    return hits[0] if hits else None


def keys(track):
    return sorted(track.rotations)


def quats(track):
    return [k[1] for k in keys(track)]


def rel_axis_ok(q, axis, what):
    """conj(q0) * q(t) must rotate about `axis` only (the spin is applied after the bind)."""
    for qt in q[1::5]:
        rel = qmul(conj(q[0]), qt)
        off = [rel[i + 1] for i in range(3) if axis[i] == 0.0]
        check(all(abs(c) < 1e-4 for c in off), "%s: rotation leaves the axis %s" % (what, axis))


def test_spin(name):
    parts, axis, rpm, orbit = SPINS[name]
    model = load(name + ".sdf")
    seq = element(model, 4)
    if not seq:
        return
    check(seq.loop < 1, "%s: element 4 must loop forever (loop %d)" % (name, seq.loop))
    check(seq.start == 0 and seq.length > 1, "%s: element 4 start/length %d/%d" % (name, seq.start, seq.length))
    frames = seq.length - 1  # the engine wraps at start + length - 1
    check(abs(frames / seq.speed - 60.0 / rpm) < 1e-6, "%s: period %.3f s, not %.3f s" % (name, frames / seq.speed, 60.0 / rpm))
    for part_name in parts:
        spun = model.track(part_name)
        check(spun is not None, "%s: no ANIM track for %s" % (name, part_name))
        if spun is None:
            continue
        what = "%s/%s" % (name, part_name)
        check([k[0] for k in keys(spun)] == list(range(frames + 1)),
              "%s must key rotation on every frame 0..%d (has %d)" % (what, frames, len(spun.rotations)))
        q = quats(spun)
        check(angle(q[0], q[-1]) < 1e-4, "%s: first and last pose differ" % what)
        steps = [angle(a, b) for a, b in zip(q, q[1:])]
        check(abs(math.degrees(sum(steps)) - 360.0) < 0.01, "%s: turns %.4f degrees" % (what, math.degrees(sum(steps))))
        check(max(steps) - min(steps) < 1e-4, "%s: uneven spin steps" % what)
        check(all(sum(x * y for x, y in zip(a, b)) > 0 for a, b in zip(q, q[1:])), "%s: key hemisphere flips" % what)
        rel_axis_ok(q, axis, what)
        if orbit:
            pk = sorted(spun.positions)
            check([k[0] for k in pk] == list(range(frames + 1)), "%s: orbit needs a position key on every frame" % what)
            radius = [math.hypot(*(k[1][i] for i in range(3) if axis[i] == 0.0)) for k in pk]
            check(max(radius) - min(radius) < 1e-4, "%s: orbit radius changes" % what)
            check(all(abs(k[1][axis.index(1.0)] - pk[0][1][axis.index(1.0)]) < 1e-4 for k in pk), "%s: orbit leaves its plane" % what)
            check(abs(pk[0][1][0] - pk[-1][1][0]) < 1e-4 and abs(pk[0][1][2] - pk[-1][1][2]) < 1e-4, "%s: orbit does not close" % what)
    for t in model.tracks:
        if t.name not in parts and t.rotations:
            tq = quats(t)
            check(all(angle(tq[0], x) < 1e-4 for x in tq), "%s: %s rotation must stay constant" % (name, t.name))
            check(max(k[0] for k in t.rotations) >= frames, "%s: %s rotation keys stop before frame %d" % (name, t.name, frames))
        if t.positions:
            check(max(k[0] for k in t.positions) >= frames, "%s: %s position keys stop before frame %d" % (name, t.name, frames))
            check(len(t.positions) >= 2, "%s: %s needs position keys" % (name, t.name))


def test_svslf():
    model = load("svslf.vdf")
    seqs = {s.index: s for s in model.sequences}
    check(sorted(seqs) == [0, 1, 4], "svslf: elements 0, 1 and 4 expected, found %s" % sorted(seqs))
    if sorted(seqs) != [0, 1, 4]:
        return
    for i in (0, 1, 4):
        check(seqs[i].loop == 1, "svslf: element %d must be one-shot (loop %d); a loop leaks one active-list slot per play"
              % (i, seqs[i].loop))
    e0, e1, e4 = seqs[0], seqs[1], seqs[4]
    check(e0.start == 0 and e0.length == 76 and abs((e0.length - 1) / e0.speed - 5.0) < 1e-6,
          "svslf: element 0 (deploy) should be 76 frames = timeDeploy 5 s")
    check(e1.start == 75 and e1.length == -76, "svslf: element 1 must be element 0 played backwards")
    check(e4.start == 76 and e4.length == 31, "svslf: element 4 start/length %d/%d" % (e4.start, e4.length))
    check({t.name for t in model.tracks} == {p.name for p in model.band(0)}, "svslf: ANIM parts must match the GEOs")
    arm = model.track("slf11arm")
    ks = keys(arm)
    last = e4.start + e4.length - 1
    check([k[0] for k in ks] == list(range(last + 1)), "svslf: slf11arm must key rotation on every frame 0..%d" % last)
    q = {k[0]: k[1] for k in ks}
    check(angle(q[75], q[76]) < 1e-4, "svslf: the unfold must end in the pose the launch starts from (snap of %.3f rad)" % angle(q[75], q[76]))
    check(angle(q[76], q[last]) < 1e-4, "svslf: the launch must end where it starts")
    check(abs(math.degrees(angle(q[0], q[75])) - 20.0) < 0.1, "svslf: deployed elevation is not 20 degrees")
    peak = max(angle(q[0], q[f]) for f in range(76, last + 1))
    check(abs(math.degrees(peak) - 88.0) < 1.5, "svslf: peak raise %.1f degrees, expected the N64 88" % math.degrees(peak))
    seq_q = [q[f] for f in range(last + 1)]
    check(all(sum(x * y for x, y in zip(a, b)) > 0 for a, b in zip(seq_q, seq_q[1:])), "svslf: key hemisphere flips")
    rel_axis_ok(seq_q, (1.0, 0.0, 0.0), "svslf")
    # Redux writes bone orientation (w, -x, y, z): a raise of the rear is a NEGATIVE stored x (confirmed live;
    # the opposite sign swung the arm under the body). Never dips: stored x stays <= 0 on every frame.
    check(all(qq[1] <= 1e-6 for qq in seq_q), "svslf: the arm is rotated the wrong way (stored x > 0 lowers the rear)")
    # raises monotonically through the unfold, never backwards past rest
    unfold = [q[f] for f in range(76)]
    check(all(unfold[i][1] >= unfold[i + 1][1] - 1e-9 for i in range(75)), "svslf: unfold is not monotonic")
    for t in model.tracks:
        if t.name != "slf11arm" and t.rotations:
            tq = quats(t)
            check(all(angle(tq[0], x) < 1e-4 for x in tq), "svslf: %s must not move" % t.name)
        check(len(t.positions) >= 2 and max(k[0] for k in t.positions) >= last,
              "svslf: %s needs position keys through frame %d" % (t.name, last))


def test_cbwpow():
    model = load("cbwpow.sdf")
    names = [p.name for p in model.band(0)]
    check(names == ["cwp11bda", "cwp11rot"], "cbwpow.sdf GEOs: %s" % names)
    rot = [p for p in model.band(0) if p.name == "cwp11rot"]
    check(rot and rot[0].parent == "cwp11bda", "cwp11rot must hang off cwp11bda")
    geo_data = open(os.path.join(FIXES, "cwp11rot.geo"), "rb").read()
    geo = bzmodellibs.legacy.read_geo(geo_data)
    check(geo.name == "cwp11rot" and len(geo.faces) > 0 and geo.bad_vertices == 0, "cwp11rot.geo does not parse")
    with open(os.path.join(FIXES, "cbwpow.skeleton"), "rb") as fh:
        skel = bzmodellibs.ogreskeleton_serializer.SkeletonSerializer(fh).read()
    check({b.name for b in skel.bones()} == {"cwp11bda", "cwp11rot"}, "skeleton bones %s" % [b.name for b in skel.bones()])
    if skel.bone_name_exists("cwp11rot"):
        bone = skel.get_bone_by_name("cwp11rot")
        check(bone.parent is not None and bone.parent.name == "cwp11bda", "cwp11rot is not parented to cwp11bda")
        sdf_pos = rot[0].matrix[9:12] if rot else (0, 0, 0)
        check(abs(bone.position.y - sdf_pos[1]) < 1e-3 and abs(bone.position.z - sdf_pos[2]) < 1e-3,
              "skeleton and SDF disagree on the cwp11rot pivot")
    with open(os.path.join(FIXES, "cbwpow.mesh"), "rb") as fh:
        mesh = bzmodellibs.ogremesh_serializer.MeshSerializer(fh).read()
    sm = mesh.get_submesh(0)
    counts = {}
    for vba in sm.bone_assignments_unsorted():
        counts[vba.bone_index] = counts.get(vba.bone_index, 0) + 1
    # 872 stock rotor vertices + 137 duplicated by the hard-edged normal splits.
    check(counts.get(1, 0) == 1009, "rotor vertices on bone 1: %s" % counts)
    check(mesh.skeleton_name == "cbwpow.skeleton", "mesh skeleton link is %r" % mesh.skeleton_name)


def main():
    if not bzmodellibs.require_or_skip("Test-BuildingAnimations"):
        return
    check(not os.path.exists(os.path.join(FIXES, "abspow.sdf")), "abspow keeps its stock unfold: no override")
    for name in SPINS:
        test_spin(name)
    test_svslf()
    test_cbwpow()
    if failures:
        print("%d failure(s)" % len(failures))
        sys.exit(1)
    print("Building animation checks passed.")


if __name__ == "__main__":
    main()
