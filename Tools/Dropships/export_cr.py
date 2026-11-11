"""Re-export a built ship under a Campaign Reimagined runtime name, with native GEO/SDF.
Run: blender -b --factory-startup out/avcarr.blend -P export_cr.py -- avcarr cr06lin
Writes out/cr/<name>.{mesh,geo,sdf,material}. Textures are renamed by to_cr_tex.py."""
import math
import os
import struct
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import addon_utils
addon_utils.enable("bz98tools", default_set=True)
import shipkit as K

src, name = sys.argv[sys.argv.index("--") + 1:][:2]
K.OUT = os.path.join(K.ROOT, "out", "cr")
os.makedirs(K.OUT, exist_ok=True)
TEX = {"nsdfhull": "cr06nhl", "nsdfhullw": "cr06nhw", "nsdftrim": "cr06ntr",
       "ccahull": "cr06chl", "ccahullw": "cr06chw", "ccatrim": "cr06ctr", "capblack": "cr06blk"}

ob = bpy.data.objects[src]
ob.name = name
for m in ob.data.materials:
    m.name = m.name.replace(src, name)
K.export_mesh(ob)

# material: same BZBase layout as write_ogre_material, with namespaced textures
fac = "nsdf" if src == "avcarr" else "cca"
lines = ['import * from "BZBase.material"', ""]
for m in K.MATS:
    d, n, s, e = (TEX[t.rsplit("_", 1)[0]] + "_" + t.rsplit("_", 1)[1].lower() for t in K.tex_names(fac, m))
    lines += [f"material {name}_{m} : BZBase", "{",
              f"\tset_texture_alias DiffuseMap {d}.dds", f"\tset_texture_alias NormalMap {n}.dds",
              f"\tset_texture_alias SpecularMap {s}.dds", f"\tset_texture_alias EmissiveMap {e}.dds",
              "", '\tset $diffuse "1 1 1"', '\tset $ambient "1 1 1"',
              '\tset $specular ".6 .6 .6"', '\tset $shininess "64"', '\tset $glow "1 1 1"', "}", ""]
with open(os.path.join(K.OUT, name + ".material"), "w", newline="\n") as f:
    f.write("\n".join(lines))


# native GEO/SDF, after CR's Author-Misn06Rocket.py (Blender -Y forward -> game +Z)
def game_vector(p):
    return (float(p[0]), float(p[2]), float(-p[1]))


proxy = ob.copy()
proxy.data = ob.data.copy()
bpy.context.collection.objects.link(proxy)
mod = proxy.modifiers.new("native", "DECIMATE")
mod.ratio = min(1.0, 3000.0 / max(1, len(ob.data.vertices)))
deps = bpy.context.evaluated_depsgraph_get()
ev = proxy.evaluated_get(deps)
me = ev.to_mesh()
me.calc_loop_triangles()
points = [game_vector(v.co) for v in me.vertices]
normals = [game_vector(v.normal) for v in me.vertices]
assert len(points) < 4096, len(points)
tag = name.encode()
raw = struct.pack("<4si16siii", b"OEG.", 0, tag, len(points), len(me.loop_triangles), 0)
raw += b"".join(struct.pack("<3f", *p) for p in points + normals)
uv = me.uv_layers.active.data
for i, tri in enumerate(me.loop_triangles):
    q = [Vector(points[v]) for v in tri.vertices]
    nrm = (q[1] - q[0]).cross(q[2] - q[0])
    nrm = nrm.normalized() if nrm.length > 1e-9 else Vector((0, 1, 0))
    raw += struct.pack("<iiBBBffffi3s13sii", i, 3, 255, 255, 255, *(-nrm), nrm.dot(q[0]), 0, bytes(3),
                       (name + ".map").encode(), 0, 0)
    for vi, li in zip(tri.vertices, tri.loops):
        u, v = uv[li].uv
        raw += struct.pack("<iiff", vi, vi, float(u), 1 - float(v))
open(os.path.join(K.OUT, name + ".geo"), "wb").write(raw)
ntri = len(me.loop_triangles)
ev.to_mesh_clear()
bpy.data.objects.remove(proxy, do_unlink=True)

allp = [game_vector(v.co) for v in ob.data.vertices]
lo = [min(p[i] for p in allp) for i in range(3)]
hi = [max(p[i] for p in allp) for i in range(3)]
radius = max(math.sqrt(sum(x * x for x in p)) for p in allp)
prefix = struct.pack("<4si4sii", b"BWD2", 8, b"REV\0", 12, 8)
prefix += struct.pack("<4si16si5fi", b"SDFC", 78, tag, 1, 2000., 1e20, 1e20, 1e20, 1e20, 0)
prefix += b"xbldx1.xdf".ljust(14, b"\0") + b"null".ljust(12, b"\0")
assert len(prefix) == 98
center = [(a + b) / 2 for a, b in zip(lo, hi)]
half = [(b - a) / 2 for a, b in zip(lo, hi)]
rec = struct.pack("<8s12f8s7fiii4f", tag, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, b"WORLD", *center, radius, *half,
                  60, 0, 0, 0, 0, 0, 0)
null = b"NULL" + bytes(116)
body = struct.pack("<i", 1) + rec + null * 5
open(os.path.join(K.OUT, name + ".sdf"), "wb").write(
    prefix + struct.pack("<4si", b"SGEO", 8 + len(body)) + body + struct.pack("<4si", b"EXIT", 8) * 2)
print("NATIVE", name, len(points), "verts", ntri, "tris; bounds", lo, hi, "r", round(radius, 1))
