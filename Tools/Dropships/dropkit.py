"""Shared helpers for the CCA/CRA dropship builds (build_svdrop.py, build_cvdrop.py); run inside Blender 5.2.
Geometry comes from shipkit (Ship.loft/box); this module adds EXACT booleans with asserts (non-planar quads
are triangulated first), facet recess cutters, the rig, face-local UVs + the hull/hullw/trim split,
the rigged .mesh/.skeleton/.material export, and EEVEE previews + contact sheets."""
import math
import os
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import shipkit as K   # noqa: E402
import paths          # noqa: E402
import bpy            # noqa: E402
import bmesh          # noqa: E402
import numpy as np    # noqa: E402
from mathutils import Vector, Matrix   # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

OUT = K.OUT
LOG = []
# geometry-stage material slots. HULL..TRIM are the final shipkit slots; the rest classify faces for UV/material
HULL, HULLW, TRIM, GLASS, VENT, CARGO, NOZZLE, LAMP = range(8)
_COLS = [(0.62, 0.63, 0.64, 1)] * 3 + [(0.07, 0.09, 0.12, 1), (0.30, 0.31, 0.32, 1), (0.78, 0.55, 0.22, 1),
                                        (0.2, 0.2, 0.2, 1), (1.0, 0.8, 0.3, 1)]
_NAMES = ("hull", "hullw", "trim", "glass", "vent", "cargo", "nozzle", "lamp")
_MATS = []


def reset():
    K.setup_scene()
    _MATS.clear()
    LOG.clear()


def mats():
    if not _MATS:
        for i, c in enumerate(_COLS):
            m = bpy.data.materials.new(_NAMES[i] + "_blk")
            m.diffuse_color = c
            _MATS.append(m)
    return _MATS


def to_object(s, name, idx=None):
    bm = s.bm
    if idx is not None:
        for f in bm.faces:
            f.material_index = idx
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats():
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def solid(name, fn, idx=None, check_it=True):
    s = K.Ship(name, "blk")
    fn(s)
    ob = to_object(s, name, idx)
    if check_it:
        be, bv, vol = check(ob)
        assert be == 0 and bv == 0 and vol > 0, f"{name}: primitive not manifold ({be} edges, {bv} verts, vol {vol})"
    return ob


def loft(sections, axis="y", off=(0, 0, 0)):
    return lambda s: s.loft(sections, ["auto"] * (len(sections) - 1), off=off, axis=axis)


def prism_yz(poly_yz, x0, x1):
    def fn(s):
        bm = s.bm
        a = [bm.verts.new((x0, y, z)) for y, z in poly_yz]
        b = [bm.verts.new((x1, y, z)) for y, z in poly_yz]
        n = len(a)
        bm.faces.new(a)
        bm.faces.new(b)
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new([a[j], a[k], b[k], b[j]])
    return fn


def box(c, size):
    return lambda s: s.box(c, size)


def prof8(hw, zt, zb, ct, cb, cx=0.0):
    return [(cx + hw, zb + cb), (cx + hw, zt - ct), (cx + hw - ct, zt), (cx - hw + ct, zt),
            (cx - hw, zt - ct), (cx - hw, zb + cb), (cx - hw + cb, zb), (cx + hw - cb, zb)]


def ring_pt(t, a, b, axis="y"):
    return Vector((a, t, b)) if axis == "y" else Vector((a, b, t))


def band(sections, i, j, axis="y"):
    (t0, p0), (t1, p1) = sections[i], sections[i + 1]
    n = len(p0)
    k = (j + 1) % n
    return [ring_pt(t0, *p0[j], axis), ring_pt(t0, *p0[k], axis), ring_pt(t1, *p1[k], axis), ring_pt(t1, *p1[j], axis)]


