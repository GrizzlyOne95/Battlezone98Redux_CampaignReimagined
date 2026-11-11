"""avdropo: the dropship as an animated SDF building (ramp opens once when the object is created).

Redux animates structures from the SDF ANIM chunk, not from .skeleton clips: each moving part is
its own GEO, the Redux .mesh has one rigidly weighted bone per GEO (same name), and the engine
moves those bones from the ANIM keys. The repairdepot class plays ANIM index 0 once in its
constructor (the stock hangar's doors), which is what this test variant relies on.

The toolkit porter writes the skeleton (bones = GEO names, identity rotations) but, with no .map
textures, a flat-colour mesh with every UV at 0.5. So the render mesh is the UV-textured rig export
from build_dropship's rig()/export_rigged(), turned 180 degrees about up into the porter's frame
(x,y,z -> -x,y,-z; the model is first turned 180 degrees so its bow faces the legacy front, +Y), its bone indices remapped by name onto the porter skeleton.

Run: blender -b -P build_dropship_sdf.py   -> ../out/sdf/avdropo.{sdf,mesh,skeleton,material} + adr11*.geo
"""
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_dropship.py")
_code = open(SRC, encoding="utf-8").read()
exec(compile(_code[:_code.index("\nK.setup_scene()")], SRC, "exec"))  # geometry builders only

import addon_utils
import geo_planes

NAME = os.environ.get("AVD_NAME", "avdropo")
RAMP_SIGN = float(os.environ.get("AVD_RAMP_SIGN", "1"))   # test hook: build a twin with the other swing
RAMP_SWING = float(os.environ.get("AVD_RAMP_DEG", "0")) or None  # test hook: animate a smaller swing
DEST = os.path.join(K.OUT, "sdf")
# GEO texture names are 8 characters; these map onto the nsdfv atlas in the hand-written .material
TEXNAME = {"hull": "avdrhull", "hullw": "avdrhulw", "trim": "avdrtrim"}
OPEN_FRAMES = 30            # 2 s at 15 fps, the stock hangar's rate
# visual ramp bone -> (static collision slab GEO, swing sign in the SDF frame); bow is +Y here
RAMPS = {"adr11rmp": ("adr11rpf", 1), "adr11fmp": ("adr11fpf", -1)}
ANIM_ELEMENTS = [(0, 0, OPEN_FRAMES + 1), (1, OPEN_FRAMES, -(OPEN_FRAMES + 1)), (4, 0, OPEN_FRAMES + 1)]


def split_parts(ob, bones):
    """One mesh object per bone/GEO, origin on the bone's pivot, parented like the rig."""
    owner = ["adr11bdy"] * len(ob.data.vertices)
    for name, (_, _, ranges) in bones.items():
        for a, b in ranges:
            owner[a:b] = [name] * (b - a)
    parts = {}
    for name, (head, parent, _) in bones.items():
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if owner[v.index] != name], context="VERTS")
        bmesh.ops.translate(bm, verts=bm.verts, vec=-head)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in ob.data.materials:
            me.materials.append(m)
        po = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(po)
        po.rotation_mode = "XYZ"
        parts[name] = (po, head, parent)
    for name, (po, head, parent) in parts.items():
        if parent:
            po.parent = parts[parent][0]
            po.location = head - parts[parent][1]
        else:
            po.location = head
    return {n: p[0] for n, p in parts.items()}


def box_mesh(name, lo, hi, materials):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector(lo[k] + (hi[k] - lo[k]) * (v.co[k] + 0.5) for k in range(3))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    return me


