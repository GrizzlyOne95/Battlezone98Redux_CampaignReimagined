#!/usr/bin/env python3
"""Static checks for the unit animation-slot model fixes (Tools/Build-UnitAnimSlots.py).

For every shipped file:
  * element 4 exists, starts on the deploy end frame (element 0's last frame), and loops
    (loop 0) on producers or plays once (loop 1) on the Armory (cvslf);
  * every part that moves during element 4 is keyed on every frame of it, its first key is
    the deploy end pose and its pose on the last frame equals the first (the loop wraps from
    start+length-1 straight back to start; the one-shot returns to rest);
  * every keyed track reaches the last frame element 4 plays (past its last key the engine
    shows key 0, the undeployed pose);
  * element 4 moves exactly the listed parts; every other part holds its deploy end pose
    (avrecy/bvrecy: only the smoke stack SM5 moves, the side panels hold);
  * Tools/Audit-SdfLoops.py finds no seam, skipped frame, velocity break or jump;
  * file-specific fixes: avmuf/bvmuf arm swing is a sine on every frame with deploy elements
    untouched, bvrecy names match the skeleton's case.
Tugs (svhaul, avhaul, bvhaul): no blank track; elements 0/1 keep their stock one-shot spans
and 1 replays 0 in reverse; the pickup moves only the gs1 cargo hardpoint, 4.375 m, keyed on
every frame (svhaul keeps its stock keys).
When the Redux models (mesh + skeleton) are available (--game, default the GOG install), every
moving part must name a skeleton bone, with vertices unless it is a hardpoint (gs*/hp*). Static
stock tracks without a bone (svrecy's gs1/gs2, the tugs' _COL) are only noted. Without the game
files that check is skipped (CI has none).

  python Tools/Test-UnitAnimSlots.py [--game <Redux dir>]
"""
import argparse
import importlib.util
import io
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FIXES = os.path.join(ROOT, "Assets", "ModelFixes")
sys.path.insert(0, HERE)
import bzmodellibs  # noqa: E402

DEFAULT_GAME = r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"

# file: (element 4 loop value: 0 forever, 1 once; the only parts element 4 may move). Every
# other part must hold its deploy end pose for the whole element.
FILES = {
    "avmuf.vdf": (0, {"AMU11AR1", "AMU11AR2"}),
    "bvmuf.vdf": (0, {"BMU11AR1", "BMU11AR2"}),
    "avrecy.vdf": (0, {"aRE11SM5"}),            # smoke stack only; side panels hold
    "bvrecy.vdf": (0, {"bRE11SM5"}),
    "svrecy.vdf": (0, {"SRE11RAD", "SRE11AR1", "SRE11AR2"}),
    "cvrecy.vdf": (0, {"CRE11AMR", "CRE11ARL"}),
    "svmuf.vdf": (0, {"smu11bsh", "smu11drl", "smu11drr"}),
    "cvmuf.vdf": (0, {"CMF11LD1", "CMF11LD2"}),
    "avcnst.vdf": (0, {"acv11twr"}),
    "bvcnst.vdf": (0, {"bcv11twr"}),
    "cvcnst.vdf": (0, {"CCN11BDC"}),
    "svcnst.vdf": (0, {"scv11twr"}),
    "cvslf.vdf": (1, {"CAM11ARM"}),
}
# Tugs: (cargo hardpoint, stock element 0, stock element 1). Tug::Simulate plays 0 on pickup
# and 1 on dropoff and waits for each, so both stay one-shot and 1 mirrors 0.
TUGS = {
    "svhaul.vdf": ("sha11gs1", (1, 11), (11, -11)),
    "avhaul.vdf": ("aha11gs1", (0, 121), (120, -121)),
    "bvhaul.vdf": ("bha11gs1", (0, 121), (120, -121)),
}
EPS_DEG, EPS_M = 1e-3, 1e-5