# ------------------------------------------------------------------ mesh checks and booleans
def check(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    be = sum(1 for e in bm.edges if not (e.is_manifold and e.is_contiguous))
    bv = sum(1 for v in bm.verts if not v.is_manifold)
    vol = bm.calc_volume(signed=True)
    bm.free()
    return be, bv, vol


def stats(ob):
    return len(ob.data.vertices), len(ob.data.polygons)


def tri_nonplanar(ob, tol=1e-4):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.normal_update()
    bad = []
    for f in bm.faces:
        if len(f.verts) > 3:
            c = f.calc_center_median()
            if max(abs((v.co - c).dot(f.normal)) for v in f.verts) > tol:
                bad.append(f)
    if bad:
        bmesh.ops.triangulate(bm, faces=bad)
        bm.to_mesh(ob.data)
    bm.free()
    return len(bad)


def boolean(target, cutter, op, label):
    """One EXACT boolean, applied immediately; asserts it changed the mesh and left it manifold."""
    nt = tri_nonplanar(target)
    nc = tri_nonplanar(cutter)
    s0 = stats(target)
    v0 = check(target)[2]
    md = target.modifiers.new("blk", "BOOLEAN")
    md.operation = op
    md.solver = "EXACT"
    md.object = cutter
    md.material_mode = "INDEX"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    target.modifiers.remove(md)
    old = target.data
    target.data = me
    bpy.data.meshes.remove(old)
    cm = cutter.data
    bpy.data.objects.remove(cutter)
    bpy.data.meshes.remove(cm)
    s1 = stats(target)
    be, bv, vol = check(target)
    changed = s1 != s0 and abs(vol - v0) > 1e-6
    ok = changed and be == 0 and bv == 0 and vol > 0
    LOG.append(dict(part=target.name, op=op, label=label, tri_target=nt, tri_cutter=nc, verts=(s0[0], s1[0]),
                    faces=(s0[1], s1[1]), vol=(round(v0, 3), round(vol, 3)), bad_edges=be, bad_verts=bv, ok=ok))
    print(f"BOOL {target.name:10s} {op:10s} {label:28s} faces {s0[1]}->{s1[1]} vol {v0:.2f}->{vol:.2f} "
          f"nonmanifold e{be} v{bv} {'OK' if ok else 'FAIL'}")
    assert ok, f"boolean {label} on {target.name}: changed={changed} bad_edges={be} bad_verts={bv} vol={vol}"
    return target


def union(target, fn_or_ob, label):
    ob = fn_or_ob if isinstance(fn_or_ob, bpy.types.Object) else solid(label, fn_or_ob)
    return boolean(target, ob, "UNION", label)


def cut(target, fn_or_ob, label, idx=None):
    ob = fn_or_ob if isinstance(fn_or_ob, bpy.types.Object) else solid(label, fn_or_ob, idx)
    return boolean(target, ob, "DIFFERENCE", label)


def facet_cutter(pts, inside, inset=0.4, depth=0.3, out=0.6):
    """Prism cutter for a recess in a planar convex facet `pts`; `inside` is a point inside the solid."""
    pts = [Vector(p) for p in pts]
    c = sum(pts, Vector()) / len(pts)
    n = Vector()
    for a, b in zip(pts, pts[1:] + pts[:1]):
        n += a.cross(b)
    n.normalize()
    if n.dot(c - Vector(inside)) < 0:
        n = -n
        pts = pts[::-1]
    u = (pts[1] - pts[0]).normalized()
    v = n.cross(u)
    p2 = [((p - c).dot(u), (p - c).dot(v)) for p in pts]
    m = len(p2)
    lines = []
    for i in range(m):
        (ax, ay), (bx, by) = p2[i], p2[(i + 1) % m]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L
        lines.append(((ax + nx * inset, ay + ny * inset), (dx, dy)))
    q = []
    for i in range(m):
        (p, d), (r, e) = lines[i - 1], lines[i]
        den = d[0] * e[1] - d[1] * e[0]
        if abs(den) < 1e-9:
            q.append(r)
            continue
        t = ((r[0] - p[0]) * e[1] - (r[1] - p[1]) * e[0]) / den
        q.append((p[0] + d[0] * t, p[1] + d[1] * t))
    area = 0.5 * sum(q[i][0] * q[(i + 1) % m][1] - q[(i + 1) % m][0] * q[i][1] for i in range(m))
    if area < 0.3:
        return None
    flat = [c + u * a + v * b for a, b in q]

    def fn(s):
        bm = s.bm
        top = [bm.verts.new(p + n * out) for p in flat]
        bot = [bm.verts.new(p - n * depth) for p in flat]
        bm.faces.new(top)
        bm.faces.new(bot)
        for i in range(m):
            k = (i + 1) % m
            bm.faces.new([top[i], top[k], bot[k], bot[i]])
    return fn


def planar(pts, tol=0.02):
    pts = [Vector(p) for p in pts]
    if len(pts) == 3:
        return True
    n = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
    return all(abs((p - pts[0]).dot(n)) < tol for p in pts)


def recess(target, pts, inside, label, idx, inset=0.4, depth=0.3):
    """Recess into a facet; a non-planar quad is split into two triangles (two panes + mullion)."""
    groups = [pts] if planar(pts) else [[pts[0], pts[1], pts[2]], [pts[0], pts[2], pts[3]]]
    n = 0
    for g_i, g in enumerate(groups):
        fn = facet_cutter(g, inside, inset, depth)
        if fn is None:
            print("SKIP tiny facet", label, g_i)
            continue
        cut(target, fn, f"{label}{'' if len(groups) == 1 else 'ab'[g_i]}", idx)
        n += 1
    return n


# ------------------------------------------------------------------ rig
def join_parts(name, parts):
    """parts: [(bone, ob, head, parent)]; one mesh, rigid vertex groups, armature + modifier."""
    for bone, ob, _, _ in parts:
        ob.vertex_groups.new(name=bone).add(range(len(ob.data.vertices)), 1.0, "REPLACE")
    objs = [p[1] for p in parts]
    main = objs[0]
    with bpy.context.temp_override(active_object=main, object=main, selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()
    main.name = name
    main.data.name = name
    arm = bpy.data.armatures.new(name + "_skel")
    ao = bpy.data.objects.new(name + "_skel", arm)
    bpy.context.scene.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode="EDIT")
    for bone, _, head, parent in parts:
        b = arm.edit_bones.new(bone)
        b.head, b.tail, b.roll = Vector(head), Vector(head) + Vector((0, 0, 3)), 0
        if parent:
            b.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for i, (bone, _, _, _) in enumerate(parts):
        arm.bones[bone]["OGREID"] = i
    md = main.modifiers.new("Armature", "ARMATURE")
    md.object = ao
    for pb in ao.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return main, ao


def apply_pose(ao, keys):
    for bone, kind, *val in keys:
        pb = ao.pose.bones[bone]
        r0 = pb.bone.matrix_local.to_3x3()
        if kind == "rot":
            pb.rotation_quaternion = (r0.inverted() @ Matrix.Rotation(math.radians(val[1]), 3, val[0]) @ r0).to_quaternion()
        else:
            pb.location = r0.inverted() @ Vector(val[0])
    bpy.context.view_layer.update()


def reset_pose(ao):
    for pb in ao.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    bpy.context.view_layer.update()


def evaluated_coords(ob, group=None):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    gi = ob.vertex_groups[group].index if group else None
    pts = [ob.matrix_world @ v.co for v in me.vertices
           if gi is None or any(g.group == gi for g in ob.data.vertices[v.index].groups)]
    ev.to_mesh_clear()
    return pts


def bounds(pts):
    a = np.array([tuple(p) for p in pts])
    return a.min(0), a.max(0)


def proxy_mat(name, rgba, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = rgba
    b.inputs["Roughness"].default_value = 0.6
    return m


def cargo_box(name, w, l, h, x, y, z0, rgba=(0.78, 0.55, 0.22, 1)):
    ob = solid(name, box((x, y, z0 + h / 2), (w, l, h)), CARGO)
    ob.data.materials.clear()
    ob.data.materials.append(proxy_mat(name + "_m", rgba))
    return ob


def overlaps(a, b):
    dg = bpy.context.evaluated_depsgraph_get()
    return len(BVHTree.FromObject(a, dg).overlap(BVHTree.FromObject(b, dg)))


# ------------------------------------------------------------------ face-local UVs
def _crc(*a):
    return zlib.crc32(repr(a).encode())


INT, DARKF, NFLOOR = 100, 101, 102     # pseudo classes used while building UVs
DARK_UV = (1864 / 2048.0, 6 / 2048.0, 160 / 2048.0)      # (u0, v0, size) of texgen_fac.DARK in tile uv


def finish_uv(ob, ship, fac, hold=None, dark=None, cells=False):
    """Assign UVs and the hull / hullw / trim submesh split to the joined, boolean-cut mesh.

    Faces form islands (same class, connected by an edge, normal within ~10 deg of the island's first face). Each island
    has its own metric frame: v = world up projected onto the facet (grime runs downward, text stands upright) for
    walls and slopes, the longest edge for roof/floor facets; u x v = outward normal. Hull islands map K.T_HULL m per
    tile (avdrop density) from the island corner; with cells=True the corner sits on a random 512 px cell origin, so the
    cell edge lines fall on the facet edges, otherwise a per-island tile offset is used. Large flat side facets
    (>= 9 x 6 m) use `hullw` (star + serial at the corner).
    hold=(x0,x1,y0,y1,z0,z1): hull faces inside this box are the hold interior and use the trim `hangar` strip (u metric,
    v stretched; the strip only carries features that are constant along v).
    dark={"under": bool, "groups": (bone prefixes,)}: undersides (normal.z < -0.35), recess walls and listed bone parts
    are UV'd, scaled to fit, into the flat near-black patch of the hull texture.
    Glass floors map one window of the glass cell, vent floors the vent strip, nozzle walls the nozzle strip, nozzle
    floors (radial throat) and lamps their cells; glass/vent/lamp recess walls fall back to hull (dark if dark is set).
    Returns UV stats."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    uvl = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")
    orig = [f.material_index for f in bm.faces]
    kinds = list(orig)
    walls = set()
    for f in bm.faces:
        o = orig[f.index]
        if o in (GLASS, VENT, LAMP):
            for e in f.edges:
                if any(g is not f and orig[g.index] == HULL and f.normal.dot(g.normal) < 0.9 for g in e.link_faces):
                    kinds[f.index] = HULL     # recess wall: plain plating, the floor carries the detail
                    walls.add(f.index)
                    break
        elif o == NOZZLE:
            wall = any(g is not f and orig[g.index] == HULL and f.normal.dot(g.normal) < 0.9
                       for e in f.edges for g in e.link_faces)
            if not wall:
                kinds[f.index] = NFLOOR       # throat floor: radial gradient cell
    legs = set()
    if dark and dark.get("groups"):
        dl = bm.verts.layers.deform.active
        gi = {g.index for g in ob.vertex_groups if g.name.startswith(tuple(dark["groups"]))}
        if dl and gi:
            for f in bm.faces:
                if all(any(k in gi and w > 0.5 for k, w in v[dl].items()) for v in f.verts):
                    legs.add(f.index)
    for f in bm.faces:
        if kinds[f.index] != HULL:
            continue
        if hold:
            cc = f.calc_center_median()
            if hold[0] <= cc.x <= hold[1] and hold[2] <= cc.y <= hold[3] and hold[4] <= cc.z <= hold[5]:
                kinds[f.index] = INT
                continue
        if dark and ((dark.get("under") and f.normal.z < -0.35) or f.index in walls or f.index in legs):
            kinds[f.index] = DARKF
    seen = [False] * len(kinds)
    islands = []
    for f0 in bm.faces:
        if seen[f0.index]:
            continue
        k = kinds[f0.index]
        seen[f0.index] = True
        stack, isl = [f0], []
        n0 = f0.normal
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if not seen[h.index] and kinds[h.index] == k and h.normal.dot(n0) > 0.985:
                        seen[h.index] = True
                        stack.append(h)
        islands.append((k, isl))
    Tm = K.T_HULL
    dens = []
    counts = {"hull": 0, "hullw": 0, "trim": 0, "dark": 0, "hold": 0, "throat": 0}
    up = Vector((0, 0, 1))
    for k, isl in islands:
        n = Vector()
        for g in isl:
            n += g.normal * g.calc_area()
        n.normalize()
        if abs(n.z) < 0.95:
            v = (up - n * n.dot(up)).normalized()
            u = v.cross(n)
        else:
            best = max((e for g in isl for e in g.edges), key=lambda e: e.calc_length())
            d = best.verts[1].co - best.verts[0].co
            u = (d - n * n.dot(d)).normalized()
            v = n.cross(u)
        co = {}
        for g in isl:
            for lp in g.loops:
                co[lp] = (lp.vert.co.dot(u), lp.vert.co.dot(v))
        us = [p[0] for p in co.values()]
        vs = [p[1] for p in co.values()]
        u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
        cen = sum((g.calc_center_median() for g in isl), Vector()) / len(isl)
        h = _crc(round(cen.x, 1), round(cen.y, 1), round(cen.z, 1), k)
        H = max(v1 - v0, 0.1)
        W = max(u1 - u0, 0.1)
        if k == HULL:
            side = abs(n.x) > 0.7 and abs(n.z) < 0.5 and (u1 - u0) >= 9 and (v1 - v0) >= 6
            if side:
                ou = ov = 0.0
            elif cells:
                ou, ov = (h % 4) * 0.25, ((h >> 8) % 4) * 0.25
            else:
                ou, ov = (h & 0xFFFF) / 65535.0, ((h >> 16) & 0xFFFF) / 65535.0
            mat = HULLW if side else HULL
            for lp, (pu, pv) in co.items():
                lp[uvl].uv = ((pu - u0) / Tm + ou, (pv - v0) / Tm + ov)
            counts["hullw" if side else "hull"] += len(isl)
        elif k == DARKF:
            mat = HULL
            su, sv, sz = DARK_UV
            sc = min(1.0 / Tm, (sz * 0.96) / max(W, H))
            for lp, (pu, pv) in co.items():
                lp[uvl].uv = (su + 0.002 + (pu - u0) * sc, sv + 0.002 + (pv - v0) * sc)
            counts["dark"] += len(isl)
        else:
            mat = TRIM
            counts["trim"] += len(isl)
            if k == GLASS:
                i = K.LAY["cells"].index("glass")
                ca = K.LAY["strips"]["cells"][0]
                w = h % 4
                a0, a1 = (i * 256 + 10 + w * 62 + 8) / K.N, (i * 256 + 10 + w * 62 + 42) / K.N
                b0, b1 = 1 - (ca + 188) / K.N, 1 - (ca + 68) / K.N
                f = lambda pu, pv: (a0 + (a1 - a0) * (pu - u0) / W, b0 + (b1 - b0) * (pv - v0) / H)
            elif k in (LAMP, NFLOOR):
                cu0, cu1, cv0, cv1 = K.cell_uv("glow" if k == LAMP else "dish")
                f = lambda pu, pv: (cu0 + (cu1 - cu0) * (pu - u0) / W, cv0 + (cv1 - cv0) * (pv - v0) / H)
                counts["throat"] += len(isl) if k == NFLOOR else 0
            elif k == INT:
                vb, vt = K.strip_v("hangar")
                f = lambda pu, pv: ((pu - u0) / Tm, vb + (vt - vb) * (pv - v0) / H)
                counts["hold"] += len(isl)
            else:
                strip = "nozzle" if k == NOZZLE else "vent"
                vb, vt = K.strip_v(strip)
                m = K.N * H / K.strip_px(strip)
                f = lambda pu, pv: ((pu - u0) / m, vb + (vt - vb) * (pv - v0) / H)
            for lp, (pu, pv) in co.items():
                lp[uvl].uv = f(pu, pv)
        for g in isl:
            g.material_index = mat
        if k == HULL:
            wa = sum(g.calc_area() for g in isl)
            ua = 0.0
            for g in isl:
                p = [lp[uvl].uv for lp in g.loops]
                ua += abs(sum(p[i].x * p[(i + 1) % len(p)].y - p[(i + 1) % len(p)].x * p[i].y for i in range(len(p)))) / 2
            if wa > 0.05:
                dens.append(math.sqrt(ua / wa) * K.N)
    mi = [f.material_index for f in bm.faces]
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()      # clearing the slots resets every face to slot 0, so the indices are restored below
    for m in K.MATS:
        me.materials.append(K.make_material(ship, fac, m))
    me.polygons.foreach_set("material_index", mi)
    for p in me.polygons:
        p.use_smooth = False
    return dict(islands=len(islands), faces=counts, hull_px_per_m=(round(min(dens), 2), round(float(np.median(dens)), 2),
                                                                     round(max(dens), 2)) if dens else None,
                avdrop_px_per_m=round(K.N / Tm, 2))


# ------------------------------------------------------------------ export
def export_rigged(ob, ao):
    """Rest pose, one submesh per material, .mesh + .skeleton through the bz98tools exporter."""
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
        filepath=os.path.join(OUT, ob.name + ".mesh"), xml_converter=conv,
        export_materials=False, export_skeleton=True, export_animation=False, export_poses=False,
        export_colour=False, apply_transform=True, apply_modifiers=True)
    print("EXPORT", ob.name, res, sorted(p.data.materials[0].name for p in parts))
    for p in parts:
        bpy.data.objects.remove(p)
    ao.data.pose_position = "POSE"
    bpy.ops.object.select_all(action="DESELECT")


# ------------------------------------------------------------------ rendering
def setup_eevee():
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in
        sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    w = bpy.data.worlds.new("space")
    sc.world = w
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.05, 0.055, 0.07, 1)
    bg.inputs[1].default_value = 1.0
    for nm, rot, en, colr in (("key", (52, 0, 38), 5.0, (1, 0.96, 0.9)), ("rim", (110, 0, 210), 2.0, (0.6, 0.7, 1.0)),
                              ("fill", (-60, 0, -40), 0.6, (0.8, 0.8, 0.9))):
        L = bpy.data.lights.new(nm, "SUN")
        L.energy, L.color = en, colr
        lo = bpy.data.objects.new(nm, L)
        lo.rotation_euler = [math.radians(a) for a in rot]
        sc.collection.objects.link(lo)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 60
    cam.data.clip_start, cam.data.clip_end = 0.3, 5000
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def shoot(path, target, d, dist, cam=None, lens=None):
    sc = bpy.context.scene
    cam = cam or sc.camera
    if lens:
        cam.data.lens = lens
    d = Vector(d).normalized()
    cam.location = Vector(target) + d * dist
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    cam.data.lens = 60
    return path


def shoot_from(path, loc, target, lens=60):
    sc = bpy.context.scene
    cam = sc.camera
    cam.data.lens = lens
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    cam.data.lens = 60
    return path


def sheet(paths, out, cols=3):
    tw, th = 800, 450
    rows = (len(paths) + cols - 1) // cols
    canvas = np.ones((rows * th, cols * tw, 4), np.float32)
    canvas[..., :3] = 0.1
    for i, p in enumerate(paths):
        img = bpy.data.images.load(p)
        w, h = img.size
        a = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(a)
        a = a.reshape(h, w, 4)[: th * 2, : tw * 2].reshape(th, 2, tw, 2, 4).mean((1, 3))
        r, c = divmod(i, cols)
        canvas[(rows - 1 - r) * th:(rows - r) * th, c * tw:(c + 1) * tw] = a
        bpy.data.images.remove(img)
    im = bpy.data.images.new("sheet_" + os.path.basename(out), cols * tw, rows * th, alpha=True)
    im.pixels.foreach_set(canvas.ravel())
    im.filepath_raw = out
    im.file_format = "PNG"
    im.save()
    return out


def stock_unit(mesh_path, tex_dds, name):
    """Import a stock Redux mesh (toolkit importer), single material with its stock diffuse DDS (loaded in place, nothing copied), skin modifiers dropped, parts joined. Used only for the colour/scale comparison render."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.bz98_bzr_mesh(filepath=mesh_path, import_materials=False)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in meshes:
        for md in list(o.modifiers):
            o.modifiers.remove(md)
        o.parent = None
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
    o.name = name
    img = bpy.data.images.load(tex_dds)      # Blender reads the classic-header DXT1 stock DDS directly
    img.colorspace_settings.name = "sRGB"
    m = bpy.data.materials.new(name + "_m")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = img
    nt.links.new(tx.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.25
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


# ------------------------------------------------------------------ one-call tail for the ship builds
def package(ship, ao, fac, cfg, cargo, open_pose, report):
    """UVs + materials, rigged export, .blend, report JSON, previews and the per-faction contact sheet.
    cfg: ctr, dist, ramp_view=(target, dir, dist), nose=(loc, target), small=(loc, target, lens),
         stock=(mesh .mesh path, diffuse DDS, (x, y) offset of the stock unit)."""
    import json
    name = ship.name
    report["uv"] = finish_uv(ship, name, fac, cfg.get("hold"), cfg.get("dark"), cfg.get("cells", False))
    print("UV", report["uv"])
    export_rigged(ship, ao)
    K.write_ogre_material(name, fac)
    json.dump(report, open(os.path.join(OUT, name + "_report.json"), "w"), indent=1, default=float)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, name + ".blend"))
    if "--norender" in sys.argv:
        return
    o = lambda n: os.path.join(OUT, f"{name}_{n}.png")
    setup_eevee()
    ctr, dist = cfg["ctr"], cfg["dist"]
    for c in cargo:
        c.hide_render = True
    shots = [shoot(o("q34"), ctr, (-1, -1.1, 0.5), dist), shoot(o("side"), ctr, (1, 0, 0.08), dist),
             shoot(o("rear"), ctr, (0.9, 1.2, 0.35), dist), shoot(o("top"), ctr, (0.05, 0.2, 1), dist),
             shoot(o("low"), ctr, (1, -0.8, -0.35), dist)]
    tgt, d, dd = cfg["ramp_view"]
    for c in cargo:
        c.hide_render = False
    apply_pose(ao, open_pose)
    lt = bpy.data.lights.new("bay", "AREA")
    lt.energy, lt.size, lt.color = 60000, 30, (1.0, 0.93, 0.8)
    lo = bpy.data.objects.new("bay", lt)
    lo.location = cfg.get("bay_light", (0, 0, 18))
    bpy.context.scene.collection.objects.link(lo)
    shots.append(shoot(o("ramp_open"), tgt, d, dd))
    reset_pose(ao)
    bpy.data.objects.remove(lo)
    for c in cargo:
        c.hide_render = True
    shots.append(shoot_from(o("nose"), *cfg["nose"]))
    sm = cfg["small"]
    shots.append(shoot_from(o("small"), sm[0], sm[1], sm[2]))
    mesh, dds, (sx, sy) = cfg["stock"]
    st = stock_unit(mesh, dds, "stock_" + os.path.basename(mesh)[:-5])
    st.location = (sx, sy, 0)
    cc = (Vector(ctr) + Vector((sx, sy, 0)) * 0.5)
    shots.append(shoot(o("compare"), cc, (-1, -1.1, 0.5), cfg["compare_dist"]))
    print("SHEET", sheet(shots, os.path.join(OUT, f"{name}_sheet.png")))