def ramp_collision(parts):
    """BZ1 snapshots floor faces once, when the object is added (frame 0, ramp closed), so the
    animated ramp can never be driven on. Like the BZ2 condor's static collision mesh, per ramp:
      adr11rpf/fpf  static slab posed at the open angle, no ANIM keys, no visual (no mesh vertices);
                    its top sits 5 cm above the visual ramp's deck and runs 1 m past the lip into the ground.
      adr11rmp/fmp  keeps its name, pivot and keys (the engine moves the visual bone from them), but its
                    GEO shrinks to a 0.4 m block at the hinge so the swinging plate has no walls."""
    for name, (slab, sign) in RAMPS.items():
        ramp = parts[name]
        mats = list(ramp.data.materials)
        old = ramp.data
        ramp.data = box_mesh(name, (-0.2, min(0, sign * 0.4), 0.0), (0.2, max(0, sign * 0.4), 0.4), mats)
        bpy.data.meshes.remove(old)
        hw, length = BAY_HW - 0.2, BAY_ZC - BAY_ZF + 1.0
        # the slab's local +y is the deck side for +sign; mirrored for the bow ramp
        y0, y1 = (-1.0, 0.05) if sign > 0 else (-0.05, 1.0)
        pf = bpy.data.objects.new(slab, box_mesh(slab, (-hw, y0, 0.0), (hw, y1, length), mats))
        bpy.context.scene.collection.objects.link(pf)
        pf.parent = parts["adr11bdy"]
        pf.location = ramp.location
        pf.rotation_mode = "XYZ"
        pf.rotation_euler = (math.radians(sign * RAMP_OPEN), 0, 0)
        parts[slab] = pf


def setup_geo(parts):
    for name, po in parts.items():
        bm = bmesh.new()             # GEO faces cap at ~10 vertices: fan the big caps into triangles
        bm.from_mesh(po.data)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 8])
        bm.to_mesh(po.data)
        bm.free()
        g = po.GEOPropertyGroup
        g.GEOType = 61               # as every stock abhang part
        g.GenerateCollision = True
        g.BoundsMode = "AUTO"
        print("GEO", name, len(po.data.polygons), "faces")


def setup_sdf():
    sc = bpy.context.scene
    p = sc.SDFVDFPropertyGroup     # header copied from the stock hangar (abhang.sdf)
    p.Name = "NSDF Dropship"
    p.VehicleSize, p.VehicleType, p.StructureType = 2, 1, 1
    p.Mass, p.CollMult, p.DragCoefficient = 1750.0, 1.0, 0.0008
    p.Defensive = 500000
    p.DeathExplosion, p.DeathSound = "xbldx1.xdf", "null"
    p.LOD1 = 5.0
    p.UseAdvancedAnimHeader = True
    sc.AnimationCollection.clear()
    for idx, start, length in ANIM_ELEMENTS:
        e = sc.AnimationCollection.add()
        e.Index, e.Start, e.Length, e.Loop, e.Speed = idx, start, length, 1, 15.0


def key_ramp(ramp, sign):
    """Ramp hinge rotation about X: closed at frame 0, lip on the ground at OPEN_FRAMES."""
    # Key EVERY frame, as stock moving parts do (sbwpow/abspow: one rotation key per frame).
    # (The "missing" open ramp was not the keys: its deck face was inside-out, see build_dropship.)
    for f in range(OPEN_FRAMES + 1):
        t = f / OPEN_FRAMES
        ramp.rotation_euler = (math.radians(sign * RAMP_SIGN * (RAMP_SWING or RAMP_OPEN) * t), 0, 0)
        ramp.keyframe_insert("rotation_euler", frame=f)
        ramp.keyframe_insert("location", frame=f)
    ramp.rotation_euler = (0, 0, 0)


def tag_materials(parts):
    for m in next(iter(parts.values())).data.materials:
        m.MaterialPropertyGroup.MapTexture = TEXNAME[m.name.rsplit("_", 1)[1]]


