"""svdrop / cvdrop as animated SDF buildings, three variants each (the avdropc / avdropo / avdropx set).

  <ship>c  ramps shut: ANIM index 0 swings every moving part 0.001 deg (the repairdepot class plays it once, invisibly)
  <ship>o  ANIM index 0 (frames 0-30) opens the ramp (and svdrop's two clamshell doors) once, on creation
  <ship>x  ANIM index 0 runs 30 -> 0: it starts open and folds shut once, on creation

Same recipe as build_dropship_sdf.py (avdrop; see README.md "SDF variant"): each bone is its own GEO (type 61), Redux
animates the part carrying the GEO's name from the SDF ANIM chunk, the ramp gets a static collision slab (the visual ramp's
own GEO shrinks to a 0.4 m block, because BZ1 snapshots floor faces once when the object is created), and face planes are
rewritten by geo_planes. The geometry comes from build_svdrop.py / build_cvdrop.py (their source up to the packaging call is
executed unchanged); the UVs and materials come from dropkit.finish_uv, so the mesh matches the shipped <ship>.mesh.
Serialisation is the BZ98 toolkit exporter only (bpy.ops.export_scene.sdf with auto_port_ogre).

The model is turned 180 degrees about Z first, so its bow is at +Y (the legacy SDF front, like avdrop). The ramp of svdrop is
then at the stern (-Y), the ramp of cvdrop at the bow (+Y).

Run: blender -b -P build_faction_sdf.py -- svdrop      (or cvdrop; run texgen_*stock.py first, the atlas must be painted)
Output: Local/dropships/out/sdf/<ship>{c,o,x}.{sdf,mesh,skeleton,material} and <part>.geo
"""
import math
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import bpy                                    # noqa: E402
import bmesh                                  # noqa: E402
import addon_utils                            # noqa: E402
from mathutils import Matrix, Vector          # noqa: E402
import dropkit as C                           # noqa: E402
import geo_planes                             # noqa: E402
import paths                                  # noqa: E402

SHIP = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "svdrop"
SRC = os.path.join(HERE, f"build_{SHIP}.py")
assert os.path.exists(SRC), SRC
DEST = os.path.join(paths.OUT, "sdf")
OPEN_FRAMES = 30            # 2 s at 15 fps, the stock hangar's rate
TINY = 0.001                # degrees: the "shut" variant's invisible swing
VARIANTS = {                # name suffix -> (swing in degrees or None for full, ANIM elements (index, start, length))
    "c": (TINY, [(0, 0, OPEN_FRAMES + 1), (1, OPEN_FRAMES, -(OPEN_FRAMES + 1)), (4, 0, OPEN_FRAMES + 1)]),
    "o": (None, [(0, 0, OPEN_FRAMES + 1), (1, OPEN_FRAMES, -(OPEN_FRAMES + 1)), (4, 0, OPEN_FRAMES + 1)]),
    "x": (None, [(0, OPEN_FRAMES, -(OPEN_FRAMES + 1)), (1, OPEN_FRAMES, -(OPEN_FRAMES + 1)), (4, 0, OPEN_FRAMES + 1)]),
}

# ---- geometry: the ship's own script, up to (not including) its packaging step ------------------------------------------
_code = open(SRC, encoding="utf-8").read()
ns = {"__file__": SRC, "__name__": "faction_ship"}
exec(compile(_code[:_code.index("\nC.package(")], SRC, "exec"), ns)
ship, ao, cfg, report, FAC, P = ns["ship"], ns["ao"], ns["cfg"], ns["report"], ns["FAC"], ns["P"]
PARTS = ns["parts"]                           # (bone, object, head, parent); objects are joined away, heads/parents remain
OPEN = ns["OPEN"]                             # Blender-frame open pose: (bone, "rot", axis, degrees)
RAMP_BONE = P + "rmp"
RAMP_W, RAMP_L = report["ramp"]["width"], ns["RAMP_L"]
TEXNAME = {"hull": FAC + "hull", "trim": FAC + "trim"}   # GEO texture names are 8 characters
CONV = os.path.join(bpy.utils.user_resource("SCRIPTS"), "addons", "bz98tools", "ogretools", "OgreXMLConverter.exe")
addon_utils.enable("bz98tools", default_set=True)

