#!/usr/bin/env python3
"""Audit looping (and continuously replayed) SDF/VDF ANIM elements for seams and pops.

For every element that loops (loop < 1) or that the engine replays back to back (walker
stand/move cycles, person cycles), and for every part keyed inside it:

  seam      pose at the wrap frame (start+length-1, the last frame the engine plays before it
            jumps back to start) differs from the pose at start (rotation > --seam-deg degrees
            or position > --seam-m metres): a visible pop once per cycle
  skipframe the wrap step is an ordinary one-frame step because the cycle was authored with a
            closing key one frame past the wrap (pose(start+length) == pose(start)); the engine
            never plays that frame (time wraps from start+length-1 straight to start), so one
            frame of motion is skipped per cycle: a one-tick hitch of the reported size
  seamvel   velocity jumps across the wrap: the step into the wrap frame and the step out of
            start differ by more than half the larger step (and by > --vel-deg / --vel-m)
  jump      one per-frame step is much larger than both neighbours (> --jump-ratio x and
            > --jump-deg / --jump-m), i.e. a pop inside the element
  flip      consecutive rotation keys in opposite quaternion hemispheres (dot < 0). The Redux
            slerp negates one side first, so this is informational only (other tools may not)
  sparse    two consecutive keys more than one frame apart whose rotation differs by more
            than --sparse-deg (default 135): slerp is near the 180-degree ambiguity and other
            tools may take the other way round. Informational

Every element is also checked for jumps, flips and sparse keys, looping or not. With --strict
the exit status is 1 when a looping element has a seam, skipframe, seamvel or jump finding.

Playback model (Redux exe: frame advance 0x0062B4C0, per-part pose 0x0062AFE0): a looping forward element plays start ..
start+length-1 and wraps time from the last frame straight back to start (period length-1), a
frame outside a part's keys shows key 0, rotation slerps with a hemisphere fix. Files are read
with the Modding Toolbox reader (battlezone.meshes.legacy) through Tools/bzmodellibs.py.

  python Tools/Audit-SdfLoops.py <dir or files...> [--strict] [--json out.json] [--exclude name]

Walker and person models are recognised by name (walk, pilo, sold, user, heav in the base
name) and their cycle elements are treated as replayed: walker 2 (stand) and 4-7 (move);
person 2, 4-7, 8, 9, 10.
"""
import argparse
import glob
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bzmodellibs  # noqa: E402

WALKER_CYCLES = {2, 4, 5, 6, 7}
PERSON_CYCLES = {2, 4, 5, 6, 7, 8, 9, 10}
BLOCKING = ("seam", "skipframe", "seamvel", "jump")

# ----------------------------------------------------------------------------- playback model


def qdot(a, b):
    return sum(x * y for x, y in zip(a, b))


def qangle(a, b):
    """Rotation angle between two quaternions, sign-insensitive, radians (chord form)."""
    sign = 1.0 if qdot(a, b) >= 0 else -1.0
    chord = math.sqrt(sum((x - sign * y) ** 2 for x, y in zip(a, b)))
    return 4.0 * math.asin(min(1.0, chord / 2.0))


def qslerp(a, b, t):
    d = qdot(a, b)
    if d < 0:
        a, d = tuple(-x for x in a), -d
    if 1 - d <= 1e-5:
        v = tuple(x + (y - x) * t for x, y in zip(a, b))
        n = math.sqrt(qdot(v, v))
        return tuple(x / n for x in v)
    th = math.acos(min(1.0, d))
    s = math.sin(th)
    return tuple((math.sin((1 - t) * th) * x + math.sin(t * th) * y) / s for x, y in zip(a, b))


def sample(keys, frame, rot):
    """Engine evaluation of a track: interpolate inside the keyed range, key 0 outside it."""
    if not keys:
        return None
    for (fa, va), (fb, vb) in zip(keys, keys[1:]):
        if fa <= frame <= fb:
            t = 0.0 if fb == fa else (frame - fa) / (fb - fa)
            return qslerp(va, vb, t) if rot else tuple(x + (y - x) * t for x, y in zip(va, vb))
    return keys[0][1]


def element_frames(e):
    """Integer frames an element plays, in play order (one frame for a hold)."""
    s, n = e["start"], e["length"]
    if n > 0:
        return list(range(s, s + n))
    if n < 0:
        return list(range(s, s + n, -1))
    return []


def read_anim(path):
    """(elements, parts) of a model's ANIM chunk, or None. Parts keep their stored names."""
    legacy = bzmodellibs.legacy
    try:
        model = (legacy.read_sdf if path.lower().endswith(".sdf") else legacy.read_vdf)(path)
    except legacy.ModelError:
        return None
    if not model.sequences:
        return None
    els = [dict(index=q.index, start=q.start, length=q.length, loop=q.loop, speed=q.speed) for q in model.sequences]
    parts = [dict(name=t.name, rot=list(t.rotations), pos=list(t.positions), scl=list(t.scales)) for t in model.tracks]
    return els, parts



def kind_of(name):
    if "walk" in name or "wamp" in name or "watm" in name:
        return "walker"
    if re.search(r"(pilo|sold|user|heav)", name):
        return "person"
    return "other"