def ogre_xml(src, dst):
    """OgreXMLConverter segfaults on exit after writing; trust the output file, not the exit code."""
    if os.path.exists(dst):
        os.remove(dst)
    subprocess.run([CONV, src, dst], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert os.path.exists(dst), dst
    return dst


def retarget_mesh(tex_mesh, tex_skel):
    """Textured rig mesh -> porter frame and skeleton; writes DEST/NAME.mesh."""
    tmp = os.path.join(DEST, "_xml")
    os.makedirs(tmp, exist_ok=True)
    bone_ids = lambda xml: {n: i for i, n in re.findall(r'<bone id="(\d+)" name="([^"]+)"', open(xml).read())}
    old = {i: n for n, i in bone_ids(ogre_xml(tex_skel, os.path.join(tmp, "tex.skeleton.xml"))).items()}
    new = bone_ids(ogre_xml(os.path.join(DEST, NAME + ".skeleton"), os.path.join(tmp, "port.skeleton.xml")))
    x = open(ogre_xml(tex_mesh, os.path.join(tmp, "tex.mesh.xml"))).read()
    turn = lambda m: f'<{m[1]} x="{-float(m[2]):g}" y="{m[3]}" z="{-float(m[4]):g}"'
    x = re.sub(r'<(position|normal|tangent|binormal) x="([^"]+)" y="([^"]+)" z="([^"]+)"', turn, x)
    x = re.sub(r'boneindex="(\d+)"', lambda m: f'boneindex="{new[old[m[1]]]}"', x)
    x = re.sub(r'<skeletonlink name="[^"]+"', f'<skeletonlink name="{NAME}.skeleton"', x)
    x = x.replace(f'material="{NAME}_tex_', f'material="{NAME}_')
    open(os.path.join(tmp, "out.mesh.xml"), "w").write(x)
    ogre_xml(os.path.join(tmp, "out.mesh.xml"), os.path.join(DEST, NAME + ".mesh"))
    shutil.rmtree(tmp)
    print("RETARGET", sorted(set(re.findall(r'<submesh material="([^"]+)"', x))))


CONV = os.path.join(bpy.utils.user_resource("SCRIPTS"), "addons", "bz98tools", "ogretools", "OgreXMLConverter.exe")
addon_utils.enable("bz98tools", default_set=True)
K.setup_scene()
ob, bones = build(NAME + "_tex")
# legacy SDF front is Blender +Y; the model's bow faces -Y, so turn it round (ramp ends up at -Y)
ob.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
for b in bones.values():
    b[0] = Vector((-b[0].x, -b[0].y, b[0].z))
ao = rig(ob, bones)
export_rigged(ob, ao)                  # -> K.OUT/avdropo_tex.{mesh,skeleton}, UV-textured, rigid weights
ob.modifiers.clear()
bpy.data.objects.remove(ao)
parts = split_parts(ob, bones)
bpy.data.objects.remove(ob)
for o in list(bpy.context.scene.objects):
    if o.name not in parts:
        bpy.data.objects.remove(o)     # cameras/lights would be exported as GEOs
ramp_collision(parts)
setup_geo(parts)
setup_sdf()
for name, (_, sign) in RAMPS.items():
    key_ramp(parts[name], sign)
tag_materials(parts)
bpy.context.scene.frame_set(0)
os.makedirs(DEST, exist_ok=True)
res = bpy.ops.export_scene.sdf(filepath=os.path.join(DEST, NAME + ".sdf"), ExportAnimations=True,
                               auto_port_ogre=True, ogre_name=NAME, ogre_dest_dir=DEST,
                               ogre_skip_unchanged=False)
print("EXPORT_SDF", res)
for issue in bpy.context.scene.bz_validation_issues:
    print("ISSUE", *(getattr(issue, k, "") for k in ("severity", "code", "message")))
for part in parts:                     # the exporter writes face centres, not planes: no collision
    print("PLANES", part, round(geo_planes.fix(os.path.join(DEST, part + ".geo")), 2))
retarget_mesh(os.path.join(K.OUT, NAME + "_tex.mesh"), os.path.join(K.OUT, NAME + "_tex.skeleton"))
for f in (NAME + "_tex.mesh", NAME + "_tex.skeleton"):
    os.remove(os.path.join(K.OUT, f))
for f in (NAME + "_port.material", NAME + "_flat_D.dds"):    # porter's flat-colour fallback
    if os.path.exists(os.path.join(DEST, f)):
        os.remove(os.path.join(DEST, f))
K.write_ogre_material(NAME, FAC)
shutil.move(os.path.join(K.OUT, NAME + ".material"), os.path.join(DEST, NAME + ".material"))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(DEST, NAME + ".blend"))
