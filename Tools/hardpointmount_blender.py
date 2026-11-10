"""Blender background step of Tools/Build-HardpointMounts.py: one kit piece, in its own frame.

    blender -b --python Tools/hardpointmount_blender.py -- piece out.npz

piece is rocket, cannon or mortar. The frame is the attach frame: x right, y the surface normal
(out of the hull), z along the surface toward the front; the saddle sits on y = 0 and runs BURY
below it, the part that is buried in the host hull. Every piece is built once, here, so its UV
layout is shared by every unit that carries it; the build tool only moves and scales it.

Every boolean is EXACT, applied one at a time, and must change the solid and leave it closed
and in one piece. Bores, grooves and vents are cut as recesses into the facet they sit on.
Each face keeps the zone of the solid it came from (paint, saddle, metal, bore, accent): the
material slots below, carried through the booleans with material_mode TRANSFER.
"""
import math, sys
import bpy, bmesh
import numpy as np

args = sys.argv[sys.argv.index('--') + 1:]
PIECE = args[0]
BURY = .12
N = 24  # sides of every round part: round mouths are where the triangle budget goes
ZONES = ('paint', 'saddle', 'metal', 'bore', 'accent')


def stats(o):
    bm = bmesh.new(); bm.from_mesh(o.data)
    out = (all(e.is_manifold for e in bm.edges) and len(bm.edges) > 0, bm.calc_volume(signed=False), len(bm.faces))
    bm.free()
    return out


def pieces(o):
    bm = bmesh.new(); bm.from_mesh(o.data); left = set(bm.verts); count = 0
    while left:
        count += 1; stack = [left.pop()]
        while stack:
            for e in stack.pop().link_edges:
                for v in e.verts:
                    if v in left:
                        left.discard(v); stack.append(v)
    bm.free()
    return count


def triangulate(o):
    bm = bmesh.new(); bm.from_mesh(o.data); bmesh.ops.triangulate(bm, faces=bm.faces); bm.to_mesh(o.data); bm.free(); o.data.update()


def solid(name, verts, faces, zone):
    me = bpy.data.meshes.new(name); me.from_pydata([tuple(v) for v in verts], [], faces); me.update()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    for z in ZONES:  # every solid carries all slots in the same order, so indices survive TRANSFER
        me.materials.append(MATERIALS[z])
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)  # no non-planar quads reach a boolean
    for f in bm.faces:
        f.material_index = ZONES.index(zone)
    bm.to_mesh(me); bm.free(); me.update()
    ok, volume, _ = stats(o)
    assert ok and volume > 1e-8, (name, 'not a closed solid', volume)
    return o


def loft(name, rings, zone):
    """Closed solid through equal-length vertex rings (capped at both ends)."""
    K = len(rings[0]); verts = [v for r in rings for v in r]; n = len(rings)
    faces = [list(range(K))[::-1], list(range(K * n - K, K * n))]
    for s in range(n - 1):
        for i in range(K):
            j = (i + 1) % K
            faces.append([K * s + i, K * s + j, K * s + K + j, K * s + K + i])
    return solid(name, verts, faces, zone)


LATHES = [0]


def lathe(name, profile, centre, axis, zone, sides=N):
    """Solid of revolution: profile is a closed list of (radius, distance along axis) from centre.

    Each lathe is turned by a different fraction of a side, so coaxial parts never put their
    edges in the same half-planes (and no ring vertex lands exactly on a box face): coincident
    edges are what leave an EXACT boolean non-manifold."""
    LATHES[0] += 1; phase = (.25 + .618 * LATHES[0]) % 1 * 2 * math.pi / sides
    axis = np.array(axis, float); axis /= np.linalg.norm(axis); c = np.array(centre, float)
    u = np.cross(axis, (0, 1, 0) if abs(axis[1]) < .9 else (1, 0, 0)); u /= np.linalg.norm(u); v = np.cross(axis, u)
    verts, rings = [], []
    for r, s in profile:
        if r == 0:
            rings.append([len(verts)] * sides); verts.append(c + axis * s)
        else:
            rings.append(list(range(len(verts), len(verts) + sides)))
            verts += [c + axis * s + r * (u * math.cos(phase + 2 * math.pi * i / sides) + v * math.sin(phase + 2 * math.pi * i / sides)) for i in range(sides)]
    faces = []
    for k in range(len(rings)):
        a, b = rings[k], rings[(k + 1) % len(rings)]
        for i in range(sides):
            j = (i + 1) % sides
            face = [a[i], a[j], b[j], b[i]]
            face = [x for n, x in enumerate(face) if x not in face[:n]]
            if len(face) >= 3:
                faces.append(face)
    return solid(name, verts, faces, zone)


def octagon(cx, cy, hw, hh, ch):
    """Chamfered rectangle (x, y) points, counter-clockwise."""
    return [(cx + x, cy + y) for x, y in ((hw - ch, -hh), (hw, -hh + ch), (hw, hh - ch), (hw - ch, hh), (-hw + ch, hh), (-hw, hh - ch), (-hw, -hh + ch), (-hw + ch, -hh))]