# ---- textured, rigged mesh in the SDF frame ---------------------------------------------------------------------------
TEXNAME_SHIP = SHIP + "_sdftex"
ship.name = ship.data.name = TEXNAME_SHIP
print("UV", C.finish_uv(ship, TEXNAME_SHIP, FAC, cfg.get("hold"), cfg.get("classify"), cfg.get("atlas", 4096)))
ship.data.transform(Matrix.Rotation(math.pi, 4, "Z"))        # bow to +Y
heads = {}
bpy.context.view_layer.objects.active = ao
bpy.ops.object.mode_set(mode="EDIT")
for eb in ao.data.edit_bones:                                # same turn for the rig: head (x, y, z) -> (-x, -y, z)
    h = eb.head
    eb.head = Vector((-h.x, -h.y, h.z))
    eb.tail = eb.head + Vector((0, 0, 3))
    heads[eb.name] = Vector(eb.head)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.context.view_layer.update()
parents = {b: p for b, _, _, p in PARTS}
bones = [b for b, _, _, _ in PARTS]


C.export_rigged(ship, ao)                     # textured rest-pose rig -> OUT/<ship>_sdftex.{mesh,skeleton}
tex_mesh = os.path.join(paths.OUT, TEXNAME_SHIP + ".mesh")
tex_skel = os.path.join(paths.OUT, TEXNAME_SHIP + ".skeleton")

# ---- split into one object per bone ---------------------------------------------------------------------------------
owner = [None] * len(ship.data.vertices)
for v in ship.data.vertices:
    owner[v.index] = ship.vertex_groups[v.groups[0].group].name
assert all(owner) and set(owner) == set(bones), (set(bones) - set(owner), set(owner) - set(bones))
ship.modifiers.clear()
bpy.data.objects.remove(ao)
objs = {}
for name in bones:
    bm = bmesh.new()
    bm.from_mesh(ship.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if owner[v.index] != name], context="VERTS")
    bmesh.ops.translate(bm, verts=bm.verts, vec=-heads[name])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in ship.data.materials:
        me.materials.append(m)
    po = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(po)
    po.rotation_mode = "XYZ"
    objs[name] = po
for name, po in objs.items():
    if parents[name]:
        po.parent = objs[parents[name]]
        po.location = heads[name] - heads[parents[name]]
    else:
        po.location = heads[name]
bpy.data.objects.remove(ship)
for o in list(bpy.context.scene.objects):
    if o.name not in objs:
        bpy.data.objects.remove(o)               # cameras and lights would be exported as GEOs

# ---- animation spec in the SDF frame ------------------------------------------------------------------------------------
# The Rz(pi) turn flips rotations about X and keeps rotations about Z.
MOVES = {}                                       # bone -> (axis index, signed degrees)
for bone, _, axis, deg in OPEN:
    MOVES[bone] = (0 if axis == "X" else 2, -deg if axis == "X" else deg)
print("MOVES", MOVES)
ramp = objs[RAMP_BONE]
ramp_x_sign = 1 if MOVES[RAMP_BONE][1] > 0 else -1


def world_verts(po):
    return [po.matrix_world @ v.co for v in po.data.vertices]


def pose(frame_deg):
    """Set every moving part to frame_deg (fraction 0..1 of its open swing) and refresh."""
    for bone, (axis, deg) in MOVES.items():
        e = [0.0, 0.0, 0.0]
        e[axis] = math.radians(deg * frame_deg)
        objs[bone].rotation_euler = tuple(e)
    bpy.context.view_layer.update()


# The ramp's own frame in its closed pose (local, relative to the hinge): d = long axis (hinge -> far edge) in (y, z), n = deck
# normal, the one that ends up pointing up once the part is swung open. avdrop's ramp closes vertically, cvdrop's leans 45 deg.
rv = [v.co.copy() for v in ramp.data.vertices]
far = max(math.hypot(v.y, v.z) for v in rv)
tip = [v for v in rv if math.hypot(v.y, v.z) > 0.9 * far]
dy0, dz0 = sum(v.y for v in tip) / len(tip), sum(v.z for v in tip) / len(tip)
edges = []                                       # the ramp's long edges, projected on (y, z): they run along d exactly
for e in ramp.data.edges:
    q, r = (ramp.data.vertices[i].co for i in e.vertices)
    ey, ez = r.y - q.y, r.z - q.z
    if ey * dy0 + ez * dz0 < 0:
        ey, ez = -ey, -ez
    edges.append((math.hypot(ey, ez), ey, ez))
longest = max(t[0] for t in edges)
dy, dz = (sum(t[1] for t in edges if t[0] > 0.9 * longest), sum(t[2] for t in edges if t[0] > 0.9 * longest))
dl = math.hypot(dy, dz)
dy, dz = dy / dl, dz / dl
phi = math.radians(MOVES[RAMP_BONE][1])
ny, nz = -dz, dy                                 # (y, z) perpendicular of d
if ny * math.sin(phi) + nz * math.cos(phi) < 0:
    ny, nz = -ny, -nz