def load_audit():
    spec = importlib.util.spec_from_file_location("audit", os.path.join(HERE, "Audit-SdfLoops.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def bones_with_vertices(game, model):
    """{bone name: vertex count} from the shipped or stock .mesh/.skeleton, or None."""
    ser_s, ser_m = bzmodellibs.ogreskeleton_serializer, bzmodellibs.ogremesh_serializer
    paths = {}
    for ext in ("mesh", "skeleton"):
        for d in (FIXES, os.path.join(game, "BZ_ASSETS", "common", "models"),
                  os.path.join(game, "BZ_ASSETS", "common", "models", "TRO")):
            p = os.path.join(d, model + "." + ext)
            if os.path.exists(p):
                paths[ext] = p
                break
    if len(paths) < 2:
        return None
    skel = ser_s.SkeletonSerializer(io.BytesIO(open(paths["skeleton"], "rb").read())).read()
    mesh = ser_m.MeshSerializer(io.BytesIO(open(paths["mesh"], "rb").read())).read()
    counts = {b.name: 0 for b in skel.bones()}
    by_handle = {b.handle: b.name for b in skel.bones()}
    for vba in mesh.all_bone_assignments():
        if vba.bone_index in by_handle:
            counts[by_handle[vba.bone_index]] += 1
    return counts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", default=DEFAULT_GAME)
    args = ap.parse_args()
    if not bzmodellibs.require_or_skip("Test-UnitAnimSlots"):
        return
    A = load_audit()
    errors = []

    def err(name, msg):
        errors.append("%s: %s" % (name, msg))

    have_game = os.path.isdir(os.path.join(args.game, "BZ_ASSETS"))

    def check_bones(name, parts, moving):
        if not have_game:
            return
        counts = bones_with_vertices(args.game, name[:-4])
        if counts is None:
            err(name, "mesh/skeleton not found under --game")
            return
        for p in parts:
            hardpoint = p["name"][-3:-1].lower() in ("gs", "hp")
            if p["name"] not in counts:
                if p["name"] in moving:
                    err(name, "moving track %r names no skeleton bone" % p["name"])
                else:
                    print("note: %s track %r names no skeleton bone (static)" % (name, p["name"]))
            elif p["name"] in moving and counts[p["name"]] == 0 and not hardpoint:
                err(name, "moving track %r drives a bone with no vertices" % p["name"])

    for name, (gs1, el0, el1) in TUGS.items():
        path = os.path.join(FIXES, name)
        if not os.path.exists(path):
            err(name, "missing from Assets/ModelFixes")
            continue
        els, parts = A.read_anim(path)
        el = {e["index"]: e for e in els}
        if any(not p["name"].strip() for p in parts):
            err(name, "blank-named track still present")
        if (el[0]["start"], el[0]["length"], el[0]["loop"]) != el0 + (1,) or                 (el[1]["start"], el[1]["length"], el[1]["loop"]) != el1 + (1,):
            err(name, "tug elements 0/1 changed from stock %s %s" % (el0, el1))
        f0 = A.element_frames(el[0])
        if A.element_frames(el[1]) != f0[::-1]:
            err(name, "element 1 does not replay element 0 in reverse")
        moving = set()
        for p in parts:
            for kind, rot in (("rot", True), ("pos", False)):
                keys = p[kind]
                if not keys:
                    continue
                dist = (lambda a, b: math.degrees(A.qangle(a, b))) if rot else math.dist
                poses = [A.sample(keys, f, rot) for f in f0]
                if max(dist(poses[0], q) for q in poses) > (EPS_DEG if rot else EPS_M):
                    moving.add(p["name"])
        if moving != {gs1}:
            err(name, "pickup should move only %s, moves %s" % (gs1, sorted(moving)))
        g = next((p for p in parts if p["name"] == gs1), None)
        if g is not None:
            keys = {k[0]: k[1] for k in g["pos"]}
            span = range(f0[0] + 1, f0[-1]) if name != "svhaul.vdf" else ()
            gaps = [f for f in span if f not in keys]
            if gaps:
                err(name, "%s: no key on frames %s" % (gs1, gaps[:5]))
            travel = math.dist(A.sample(g["pos"], f0[0], False), A.sample(g["pos"], f0[-1], False))
            if abs(travel - 4.375) > 0.01:
                err(name, "%s travels %.3f m, expected 4.375" % (gs1, travel))
        check_bones(name, parts, moving)

    for name, (loop, movers) in FILES.items():
        path = os.path.join(FIXES, name)
        if not os.path.exists(path):
            err(name, "missing from Assets/ModelFixes")
            continue
        els, parts = A.read_anim(path)
        el = {e["index"]: e for e in els}
        if name == "bvrecy.vdf":
            low = [p["name"] for p in parts if p["name"].startswith("bre11") and p["name"][5:7].lower() in ("ge", "lg", "po", "sm")]
            if low:
                err(name, "names not matching the skeleton case: %s" % low)
        e0, e4 = el.get(0), el.get(4)
        if e4 is None:
            err(name, "no element 4")
            continue
        deploy_end = e0["start"] + e0["length"] - 1
        if e4["start"] != deploy_end or e4["length"] < 2:
            err(name, "element 4 %s does not start on the deploy end frame %d" % ((e4["start"], e4["length"]), deploy_end))
        if e4["loop"] != loop:
            err(name, "element 4 loop %d, expected %d" % (e4["loop"], loop))
        frames = A.element_frames(e4)
        first, last = frames[0], frames[-1]
        moving = set()
        for p in parts:
            for kind, rot in (("rot", True), ("pos", False), ("scl", False)):
                keys = p[kind]
                if not keys:
                    continue
                if keys[-1][0] < last:
                    err(name, "%s %s keys end at %d, before element 4's last frame %d" % (p["name"], kind, keys[-1][0], last))
                    continue
                dist = (lambda a, b: math.degrees(A.qangle(a, b))) if rot else math.dist
                eps = EPS_DEG if rot else EPS_M
                poses = [A.sample(keys, f, rot) for f in frames]
                if max(dist(poses[0], q) for q in poses) <= eps:
                    continue
                moving.add(p["name"])
                if dist(poses[0], poses[-1]) > eps:
                    err(name, "%s %s: last frame %d differs from first by %.4f" % (p["name"], kind, last, dist(poses[0], poses[-1])))
                have = {k[0] for k in keys}
                gaps = [f for f in frames if f not in have]
                if gaps:
                    err(name, "%s %s: no key on frames %s" % (p["name"], kind, gaps[:5]))
                if first not in have:
                    err(name, "%s %s: no key on the deploy end frame %d" % (p["name"], kind, first))
        if moving != movers:
            err(name, "element 4 must move exactly %s (all else holds the deploy end pose), moves %s"
                % (sorted(movers), sorted(moving)))
        if name in ("avmuf.vdf", "bvmuf.vdf"):
            if (e0["start"], e0["length"]) != (0, 36) or (el[1]["start"], el[1]["length"]) != (35, -36) or (e4["start"], e4["length"]) != (35, 40):
                err(name, "deploy/idle elements changed from stock")
        check_bones(name, parts, moving)

    audit_args = argparse.Namespace(seam_deg=0.5, seam_m=0.01, vel_deg=1.5, vel_m=0.05, jump_deg=4.0, jump_m=0.15,
                                    jump_ratio=3.0, sparse_deg=135.0)
    for name in list(FILES) + list(TUGS):
        path = os.path.join(FIXES, name)
        if os.path.exists(path):
            for x in A.audit_file(path, audit_args):
                if x["looping"] and x["kind"] in A.BLOCKING:
                    err(name, "audit %s el%d %s frame %d %.3f %s" % (x["kind"], x["element"], x["part"], x["frame"], x["magnitude"], x["unit"]))

    if not have_game:
        print("note: no Redux install at %s; skeleton/vertex checks skipped" % args.game)
    for e in errors:
        print("FAIL", e)
    print("%d files, %d failures" % (len(FILES) + len(TUGS), len(errors)))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
