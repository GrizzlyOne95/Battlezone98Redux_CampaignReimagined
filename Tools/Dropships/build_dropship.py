"""NSDF dropship 'avdrop' from the NSDF_DropShip (1)/(2) concept blockouts: a sky-crane upper body
(cockpit fuselage, wing beams, two tall canted lift nacelles) carried on four struts over an
underslung octagonal cargo pod with a rear drop ramp. Sized for a packed Recycler + 4 tanks
(see README_dropship.md). Ground = z 0, forward = -Y.
Run: blender -b -P build_dropship.py [-- --norender]"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as K
from shipkit import octo, circle
import bpy
import bmesh
from mathutils import Matrix, Vector

A, L, ACC, RED, HAZ, GRB, VNT = ("auto", ("trim", "lights"), ("trim", "accent"), ("trim", "redlts"),
                                 ("trim", "hazard"), ("trim", "greeble"), ("trim", "vent"))
import paths
STOCK = paths.STOCK

# ---- key dimensions (metres) -- keep in sync with README_dropship.md
POD_HW, POD_Y0, POD_Y1, POD_ZB, POD_ZT = 20.0, -23.0, 24.0, 3.0, 23.0     # outer shell, open both ends
BAY_HW, BAY_Y0, BAY_ZF, BAY_ZC = 17.5, -23.0, 4.5, 20.5                   # interior; ramps at BAY_Y0 and POD_Y1
BODY_ZB, BODY_ZT = 32.0, 41.0
NAC_X, NAC_HW = 32.0, 5.5
RAMP_T = 1.2
BOW_Y = -24.0
SHIP = sys.argv[sys.argv.index("--ship") + 1] if "--ship" in sys.argv[:-1] else "avdrop"   # avdrop (NSDF) or bvdrop (Black Dog retexture)
if SHIP not in ("avdrop", "bvdrop"):
    sys.exit(f"--ship must be avdrop or bvdrop, not {SHIP!r}")
WING_CELL = "dish" if SHIP == "bvdrop" else "star"   # bvdrop: wing-top marking is the secondary stencil, not the flank emblem
FAC = {"avdrop": "nsdfv", "bvdrop": "bdrv"}[SHIP]   # texture prefix: texgen_avstock.py / texgen_bvstock.py
RAMP_OPEN = math.degrees(math.asin(BAY_ZF / (BAY_ZC - BAY_ZF))) + 90      # lip touches the ground
# landing legs, keyed by (side, y): 1/2 port (+X) fore/aft, 3/4 starboard fore/aft
LEGS = {(1, -18): "adr11lg1", (1, 16): "adr11lg2", (-1, -18): "adr11lg3", (-1, 16): "adr11lg4"}
GEAR_UP = 2.3        # legs telescope up so the pads tuck under the belly
NAC_TILT = 30.0      # nacelles roll the lift bells aft for forward flight
# sample animations: name -> [(bone, "rot", axis, degrees) | (bone, "loc", (x, y, z))], keyed 1 -> 61
ANIMS = {
    "ramp_open": [("adr11rmp", "rot", "X", -RAMP_OPEN), ("adr11fmp", "rot", "X", RAMP_OPEN)],
    "gear_retract": [(b, "loc", (0, 0, GEAR_UP)) for b in LEGS.values()],
    "nacelle_tilt": [(b, "rot", "X", NAC_TILT) for b in ("adr11nc1", "adr11nc2")],
    "vtol_gimbal": [(f"adr11vt{k}", "rot", "X", 15) for k in range(1, 7)],
}


def prof8(hw, zt, zb, ct, cb, cx=0.0):
    """Octagon in (a, b) with separate top/bottom chamfers (same winding as shipkit.octo)."""
    return [(cx + hw, zb + cb), (cx + hw, zt - ct), (cx + hw - ct, zt), (cx - hw + ct, zt),
            (cx - hw, zt - ct), (cx - hw, zb + cb), (cx - hw + cb, zb), (cx + hw - cb, zb)]


def rect(cx, cy, hx, hy):
    return [(cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy), (cx - hx, cy - hy)]


def new_verts(s, n0):
    return list(s.bm.verts)[n0:]


def transform_new(s, n0, mat, cent):
    bmesh.ops.rotate(s.bm, verts=new_verts(s, n0), cent=cent, matrix=mat)


def flip_to(faces, axis, sign):
    for f in faces:
        f.normal_update()
        if f.normal[axis] * sign < 0:
            f.normal_flip()


def strut(s, p0, p1, hx, hy, spec=A):
    """Sheared square strut between (x,y,z) points p0 (low) and p1 (high), lofted along z."""
    s.loft([(p0[2], rect(p0[0], p0[1], hx, hy)), (p1[2], rect(p1[0], p1[1], hx, hy))], [spec], axis="z")


def wing(s, x0, x1, root, tip, cy):
    """Beam along X from |x|=x0 (root) to x1 (tip); root/tip = (depth_y, zt, zb, chamfer).
    Lofted along Y then turned 90 deg about Z, so t -> -x and profile a -> y."""
    n0 = len(s.bm.verts)
    sg = 1 if x1 > 0 else -1
    secs = sorted([(-sg * x0, octo(*root, cy)), (-x1, octo(*tip, cy))], key=lambda t: t[0])
    s.loft(secs, [A])
    transform_new(s, n0, Matrix.Rotation(math.radians(90), 3, "Z"), Vector((0, 0, 0)))


def vtol(s, x, y, ztop, r, length):
    """Downward lift bell: shipkit.engine built along +Y then turned to point -Z.
    Returns the bell's vertex range (for its gimbal bone)."""
    n0 = len(s.bm.verts)
    s.engine(0, x, y, r, length, nozzle_r=r * 0.9, bands=L)
    transform_new(s, n0, Matrix.Rotation(math.radians(-90), 3, "X"), Vector((0, 0, 0)))
    bmesh.ops.translate(s.bm, verts=new_verts(s, n0), vec=(0, 0, ztop))
    return n0, len(s.bm.verts)


