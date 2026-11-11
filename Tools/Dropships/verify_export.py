"""Reload exported .mesh/.skeleton through the BZ98 toolkit importer and report submeshes, bones, UVs.
Run: blender -b -P verify_export.py -- svdrop cvdrop   (files from Local/dropships/out)"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
import shipkit as K
import paths

K.setup_scene()
names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["svdrop", "cvdrop"]
ok = True
for n in names:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.bz98_bzr_mesh(filepath=os.path.join(paths.OUT, n + ".mesh"), import_materials=False)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    arms = [o for o in new if o.type == "ARMATURE"]
    bones = sorted(b.name for a in arms for b in a.data.bones)
    uv = all(len(o.data.uv_layers) > 0 and any(abs(l.uv.x) + abs(l.uv.y) > 0 for l in o.data.uv_layers[0].data) for o in meshes)
    groups = sorted({g.name for o in meshes for g in o.vertex_groups})
    slots = sorted({p.material_index for o in meshes for p in o.data.polygons})
    mnames = sorted({m.name for o in meshes for m in o.data.materials if m})
    tris = sum(len(o.data.polygons) for o in meshes)
    print(f"VERIFY {n}: submeshes={len(meshes)} {[o.name for o in meshes]} slots_used={slots} materials={mnames} tris={tris} bones={len(bones)} {bones} "
          f"vertex_groups={len(groups)} uv={uv}")
    ok &= len(meshes) >= 3 and len(bones) > 0 and len(bones) > 0 and uv
    mat = os.path.join(paths.OUT, n + ".material")
    print("  material file:", os.path.exists(mat), "skeleton:", os.path.exists(os.path.join(paths.OUT, n + ".skeleton")))
print("VERIFY", "PASS" if ok else "FAIL")
