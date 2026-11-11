"""Reload exported .mesh/.skeleton through the BZ98 toolkit and report submeshes, bones, UVs.
Asserts the submeshes are exactly <ship>_hull and <ship>_trim (read with the toolkit's Ogre mesh serializer) and that the
toolkit importer finds bones and UVs.
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
    path = os.path.join(paths.OUT, n + ".mesh")
    sub = None
    try:
        from bz98tools.bzrmodelporter.ogremesh_serializer import MeshSerializer
        with open(path, "rb") as fh:
            m = MeshSerializer(fh).read()
        sub = sorted(s.material_name for s in m.submeshes())
    except Exception as ex:   # fall back to the importer's own object names
        print("  serializer read failed:", ex)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.bz98_bzr_mesh(filepath=path, import_materials=False)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    arms = [o for o in new if o.type == "ARMATURE"]
    bones = sorted(b.name for a in arms for b in a.data.bones)
    uv = all(len(o.data.uv_layers) > 0 and any(abs(l.uv.x) + abs(l.uv.y) > 0 for l in o.data.uv_layers[0].data) for o in meshes)
    tris = sum(len(o.data.polygons) for o in meshes)
    print(f"VERIFY {n}: submeshes={sub or [o.name for o in meshes]} importer_objects={len(meshes)} tris={tris} "
          f"bones={len(bones)} {bones} uv={uv}")
    want = sorted([n + "_hull", n + "_trim"])
    names_ok = sub == want
    if not names_ok:
        print(f"  FAIL submesh names {sub} != {want}")
    ok &= names_ok and len(meshes) >= 2 and len(bones) > 0 and uv
    print("  material file:", os.path.exists(os.path.join(paths.OUT, n + ".material")), "skeleton:",
          os.path.exists(os.path.join(paths.OUT, n + ".skeleton")))
print("VERIFY", "PASS" if ok else "FAIL")