def pane(s, f, inset=0.2, lift=0.05, cell="glass"):
    """Glass pane inset inside face f (framed by the face itself), UV'd onto one lit window
    of the atlas glass cell so it glows."""
    f.normal_update()
    n = f.normal.copy()
    pts = [v.co.copy() for v in f.verts]
    c = sum(pts, Vector()) / len(pts)
    pts = [c + (p - c) * (1 - inset) + n * lift for p in pts]
    e1 = (pts[1] - pts[0]).normalized()
    e2 = n.cross(e1)
    loc = [((p - c).dot(e1), (p - c).dot(e2)) for p in pts]
    a0, a1 = min(q[0] for q in loc), max(q[0] for q in loc)
    b0, b1 = min(q[1] for q in loc), max(q[1] for q in loc)
    i = K.LAY["cells"].index(cell)
    ca = K.LAY["strips"]["cells"][0]
    u0, u1 = (i * 256 + 18) / K.N, (i * 256 + 52) / K.N        # one window of the 4 in the cell
    v0, v1 = 1 - (ca + 188) / K.N, 1 - (ca + 68) / K.N
    uvs = [(u0 + (u1 - u0) * (x - a0) / max(1e-6, a1 - a0), v0 + (v1 - v0) * (y - b0) / max(1e-6, b1 - b0))
           for x, y in loc]
    g = s._face([s.bm.verts.new(p) for p in pts], "trim", uvs)
    g.normal_update()
    if g.normal.dot(n) < 0:
        g.normal_flip()


def hexa(hw, zt, zb, cx=0.0):
    zc = (zt + zb) / 2
    return [(cx + hw, zc), (cx + hw * 0.55, zt), (cx - hw * 0.55, zt), (cx - hw, zc),
            (cx - hw * 0.55, zb), (cx + hw * 0.55, zb)]


def framed(s, pts, y, depth, inner=0.72, spec=VNT, frame=L):
    """Raised parallelogram block on a -Y face with a lit frame ring around a louvre panel."""
    s.loft([(y - depth, pts), (y + 0.3, pts)], [A], cap0=A, cap1=A)
    c = Vector((sum(p[0] for p in pts) / 4, 0, sum(p[1] for p in pts) / 4))
    yo = y - depth - 0.02
    O = [Vector((p[0], yo, p[1])) for p in pts]
    I = [c + (Vector((p[0], 0, p[1])) - c) * inner + Vector((0, yo, 0)) for p in pts]
    faces = []
    for j in range(4):
        k = (j + 1) % 4
        q = [I[j], I[k], O[k], O[j]]
        faces.append(s._face([s.bm.verts.new(v) for v in q], "trim", s._quad_uv(frame, q)))
    ip = [I[0], I[1], I[2], I[3]]
    faces.append(s._face([s.bm.verts.new(v) for v in ip], "trim", s._quad_uv(spec, ip)))
    flip_to(faces, 1, -1)


