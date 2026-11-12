"""Reload the svdrop / cvdrop SDF variants through the toolkit and assert what build_faction_sdf.py promises.

Per ship and variant (c, o, x): the SDF parses (Modding Toolbox reader), its parts are exactly the bones plus the collision
slab, the ANIM elements are the variant's, the ramp (and svdrop's clamshells) are keyed on every frame 0-30 with the
variant's end pose, every GEO reads with vertices, the .mesh reads (Ogre serializer: hull + trim submeshes, vertices) and its
skeleton bones equal the GEO names, and the toolkit's SDF importer finds objects.
Run: blender -b -P verify_faction_sdf.py -- svdrop cvdrop      (files from Local/dropships/out/sdf)
"""
import math
import os
import sys
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE)))     # Tools/ (bzmodellibs)
import bpy                                                  # noqa: E402
import addon_utils                                          # noqa: E402
import bzmodellibs                                          # noqa: E402
import paths                                                # noqa: E402

addon_utils.enable("bz98tools", default_set=True)
from bz98tools.bzrmodelporter.ogremesh_serializer import MeshSerializer          # noqa: E402
from bz98tools.bzrmodelporter.ogreskeleton_serializer import SkeletonSerializer  # noqa: E402

legacy = bzmodellibs.legacy
DEST = Path(paths.OUT) / "sdf"
names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["svdrop", "cvdrop"]
EXPECT = {"svdrop": dict(prefix="sdr11", ramp=106.33, doors=100.0), "cvdrop": dict(prefix="cdr11", ramp=-61.33, doors=None)}
SEQ = {"c": [(0, 0, 31), (1, 30, -31), (4, 0, 31)], "o": [(0, 0, 31), (1, 30, -31), (4, 0, 31)],
       "x": [(0, 30, -31), (1, 30, -31), (4, 0, 31)]}


def angle(q):
    w, x, y, z = q
    return math.degrees(2 * math.atan2(math.sqrt(x * x + y * y + z * z), w))


ok = True
for ship in names:
    ex = EXPECT[ship]
    for v in "cox":
        name = ship + v
        sdf = legacy.read_sdf(DEST / (name + ".sdf"))
        parts = [p.name for p in sdf.parts if p.name != "NULL"]
        want_bones = {ex["prefix"] + s for s in (["bdy", "rmp", "lg1", "lg2", "lg3", "lg4"] + (["cl1", "cl2"] if ex["doors"] else []))}
        good = set(parts) == want_bones | {ex["prefix"] + "rpf"} and len(parts) == sdf.geocount
        seq = [(s.index, s.start, s.length) for s in sdf.sequences]
        good &= seq == SEQ[v]
        full = {t.name: t for t in sdf.tracks if t.rotations}
        moving = {ex["prefix"] + "rmp"} | ({ex["prefix"] + "cl1", ex["prefix"] + "cl2"} if ex["doors"] else set())
        good &= set(full) == moving
        for b, t in full.items():
            frames = [k[0] for k in t.rotations]
            end = angle(t.rotations[-1][1])
            target = (0.001 if v == "c" else (abs(ex["ramp"]) if b.endswith("rmp") else ex["doors"]))
            good &= frames == list(range(31)) and abs(end - target) < (1e-4 if v == "c" else 0.05)
            good &= len(t.positions) == 31
        for p in parts:
            g = legacy.read_geo(DEST / (p + ".geo"))
            good &= g.vertex_count > 0 and g.bad_vertices == 0 and len(g.faces) > 0
        with open(DEST / (name + ".mesh"), "rb") as fh:
            m = MeshSerializer(fh).read()
        subs = sorted(s.material_name for s in m.submeshes())
        good &= subs == sorted([name + "_hull", name + "_trim"])
        with open(DEST / (name + ".skeleton"), "rb") as fh:
            sk = SkeletonSerializer(fh).read()
        bones = sorted(b.name for b in sk.bones())
        good &= bones == sorted(parts)
        before = set(bpy.data.objects)
        bpy.ops.import_scene.sdf(filepath=str(DEST / (name + ".sdf")))
        objs = [o for o in bpy.data.objects if o not in before]
        good &= len(objs) > 0
        print(f"VERIFY {name}: parts={len(parts)} anim={seq} subs={subs} bones={len(bones)} importer_objects={len(objs)} "
              f"-> {'ok' if good else 'FAIL'}")
        ok &= good
print("VERIFY", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