def replayed(name, e):
    k = kind_of(name)
    if k == "walker" and e["index"] in WALKER_CYCLES:
        return True
    if k == "person" and e["index"] in PERSON_CYCLES:
        return True
    return e["loop"] < 1


def pdist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def audit_file(path, args):
    name = os.path.splitext(os.path.basename(path))[0].lower()
    anim = read_anim(path)
    if anim is None:
        return []
    els, parts = anim
    out = []

    def add(kind, e, part, frame, mag, unit, looping):
        out.append(dict(model=name, element=e["index"], part=part, kind=kind, frame=frame,
                        magnitude=round(mag, 3), unit=unit, looping=looping))

    for e in els:
        frames = element_frames(e)
        if len(frames) < 3:
            continue
        lo, hi = min(frames), max(frames)
        looping = replayed(name, e)
        for p in parts:
            for track, rot in (("rot", True), ("pos", False)):
                keys = p[track]
                if not keys:
                    continue
                inside = [k for k in keys if lo <= k[0] <= hi]
                if not inside and not (keys[0][0] < lo and keys[-1][0] > hi):
                    continue  # constant over the element (held key)
                poses = [sample(keys, f, rot) for f in frames]
                dist = (lambda a, b: math.degrees(qangle(a, b))) if rot else pdist
                unit = "deg" if rot else "m"
                steps = [dist(a, b) for a, b in zip(poses, poses[1:])]
                if max(steps) < 1e-6 and (not looping or dist(poses[0], poses[-1]) < 1e-6):
                    continue
                jump_min = args.jump_deg if rot else args.jump_m
                for k in range(len(steps)):
                    nb = [steps[j] for j in (k - 1, k + 1) if 0 <= j < len(steps)]
                    if looping:
                        if k == 0:
                            nb.append(steps[-1])
                        if k == len(steps) - 1:
                            nb.append(steps[0])
                    ref = max(nb) if nb else 0.0
                    if steps[k] > jump_min and steps[k] > args.jump_ratio * max(ref, 1e-3):
                        add("jump", e, p["name"], frames[k + 1], steps[k], unit, looping)
                if rot:
                    for (fa, a), (fb, b) in zip(keys, keys[1:]):
                        if fb < lo or fa > hi:
                            continue
                        if qdot(a, b) < 0:
                            add("flip", e, p["name"], fb, math.degrees(qangle(a, b)), unit, looping)
                        if fb - fa > 1 and math.degrees(qangle(a, b)) > args.sparse_deg:
                            add("sparse", e, p["name"], fb, math.degrees(qangle(a, b)), unit, looping)
                if not looping:
                    continue
                seam = dist(poses[0], poses[-1])
                if seam > (args.seam_deg if rot else args.seam_m):
                    step = 1 if e["length"] > 0 else -1
                    beyond = sample(keys, frames[-1] + step, rot)
                    closing = dist(beyond, poses[0]) <= (args.seam_deg if rot else args.seam_m)
                    ordinary = seam <= 1.5 * max(steps[-1], steps[0], 1e-6)
                    add("skipframe" if closing and ordinary else "seam", e, p["name"], frames[-1], seam, unit, looping)
                    continue
                vin, vout = steps[-1], steps[0]
                vmin = args.vel_deg if rot else args.vel_m
                if abs(vin - vout) > vmin and abs(vin - vout) > 0.5 * max(vin, vout):
                    add("seamvel", e, p["name"], frames[-1], abs(vin - vout), unit, looping)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--strict", action="store_true", help="exit 1 on seam/skipframe/seamvel/jump in a looping element")
    ap.add_argument("--json")
    ap.add_argument("--exclude", action="append", default=[], metavar="NAME",
                    help="skip a model by base name (repeatable), e.g. a known-seamed walker")
    ap.add_argument("--seam-deg", type=float, default=0.5)
    ap.add_argument("--seam-m", type=float, default=0.01)
    ap.add_argument("--vel-deg", type=float, default=1.5)
    ap.add_argument("--vel-m", type=float, default=0.05)
    ap.add_argument("--jump-deg", type=float, default=4.0)
    ap.add_argument("--jump-m", type=float, default=0.15)
    ap.add_argument("--jump-ratio", type=float, default=3.0)
    ap.add_argument("--sparse-deg", type=float, default=135.0)
    args = ap.parse_args()
    files = []
    for p in args.paths:
        if os.path.isdir(p):
            files += sorted(glob.glob(os.path.join(p, "*.sdf")) + glob.glob(os.path.join(p, "*.vdf")))
        else:
            files.append(p)
    skip = {x.lower() for x in args.exclude}
    files = [f for f in files if os.path.splitext(os.path.basename(f))[0].lower() not in skip]
    findings = []
    for f in files:
        findings += audit_file(f, args)
    for x in findings:
        print("%-9s el%-2d %-9s %-8s frame %4d  %8.3f %s%s" % (x["model"], x["element"], x["part"], x["kind"], x["frame"],
                                                              x["magnitude"], x["unit"], "  (loop)" if x["looping"] else ""))
    if args.json:
        json.dump(findings, open(args.json, "w"), indent=1)
    bad = [x for x in findings if x["looping"] and x["kind"] in BLOCKING]
    print("%d files, %d findings, %d blocking in looping elements" % (len(files), len(findings), len(bad)))
    if args.strict and bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