def cockpit(s):
    """Concept front view: stepped faceted canopy dome on the bow face, slanted framed vents
    either side, brow light bars, chin landing floods, red/blue running lights."""
    yb = BOW_Y
    dome = s.loft([(yb + 0.3, hexa(4.8, 39.6, 33.3)), (yb - 2.0, hexa(4.0, 39.0, 33.9)),
                   (yb - 3.6, hexa(2.6, 38.2, 34.6)), (yb - 4.4, hexa(1.5, 37.4, 35.2))],
                  [A, A, A], cap0=None, cap1=A)
    for f in dome:  # glaze every facet that looks forward/up; the chin facets stay plated
        f.normal_update()
        if f.normal.z > -0.35 and f.normal.y < -0.2:
            pane(s, f, inset=0.22)
    s.box((0, yb - 1.2, 39.7), (5.6, 2.4, 0.5), A, faces={"-y": L})          # canopy brow strip
    for sg in (1, -1):
        x = sg * 7.0  # slanted vents, top edge leaning outboard like the concept
        pts = [(x - 1.8, 34.3), (x + 1.8, 34.3), (x + 1.8 + sg * 0.5, 38.0), (x - 1.8 + sg * 0.5, 38.0)]
        if sg < 0:
            pts = [pts[1], pts[0], pts[3], pts[2]]
        framed(s, pts, yb, 0.9)
        s.plate((x, yb, 39.2), (3.6, 0.5), "-y", L, depth=0.25)             # brow light bars
        s.plate((sg * 8.6, yb, 33.4), (0.9, 0.9), "-y", ("cell", "glow"), depth=0.3)
        s.plate((sg * 5.0, yb + 2.5, 32.5), (2.0, 2.0), "-z", ("cell", "glow"), depth=0.3)  # landing floods
        s.plate((sg * 9.95, yb + 1.0, 36.2), (1.0, 2.2), "+x" if sg > 0 else "-x", RED if sg > 0 else L, depth=0.2)


def part(s, bone, head, parent="adr11bdy"):
    """Declare a moving part: bone name -> [head, parent, vertex ranges]. Vertices default
    to the root bone; a part's ranges override its parent's (children are declared after)."""
    s.rig.setdefault(bone, [Vector(head), parent, []])
    return s.rig[bone][2]


