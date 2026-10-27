"""Re-export a built ship under a Campaign Reimagined runtime name, with native GEO/SDF.
Run: blender -b --factory-startup out/avcarr.blend -P export_cr.py -- avcarr cr06lin
Writes out/cr/<name>.{mesh,geo,sdf,material}. Textures are renamed by to_cr_tex.py."""
import io
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import addon_utils
addon_utils.enable("bz98tools", default_set=True)
import shipkit as K
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from bzmodellibs import geo, geo_serializer
from bzstaticmodel import static_sdf_bytes

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
g = geo.Geo()
g.name = name
g.vert_count = len(points)
g.vertex_pos_buffer = np.array(points, dtype="<f4")
g.vertex_normal_buffer = np.array(normals, dtype="<f4")
uv = me.uv_layers.active.data
for i, tri in enumerate(me.loop_triangles):
    q = [Vector(points[v]) for v in tri.vertices]
    nrm = (q[1] - q[0]).cross(q[2] - q[0])
    nrm = nrm.normalized() if nrm.length > 1e-9 else Vector((0, 1, 0))
    face = g.create_face(i)
    face.color = geo.Color3(255, 255, 255)
    face.plane = geo.SurfacePlane(geo.Vector3(*(-nrm)), nrm.dot(q[0]))
    face.shade_type = face.texture_type = 0
    face.texture_name = name + ".map"
    for vi, li in zip(tri.vertices, tri.loops):
        u, v = uv[li].uv
        face.create_face_node(vi, vi, geo.UV(float(u), 1 - float(v)))
raw = io.BytesIO()
geo_serializer.GeoSerializer(raw).write(g)
open(os.path.join(K.OUT, name + ".geo"), "wb").write(raw.getvalue())
ntri = len(me.loop_triangles)
ev.to_mesh_clear()
bpy.data.objects.remove(proxy, do_unlink=True)

allp = [game_vector(v.co) for v in ob.data.vertices]
lo = [min(p[i] for p in allp) for i in range(3)]
hi = [max(p[i] for p in allp) for i in range(3)]
radius = max(math.sqrt(sum(x * x for x in p)) for p in allp)
center = [(a + b) / 2 for a, b in zip(lo, hi)]
half = [(b - a) / 2 for a, b in zip(lo, hi)]
open(os.path.join(K.OUT, name + ".sdf"), "wb").write(static_sdf_bytes(name, center, half, radius))
print("NATIVE", name, len(points), "verts", ntri, "tris; bounds", lo, hi, "r", round(radius, 1))