a_max = max(v.y * dy + v.z * dz for v in rv)     # ramp length along d
b_deck = max(v.y * ny + v.z * nz for v in rv)    # deck face, along n
print("RAMP frame d", (round(dy, 3), round(dz, 3)), "n", (round(ny, 3), round(nz, 3)), "length", round(a_max, 2),
      "deck offset", round(b_deck, 3))
pose(1.0)
ramp_open = world_verts(ramp)
lip_z = min(p.z for p in ramp_open)
assert -0.3 < lip_z < 0.4, f"open ramp lip not on the ground: z={lip_z}"
deck_pts = [(p.y, p.z) for p, v in zip(ramp_open, rv) if abs(v.y * ny + v.z * nz - b_deck) < 1e-3]   # open deck, world (y, z)
assert deck_pts, "no deck vertices on the ramp"
pose(0.0)
for bone, (axis, deg) in MOVES.items():
    if axis == 2:                                # a door must swing outward: its |x| extreme grows
        before = max(abs(p.x) for p in world_verts(objs[bone]))
        pose(1.0)
        after = max(abs(p.x) for p in world_verts(objs[bone]))
        pose(0.0)
        assert after > before + 1.0, f"{bone} does not swing outward ({before} -> {after})"


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


# collision slab (invisible, static, posed open) + the visual ramp's GEO shrunk to a hinge block
SLAB = P + "rpf"
mats = list(ramp.data.materials)
old = ramp.data
ramp.data = box_mesh(RAMP_BONE, (-0.2, min(0, ramp_x_sign * 0.4), 0.0), (0.2, max(0, ramp_x_sign * 0.4), 0.4), mats)
bpy.data.meshes.remove(old)
hw, length = RAMP_W / 2, a_max + 1.0              # the slab runs 1 m past the lip into the ground


def slab_mesh(name, b0, b1):
    """Box in the closed ramp's local frame: x +-hw, a (along d) 0..length, b (along n) b0..b1."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        x, aa, bb = hw * 2 * v.co.x, length * (v.co.y + 0.5), b0 + (b1 - b0) * (v.co.z + 0.5)
        v.co = Vector((x, aa * dy + bb * ny, aa * dz + bb * nz))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    return me


slab = bpy.data.objects.new(SLAB, slab_mesh(SLAB, b_deck - 1.0, b_deck + 0.05))   # top is 5 cm above the visual deck
bpy.context.scene.collection.objects.link(slab)
slab.parent = objs[P + "bdy"]
slab.location = ramp.location
slab.rotation_mode = "XYZ"
slab.rotation_euler = (phi, 0, 0)
objs[SLAB] = slab
bpy.context.view_layer.update()
# the slab's deck edge must sit on the visual ramp's deck: compare along the open ramp line
(ya, za), (yb, zb) = [(w.y, w.z) for w in (slab.matrix_world @ Vector((0, aa * dy + (b_deck + 0.05) * ny,
                                                                         aa * dz + (b_deck + 0.05) * nz))
                                            for aa in (0.0, length))]
worst, n = 0.0, 0
for y, z in deck_pts:
    t = (y - ya) / (yb - ya)
    if t < 1 - 1.0 / length + 0.01:              # the slab runs 1 m past the lip
        worst, n = max(worst, abs(za + (zb - za) * t - z)), n + 1
assert n >= 4, f"slab and ramp deck do not overlap along y: {deck_pts[:4]} slab {(ya, za)}..{(yb, zb)}"
assert worst < 0.4, f"collision slab is off the visual ramp deck by {worst:.2f} m"
print("SLAB deck match worst", round(worst, 3), "m over", n, "deck points; lip z", round(lip_z, 3))

for name, po in objs.items():                    # GEO faces cap at ~10 vertices: fan the big caps into triangles
    bm = bmesh.new()
    bm.from_mesh(po.data)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 8])
    bm.to_mesh(po.data)
    bm.free()
    g = po.GEOPropertyGroup
    g.GEOType = 61                               # as every stock abhang part
    g.GenerateCollision = True
    g.BoundsMode = "AUTO"
    print("GEO", name, len(po.data.polygons), "faces")
for m in next(iter(objs.values())).data.materials:
    m.MaterialPropertyGroup.MapTexture = TEXNAME[m.name.rsplit("_", 1)[1]]


def ogre_xml(src, dst):
    """OgreXMLConverter segfaults on exit after writing; trust the output file, not the exit code."""
    if os.path.exists(dst):
        os.remove(dst)
    subprocess.run([CONV, src, dst], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert os.path.exists(dst), dst
    return dst


def retarget_mesh(name):
    """Textured rig mesh -> the porter's frame and skeleton; writes DEST/<name>.mesh (as build_dropship_sdf.py)."""
    tmp = os.path.join(DEST, "_xml")
    os.makedirs(tmp, exist_ok=True)
    bone_ids = lambda xml: {n: i for i, n in re.findall(r'<bone id="(\d+)" name="([^"]+)"', open(xml).read())}
    old_ids = {i: n for n, i in bone_ids(ogre_xml(tex_skel, os.path.join(tmp, "tex.skeleton.xml"))).items()}
    new_ids = bone_ids(ogre_xml(os.path.join(DEST, name + ".skeleton"), os.path.join(tmp, "port.skeleton.xml")))
    x = open(ogre_xml(tex_mesh, os.path.join(tmp, "tex.mesh.xml"))).read()
    turn = lambda m: f'<{m[1]} x="{-float(m[2]):g}" y="{m[3]}" z="{-float(m[4]):g}"'
    x = re.sub(r'<(position|normal|tangent|binormal) x="([^"]+)" y="([^"]+)" z="([^"]+)"', turn, x)
    x = re.sub(r'boneindex="(\d+)"', lambda m: f'boneindex="{new_ids[old_ids[m[1]]]}"', x)
    x = re.sub(r'<skeletonlink name="[^"]+"', f'<skeletonlink name="{name}.skeleton"', x)
    x = x.replace(f'material="{TEXNAME_SHIP}_', f'material="{name}_')
    open(os.path.join(tmp, "out.mesh.xml"), "w").write(x)
    ogre_xml(os.path.join(tmp, "out.mesh.xml"), os.path.join(DEST, name + ".mesh"))
    shutil.rmtree(tmp)
    print("RETARGET", name, sorted(set(re.findall(r'<submesh material="([^"]+)"', x))))