def build(name):
    s = K.Ship(name, FAC)
    s.rig = {"adr11bdy": [Vector((0, 0, 0)), None, []]}

    # ---------------- cargo pod: outer octagonal shell, open at both ends (bow and stern ramps)
    s.loft([(POD_Y0, prof8(POD_HW, POD_ZT, POD_ZB, 4, 2.5)),
            (POD_Y0 + 2, prof8(POD_HW + 0.3, POD_ZT + 0.3, POD_ZB - 0.3, 4.1, 2.6)),
            (POD_Y1 - 4, prof8(POD_HW + 0.3, POD_ZT + 0.3, POD_ZB - 0.3, 4.1, 2.6)),
            (POD_Y1, prof8(POD_HW, POD_ZT, POD_ZB, 4, 2.5))],
           [ACC, A, ACC], cap0=None, cap1=None)
    # interior bay: same loft reversed so faces point into the hold; open both ends
    inner = prof8(BAY_HW, BAY_ZC, BAY_ZF, 3.2, 0.4)
    fs = s.loft([(BAY_Y0, inner), (POD_Y1, inner)], [A], cap0=None, cap1=None)
    bmesh.ops.reverse_faces(s.bm, faces=fs)
    # bow and stern frames joining shell to bay
    outer = prof8(POD_HW, POD_ZT, POD_ZB, 4, 2.5)
    for y, sign in ((POD_Y0, -1), (POD_Y1, 1)):
        O = [s.bm.verts.new((a, y, b)) for a, b in outer]
        I = [s.bm.verts.new((a, y, b)) for a, b in inner]
        frame = [s._face([O[j], O[(j + 1) % 8], I[(j + 1) % 8], I[j]], "auto") for j in range(8)]
        flip_to(frame, 1, sign)
    # bay dressing: floor deck plates, hazard edges, wall light strips, ceiling hatches
    s.plate((0, 0, BAY_ZF), (BAY_HW * 2 - 2, POD_Y1 - BAY_Y0 - 2), "+z", GRB, depth=0.15)
    for x in (-1, 1):
        s.plate((x * (BAY_HW - 1.2), 0.5, BAY_ZF + 0.15), (1.2, POD_Y1 - BAY_Y0 - 3), "+z", HAZ, depth=0.1)
        s.plate((x * BAY_HW, 0.5, BAY_ZF + 7), (POD_Y1 - BAY_Y0 - 4, 1.2), "-x" if x > 0 else "+x", L, depth=0.2)
    for y in (-14, 0, 14):
        s.plate((0, y, BAY_ZC), (8, 6), "-z", ("cell", "hatch"), depth=0.2)
    # hull dressing
    s.plate((POD_HW + 0.3, -6, 13), (14, 9), "+x", ("cell", "number"), depth=0.4, mirror_x=True)
    s.plate((POD_HW + 0.3, 12, 13), (10, 10), "+x", ("cell", "star"), depth=0.4, mirror_x=True)
    s.plate((POD_HW + 0.3, -1, POD_ZB + 3.4), (40, 1.6), "+x", HAZ, depth=0.3, mirror_x=True)
    s.plate((0, -1, POD_ZT + 0.3), (24, 34), "+z", GRB, depth=0.4)
    # landing gear: four splayed legs with pads (each its own bone, pivot at the hip) + skid rails
    for x in (-1, 1):
        for y in (-18, 16):
            n0 = len(s.bm.verts)
            strut(s, (x * 17.5, y, 0.6), (x * 14, y, POD_ZB), 0.9, 1.4)
            s.box((x * 17.5, y, 0.3), (5, 7, 0.6), A, faces={"+z": HAZ})
            part(s, LEGS[(x, y)], (x * 14, y, POD_ZB)).append((n0, len(s.bm.verts)))
        s.box((x * 11, -1, POD_ZB - 0.5), (2, 42, 1), A, faces={"-z": GRB})

    # ---------------- bow and stern ramps (each hinged on its bay floor lip, swinging outward)
    rp = prof8(BAY_HW - 0.2, BAY_ZC - 0.2, BAY_ZF, 3.1, 0.3)
    for bone, y, out in (("adr11rmp", POD_Y1, 1), ("adr11fmp", POD_Y0, -1)):
        n0 = len(s.bm.verts)
        fs = s.loft([(min(y, y + out * RAMP_T), rp), (max(y, y + out * RAMP_T), rp)], [ACC], cap0=A, cap1=A)
        # shipkit.loft winds both caps in the same ring order, so one is always inside-out, and its
        # signed-volume fix then depends on where the part sits (the bow ramp came out fully reversed)
        bmesh.ops.recalc_face_normals(s.bm, faces=fs)
        yo, face = y + out * RAMP_T, "+y" if out > 0 else "-y"
        for x in (-1, 1):  # hazard chevrons on the outer face, roundel up top
            s.plate((x * 9, yo, BAY_ZF + 1.4), (12, 1.4), face, HAZ, depth=0.2)
        s.plate((0, yo, BAY_ZF + 9), (7, 7), face, ("cell", "roundel"), depth=0.2)
        part(s, bone, (0, y, BAY_ZF)).append((n0, len(s.bm.verts)))

    # ---------------- struts pod -> body (A-frames, plus a central spine strut)
    for x in (-1, 1):
        for y0, y1 in ((-16, -9), (16, 11)):
            strut(s, (x * 13, y0, POD_ZT - 0.5), (x * 7, y1, BODY_ZB + 0.5), 1.3, 1.6, A)
    strut(s, (0, 2, POD_ZT - 0.5), (0, 2, BODY_ZB + 0.5), 2.2, 2.2, L)

    # ---------------- upper body: fuselage; flat bow face carries the cockpit (concept front view)
    s.loft([(BOW_Y, prof8(9.5, 40, 32.5, 1.5, 1.2)), (-19, prof8(11, 41, 32, 3, 2)),
            (14, prof8(11, 41, 32, 3, 2)), (19, prof8(8, 39.5, 33, 2.5, 1.5))],
           [ACC, A, A], cap0=A, cap1=A)
    s.plate((0, 19, 36), (10, 4), "+y", VNT, depth=0.3)
    cockpit(s)
    # dorsal hump / ridge
    s.loft([(BODY_ZT, rect(0, -2, 7, 13)), (BODY_ZT + 3.5, rect(0, -1, 3, 8))], [A], cap0=None, cap1=A, axis="z")
    s.plate((0, -1, BODY_ZT + 3.5), (5, 14), "+z", GRB, depth=0.2)
    s.plate((0, -8, BODY_ZT + 3.5), (4, 1.2), "+z", RED, depth=0.2)   # dorsal beacon
    s.plate((0, 6, BODY_ZB), (12, 18), "-z", GRB, depth=0.4)
    # wing beams to the nacelles, tapering outboard
    for sg in (1, -1):
        wing(s, 10.5, sg * (NAC_X - NAC_HW + 0.5), (30, 41, 32.5, 2.5), (18, 40, 35, 2), 0)
        s.plate((sg * 19, -6, 40.4), (11, 1.4), "+z", L, depth=0.2)
        s.plate((sg * 19, 0, 40.6), (8, 8), "+z", ("cell", WING_CELL), depth=0.3)

    # ---------------- lift nacelles: tall slabs with hip-roof ends, canted out 7 deg
    for sg in (1, -1):
        n0 = len(s.bm.verts)
        x = sg * NAC_X
        nb = "adr11nc1" if sg > 0 else "adr11nc2"
        cant = Matrix.Rotation(math.radians(sg * 7), 3, "Y")
        piv = Vector((x, 0, 36))
        nac = part(s, nb, piv)
        s.loft([(-13, prof8(NAC_HW - 1.5, 41, 19, 3, 2, x)), (-9, prof8(NAC_HW, 48, 14, 3.5, 2.5, x)),
                (-6, prof8(NAC_HW + 0.2, 48.2, 13.8, 3.6, 2.6, x)), (6, prof8(NAC_HW + 0.2, 48.2, 13.8, 3.6, 2.6, x)),
                (9, prof8(NAC_HW, 48, 14, 3.5, 2.5, x)), (12, prof8(NAC_HW - 1, 44, 16.5, 3, 2, x))],
               [A, L, A, RED, A], cap0=A, cap1=A)
        s.plate((x + sg * (NAC_HW + 0.2), 0, 38), (10, 6), "+x" if sg > 0 else "-x", VNT, depth=0.4)
        s.plate((x + sg * (NAC_HW + 0.2), 0, 24), (9, 9), "+x" if sg > 0 else "-x", ("cell", "chevron"), depth=0.4)
        s.plate((x + sg * (NAC_HW + 0.2), 0, 17), (12, 1.4), "+x" if sg > 0 else "-x", HAZ, depth=0.3)
        for z in (23, 37):        # aft cruise/orbit nozzles
            s.engine(7, x, z, 2.6, 9, bands=L)
        for k, y in enumerate((-6.5, 0, 6.5)):  # ventral lift bells, each on a gimbal bone
            rng = vtol(s, x, y, 14.5, 2.5, 5)
            head = piv + cant @ (Vector((x, y, 14.5)) - piv)
            part(s, f"adr11vt{k + 1 + (0 if sg > 0 else 3)}", head, nb).append(rng)
        transform_new(s, n0, cant, piv)
        nac.append((n0, len(s.bm.verts)))
    ob = s.finish()
    return ob, s.rig