def prism(name, sections, zone):
    """Loft of chamfered rectangles along z: sections = [(z, cx, cy, hw, hh, ch)]."""
    return loft(name, [[(x, y, z) for x, y in octagon(cx, cy, hw, hh, ch)] for z, cx, cy, hw, hh, ch in sections], zone)


def box(name, lo, hi, zone):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    return solid(name, verts, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]], zone)


def boolean(target, cutter, operation):
    before = stats(target)
    mod = target.modifiers.new(cutter.name, 'BOOLEAN'); mod.operation = operation; mod.solver = 'EXACT'; mod.object = cutter
    mod.material_mode = 'TRANSFER'
    bpy.context.view_layer.objects.active = target
    with bpy.context.temp_override(object=target, active_object=target):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    triangulate(target)
    after = stats(target)
    assert after[0], (cutter.name, 'left the solid non-manifold')
    assert abs(after[1] - before[1]) > 1e-8 and after[2] != before[2], (cutter.name, 'changed nothing', before, after)
    assert pieces(target) == 1, (cutter.name, 'left the solid in more than one piece')
    print('boolean', operation, cutter.name, 'volume %.5f -> %.5f' % (before[1], after[1]), 'faces', before[2], '->', after[2])
    bpy.data.objects.remove(cutter)


def saddle(hw, z0, z1, top):
    """Compact chamfered foot: its lower half is buried in the host hull."""
    return prism('saddle', [(z0, 0, (top - BURY) / 2, hw, (top + BURY) / 2, .03), (z1, 0, (top - BURY) / 2, hw, (top + BURY) / 2, .03)], 'saddle')


def rocket():
    """Boxed four-tube launcher on a short pylon; rocket noses visible in the tubes."""
    body = saddle(.09, -.24, .16, .12)
    boolean(body, prism('pod', [(-.40, 0, .25, .18, .14, .035), (-.37, 0, .25, .20, .16, .04), (.32, 0, .25, .20, .16, .04), (.36, 0, .25, .185, .145, .035)], 'paint'), 'UNION')
    tubes = [(x, y) for y in (.17, .33) for x in (-.095, .095)]
    for i, (x, y) in enumerate(tubes):
        boolean(body, lathe('collar%d' % i, [(0, .30), (.074, .30), (.074, .40), (.066, .43), (0, .43)], (x, y, 0), (0, 0, 1), 'metal'), 'UNION')
    for i, (x, y) in enumerate(tubes):
        boolean(body, lathe('tube%d' % i, [(0, .02), (.052, .02), (.052, .50), (0, .50)], (x, y, 0), (0, 0, 1), 'bore'), 'DIFFERENCE')
    for i, (x, y) in enumerate(tubes):  # warhead noses standing on the tube floor
        boolean(body, lathe('nose%d' % i, [(0, .00), (.042, .00), (.042, .16), (.02, .23), (0, .25)], (x, y, 0), (0, 0, 1), 'accent', sides=12), 'UNION')
    # a band groove round the pod, then a vent row on each flank: recesses into the facet they sit on
    outer = [[(x, y, z) for x, y in octagon(0, .25, .23, .19, .06)] for z in (-.11, -.085)]
    inner = [[(x, y, z) for x, y in octagon(0, .25, .188, .148, .036)] for z in (-.11, -.085)]
    ring = loft('band_o', outer, 'accent'); hole = loft('band_i', inner, 'accent'); boolean(ring, hole, 'DIFFERENCE')
    boolean(body, ring, 'DIFFERENCE')
    for side in (-1, 1):
        for i, z in enumerate((-.30, -.22)):
            x0, x1 = sorted((side * .185, side * .23))
            boolean(body, box('vent%d%d' % (side + 1, i), (x0, .20, z), (x1, .30, z + .05), 'bore'), 'DIFFERENCE')
    return body, (0., .25, .43), (0., 0., 1.)


def cannon():
    """Long slim barrel from a round mantlet on a compact foot, with a ported muzzle brake."""
    body = saddle(.10, -.22, .18, .08)
    y = .17
    boolean(body, lathe('mantlet', [(0, -.24), (.08, -.24), (.11, -.18), (.11, .06), (.085, .12), (0, .12)], (0, y, 0), (0, 0, 1), 'paint'), 'UNION')
    boolean(body, lathe('sleeve', [(0, .10), (.066, .10), (.066, .34), (.052, .38), (0, .38)], (0, y, 0), (0, 0, 1), 'metal'), 'UNION')
    boolean(body, lathe('barrel', [(0, .36), (.040, .36), (.036, 1.24), (0, 1.24)], (0, y, 0), (0, 0, 1), 'metal'), 'UNION')
    boolean(body, lathe('brake', [(0, 1.20), (.050, 1.20), (.060, 1.23), (.060, 1.37), (.052, 1.40), (0, 1.40)], (0, y, 0), (0, 0, 1), 'accent'), 'UNION')
    boolean(body, lathe('bore', [(0, .90), (.026, .90), (.026, 1.50), (0, 1.50)], (0, y, 0), (0, 0, 1), 'bore'), 'DIFFERENCE')
    for side in (-1, 1):  # brake ports: recesses in each flank
        x0, x1 = sorted((side * .036, side * .08))
        boolean(body, box('port%d' % (side + 1), (x0, y - .018, 1.26), (x1, y + .018, 1.34), 'bore'), 'DIFFERENCE')
    boolean(body, lathe('groove', [(.059, .22), (.08, .22), (.08, .235), (.059, .235)], (0, y, 0), (0, 0, 1), 'accent'), 'DIFFERENCE')
    return body, (0., y, 1.40), (0., 0., 1.)