def setup_sdf(elements):
    sc = bpy.context.scene
    p = sc.SDFVDFPropertyGroup                   # header copied from the stock hangar (abhang.sdf), as avdrop
    p.Name = "CCA Dropship" if FAC == "cdrv" else "CRA Dropship"
    p.VehicleSize, p.VehicleType, p.StructureType = 2, 1, 1
    p.Mass, p.CollMult, p.DragCoefficient = 1750.0, 1.0, 0.0008
    p.Defensive = 500000
    p.DeathExplosion, p.DeathSound = "xbldx1.xdf", "null"
    p.LOD1 = 5.0
    p.UseAdvancedAnimHeader = True
    sc.AnimationCollection.clear()
    for idx, start, ln in elements:
        e = sc.AnimationCollection.add()
        e.Index, e.Start, e.Length, e.Loop, e.Speed = idx, start, ln, 1, 15.0


def key_moves(swing):
    """Every moving part keyed on EVERY frame 0-30 (rotation and position), as stock moving parts are."""
    for bone, (axis, deg) in MOVES.items():
        po = objs[bone]
        po.animation_data_clear()
        total = (math.copysign(swing, deg) if swing else deg)
        for f in range(OPEN_FRAMES + 1):
            e = [0.0, 0.0, 0.0]
            e[axis] = math.radians(total * f / OPEN_FRAMES)
            po.rotation_euler = tuple(e)
            po.keyframe_insert("rotation_euler", frame=f)
            po.keyframe_insert("location", frame=f)
        po.rotation_euler = (0, 0, 0)


os.makedirs(DEST, exist_ok=True)
for suffix, (swing, elements) in VARIANTS.items():
    name = SHIP + suffix
    key_moves(swing)
    setup_sdf(elements)
    bpy.context.scene.frame_set(0)
    res = bpy.ops.export_scene.sdf(filepath=os.path.join(DEST, name + ".sdf"), ExportAnimations=True,
                                   auto_port_ogre=True, ogre_name=name, ogre_dest_dir=DEST, ogre_skip_unchanged=False)
    print("EXPORT_SDF", name, res)
    for issue in bpy.context.scene.bz_validation_issues:
        print("ISSUE", *(getattr(issue, k, "") for k in ("severity", "code", "message")))
    for part in objs:                            # the exporter writes face centres, not planes: no collision
        print("PLANES", part, round(geo_planes.fix(os.path.join(DEST, part + ".geo")), 2))
    retarget_mesh(name)
    for f in (name + "_port.material", name + "_flat_D.dds"):   # porter's flat-colour fallback
        if os.path.exists(os.path.join(DEST, f)):
            os.remove(os.path.join(DEST, f))
    C.write_material(name, FAC)
    shutil.move(os.path.join(paths.OUT, name + ".material"), os.path.join(DEST, name + ".material"))
for f in (TEXNAME_SHIP + ".mesh", TEXNAME_SHIP + ".skeleton"):
    os.remove(os.path.join(paths.OUT, f))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(DEST, SHIP + "_sdf.blend"))
print("DONE", SHIP)