def rig(ob, bones):
    """Armature with one bone per moving part (head = pivot, pointing +Z), rigid weights,
    OGREIDs for the Ogre exporter, and an Armature modifier on the hull."""
    arm = bpy.data.armatures.new(f"{SHIP}_skel")
    ao = bpy.data.objects.new(f"{SHIP}_skel", arm)
    bpy.context.scene.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, parent, _) in bones.items():
        b = arm.edit_bones.new(name)
        b.head, b.tail, b.roll = head, head + Vector((0, 0, 3)), 0
        if parent:
            b.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for i, name in enumerate(bones):
        arm.bones[name]["OGREID"] = i
    owner = ["adr11bdy"] * len(ob.data.vertices)
    for name, (_, _, ranges) in bones.items():
        for a, b in ranges:
            owner[a:b] = [name] * (b - a)
    for name in bones:
        idx = [i for i, n in enumerate(owner) if n == name]
        ob.vertex_groups.new(name=name).add(idx, 1.0, "REPLACE")
    md = ob.modifiers.new("Armature", "ARMATURE")
    md.object = ao
    for pb in ao.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ao


def apply_pose(ao, keys):
    """Pose bones with world-space rotations (about each pivot) / translations."""
    for bone, kind, *val in keys:
        pb = ao.pose.bones[bone]
        r0 = pb.bone.matrix_local.to_3x3()
        if kind == "rot":
            pb.rotation_quaternion = (r0.inverted() @ Matrix.Rotation(math.radians(val[1]), 3, val[0]) @ r0).to_quaternion()
        else:
            pb.location = r0.inverted() @ Vector(val[0])