ELEVATION = 40.


def mortar():
    """One short, fat tube raised 40 degrees on trunnions over a base ring."""
    body = lathe('plinth', [(0, -BURY), (.22, -BURY), (.22, .04), (.25, .06), (.25, .09), (.21, .11), (0, .11)], (0, 0, 0), (0, 1, 0), 'saddle')
    boolean(body, box('yoke', (-.19, .09, -.09), (.19, .25, .09), 'paint'), 'UNION')
    e = math.radians(ELEVATION); axis = (0, math.sin(e), math.cos(e)); pivot = (0, .25, 0)
    boolean(body, lathe('tube', [(0, -.20), (.115, -.20), (.13, -.16), (.13, .34), (.15, .36), (.15, .44), (.138, .46), (0, .46)], pivot, axis, 'metal'), 'UNION')
    boolean(body, lathe('trunnion', [(0, -.235), (.055, -.235), (.055, .235), (0, .235)], pivot, (1, 0, 0), 'accent', sides=16), 'UNION')
    boolean(body, lathe('bore', [(0, .02), (.098, .02), (.098, .60), (0, .60)], pivot, axis, 'bore'), 'DIFFERENCE')
    boolean(body, lathe('band', [(.12, .14), (.14, .14), (.14, .16), (.12, .16)], pivot, axis, 'accent'), 'DIFFERENCE')
    boolean(body, lathe('groove', [(.235, .065), (.26, .065), (.26, .08), (.235, .08)], (0, 0, 0), (0, 1, 0), 'accent'), 'DIFFERENCE')
    mouth = np.array(pivot) + np.array(axis) * .46
    return body, tuple(mouth), axis


bpy.ops.wm.read_factory_settings(use_empty=True)
MATERIALS = {z: bpy.data.materials.new(z) for z in ZONES}
body, muzzle, fire = dict(rocket=rocket, cannon=cannon, mortar=mortar)[PIECE]()

# The booleans leave fans of coplanar slivers: merge each flat region (per zone) and split it again cleanly.
bm = bmesh.new(); bm.from_mesh(body.data); count = len(bm.faces)
bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(.5), verts=bm.verts, edges=bm.edges, delimit={'MATERIAL'})
bmesh.ops.triangulate(bm, faces=bm.faces, quad_method='BEAUTY', ngon_method='BEAUTY')
bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
bmesh.ops.triangulate(bm, faces=bm.faces)
assert min(f.calc_area() for f in bm.faces) > 1e-9, 'zero-area triangle left in the solid'
bm.to_mesh(body.data); bm.free(); body.data.update()
ok, volume, faces = stats(body); assert ok, 'cleanup left the solid non-manifold'
assert pieces(body) == 1
print('%s cleanup: faces %d -> %d, volume %.5f' % (PIECE, count, faces, volume))

me = body.data
me.polygons.foreach_set('use_smooth', [True] * len(me.polygons))
me.set_sharp_from_angle(angle=math.radians(35))
me.uv_layers.new(name='uv')
bpy.context.view_layer.objects.active = body; body.select_set(True)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(40), island_margin=0.02)
bpy.ops.object.mode_set(mode='OBJECT')
me = body.data
assert all(len(p.vertices) == 3 for p in me.polygons)
corner = np.array([me.vertices[l.vertex_index].co[:] for l in me.loops], 'f8')
normal = np.array([n.vector[:] for n in me.corner_normals], 'f8')
uv = np.array([d.uv[:] for d in me.uv_layers.active.data], 'f8')
tris = np.array([list(p.loop_indices) for p in me.polygons], 'i4')
zone = np.array([p.material_index for p in me.polygons], 'i4')
for z in range(len(ZONES)):
    assert (zone == z).any(), (PIECE, ZONES[z], 'zone is missing from the solid')
np.savez(args[1], positions=corner, normals=normal, uvs=uv, tris=tris, zone=zone, muzzle=np.array(muzzle, float), fire=np.array(fire, float), bury=BURY)
print('%s solid: %d triangles' % (PIECE, len(tris)))