def reset_pose(ao):
    for pb in ao.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)


def make_actions(ao):
    """One action per sample animation, each on its own muted NLA track (the exporter
    collects NLA strip actions; muting keeps the rest pose for renders)."""
    ad = ao.animation_data_create()
    for name, keys in ANIMS.items():
        act = bpy.data.actions.new(name)
        ad.action = act
        for frame, on in ((1, False), (61, True)):
            reset_pose(ao)
            if on:
                apply_pose(ao, keys)
            for bone, kind, *_ in keys:
                ao.pose.bones[bone].keyframe_insert("rotation_quaternion" if kind == "rot" else "location", frame=frame)
        ad.action = None
        tr = ad.nla_tracks.new()
        tr.name = name
        tr.strips.new(name, 1, act)
        tr.mute = True
    reset_pose(ao)


def export_rigged(ob, ao):
    """shipkit.export_mesh, plus the .skeleton and its animations (rest pose while exporting)."""
    conv = os.path.join(bpy.utils.user_resource("SCRIPTS"), "addons", "bz98tools", "ogretools", "OgreXMLConverter.exe")
    ao.data.pose_position = "REST"
    tmp = ob.copy()
    tmp.data = ob.data.copy()
    bpy.context.collection.objects.link(tmp)
    bpy.ops.object.select_all(action="DESELECT")
    tmp.select_set(True)
    bpy.context.view_layer.objects.active = tmp
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = list(bpy.context.selected_objects)
    for p in parts:
        used = {poly.material_index for poly in p.data.polygons}
        keep = p.data.materials[min(used)]
        p.data.materials.clear()
        p.data.materials.append(keep)
    bpy.context.view_layer.objects.active = parts[0]
    res = bpy.ops.export_scene.bz98_bzr_mesh(
        filepath=os.path.join(K.OUT, ob.name + ".mesh"), xml_converter=conv,
        export_materials=False, export_skeleton=True, export_animation=True, export_poses=False,
        export_colour=False, apply_transform=True, apply_modifiers=True)
    print("EXPORT", ob.name, res, sorted(p.data.materials[0].name for p in parts))
    for p in parts:
        bpy.data.objects.remove(p)
    ao.data.pose_position = "POSE"
    bpy.ops.object.select_all(action="DESELECT")


K.setup_scene()
ob, bones = build(SHIP)
print("FACES", len(ob.data.polygons), "BONES", len(bones))
ao = rig(ob, bones)
make_actions(ao)
export_rigged(ob, ao)
K.write_ogre_material(SHIP, FAC)

# ---------------- cargo proxies (blend/preview only, not exported)


def proxy_mat(name, rgba, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = rgba
    b.inputs["Roughness"].default_value = 0.6
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except (AttributeError, TypeError):
                pass
    return m


def import_stock(mesh, drop_groups=()):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.bz98_bzr_mesh(filepath=os.path.join(STOCK, mesh + ".mesh"), import_materials=False)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in meshes:
        for md in list(o.modifiers):
            o.modifiers.remove(md)
        o.parent = None
        bm = bmesh.new()
        bm.from_mesh(o.data)
        dl = bm.verts.layers.deform.active
        idx = {o.vertex_groups[g].index for g in drop_groups if g in o.vertex_groups}
        if dl and idx:
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if any(i in idx and w > 0.5 for i, w in v[dl].items())],
                             context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = mesh + "_proxy"
    return o


cargo = []
if os.path.isdir(STOCK):   # cargo-fit proxies need the stock avrecy/avtank meshes (not in this repo)
    RECY = (0.0, -4.0)              # packed recycler centre (x, y) on the bay floor
    TANKS = [(-13.2, -12.0), (-13.2, 0.0), (13.2, -12.0), (13.2, 0.0)]
    recy = import_stock("avrecy", drop_groups=("are11bdb", "are11bdc", "are11bdd"))  # fold-out wings removed
    recy.data.materials.clear(); recy.data.materials.append(proxy_mat("cargo_recy", (0.55, 0.5, 0.36, 1)))
    recy.location = (RECY[0], RECY[1] + 1.8, BAY_ZF + 0.2)   # stock origin sits 1.8 m aft of the hull centre
    cargo.append(recy)
    env = bpy.data.objects.new("recy_envelope", bpy.data.meshes.new("recy_envelope"))
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(env.data); bm.free()
    env.scale = (18, 36, 13.4)
    env.location = (RECY[0], RECY[1], BAY_ZF + 0.2 + 6.7)
    env.data.materials.append(proxy_mat("cargo_env", (1.0, 0.6, 0.1, 1), alpha=0.18))
    bpy.context.scene.collection.objects.link(env)
    cargo.append(env)
    tank = import_stock("avtank")
    tank.data.materials.clear(); tank.data.materials.append(proxy_mat("cargo_tank", (0.32, 0.38, 0.24, 1)))
    for i, (x, y) in enumerate(TANKS):
        t = tank if i == 0 else tank.copy()
        if i:
            bpy.context.scene.collection.objects.link(t)
        t.location = (x, y, BAY_ZF + 0.2)
        cargo.append(t)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(K.OUT, SHIP + ".blend"))

if "--norender" not in sys.argv:
    for o in cargo:
        o.hide_render = True
    K.render_previews(ob, SHIP, 230)
    sc = bpy.context.scene
    for vn, loc in (("cockpit", (-14, -62, 44)), ("cockpit_front", (0, -60, 37))):  # bow close-ups
        sc.camera.location = loc
        sc.camera.rotation_euler = (Vector((0, -24, 36)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(K.OUT, f"{SHIP}_{vn}.png")
        bpy.ops.render.render(write_still=True)
    # flight pose: gear up, nacelles tilted, bells gimballed (proves the rig deforms cleanly)
    apply_pose(ao, ANIMS["gear_retract"] + ANIMS["nacelle_tilt"] + ANIMS["vtol_gimbal"])
    cam = sc.camera
    cam.location = (-215, -95, 70)
    cam.rotation_euler = (Vector((0, 0, 22)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(K.OUT, f"{SHIP}_flight.png")
    bpy.ops.render.render(write_still=True)
    reset_pose(ao)
    # bay-open shot: ramp bone lowered, light the hold, look in over the ramp
    apply_pose(ao, ANIMS["ramp_open"])
    for o in cargo:
        o.hide_render = False
    sc = bpy.context.scene
    lt = bpy.data.lights.new("bay", "AREA")
    lt.energy, lt.size, lt.color = 60000, 30, (1.0, 0.93, 0.8)
    lo = bpy.data.objects.new("bay", lt)
    lo.location = (0, 0, BAY_ZC - 1)
    sc.collection.objects.link(lo)
    cam = sc.camera
    cam.location = (48, 125, 30)
    cam.rotation_euler = (Vector((0, -2, 10)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(K.OUT, f"{SHIP}_bayopen.png")
    bpy.ops.render.render(write_still=True)
    # fit-check plan: bay floor outline (dark) + lowered ramp (light) with the load, orthographic top
    ob.hide_render = lo.hide_render = True
    reset_pose(ao)
    for nm, dims, cen, col in (("plan_floor", (2 * BAY_HW, POD_Y1 - BAY_Y0, 0.2), (0, (POD_Y1 + BAY_Y0) / 2, BAY_ZF), (0.12, 0.13, 0.16, 1)),
                               ("plan_ramp", (2 * BAY_HW - 0.4, 15.4, 0.2), (0, POD_Y1 + 7.7, BAY_ZF), (0.3, 0.3, 0.33, 1))):
        pb = bpy.data.objects.new(nm, bpy.data.meshes.new(nm))
        bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(pb.data); bm.free()
        pb.scale, pb.location = dims, cen
        pb.data.materials.append(proxy_mat(nm, col))
        sc.collection.objects.link(pb)
    cam.data.type, cam.data.ortho_scale = "ORTHO", 78
    cam.location, cam.rotation_euler = (0, 9, 200), (0, 0, math.radians(90))  # bow left, ramp right
    sc.render.filepath = os.path.join(K.OUT, f"{SHIP}_bayplan.png")
    bpy.ops.render.render(write_still=True)
