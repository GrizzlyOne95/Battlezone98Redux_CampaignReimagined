"""Blender background step of Tools/CockpitsAndRigs/Build-NacelleJets.py: one thruster housing solid.

    blender -b --python Tools/CockpitsAndRigs/nacellejet_blender.py -- config.json out.npz

Builds, in the housing's build frame (flame along -Y, chord along Z; the unit's Ogre mesh
space when the nacelle is not rotated), a faceted fairing pod whose roof is buried in the
wing, unions the nozzle bell into it, then cuts the bore, a bell groove and the side vents
as recesses. Every boolean is EXACT, applied one at a time, and must change the solid and
leave it manifold and in one piece. Faces left wholly inside the wing are dropped afterwards
(not when the pod overhangs a wing edge: its roof shows there). Writes per-corner
positions, split normals and UVs; binary model I/O stays in the build tool.
"""
import json, math, sys
import bpy, bmesh
import numpy as np

args = sys.argv[sys.argv.index('--') + 1:]
cfg = json.loads(open(args[0]).read())
EX, EY, EZ = cfg['emit']
N = cfg['sides']
OX, OZ = cfg.get('offset', (0., 0.))  # pod body offset from the emit point
SIDE = cfg['underside'][2] if len(cfg['underside']) > 2 else 0.


def under(x, z):
    """Wing underside height at (x, chord position z): plane fit measured by the build tool."""
    return cfg['underside'][0] + cfg['underside'][1] * (z - EZ) + SIDE * (x - EX)


ROOF = np.array(cfg['roof']['h']) if 'roof' in cfg else None


def roof(x, z):
    """Conformal roof: skin height grid measured by the build tool (bilinear, clamped at its edges)."""
    R = cfg['roof']; g = R['step']
    fx = min(max((x - R['x0']) / g, 0), ROOF.shape[0] - 1); fz = min(max((z - R['z0']) / g, 0), ROOF.shape[1] - 1)
    i = min(int(fx), ROOF.shape[0] - 2); j = min(int(fz), ROOF.shape[1] - 2); t = fx - i; u = fz - j
    return float(ROOF[i, j] * (1 - t) * (1 - u) + ROOF[i + 1, j] * t * (1 - u) + ROOF[i, j + 1] * (1 - t) * u + ROOF[i + 1, j + 1] * t * u)


def top(x, z):
    """Height the buried roof is measured from: the conformal skin grid, else the seat plane."""
    return roof(x, z) if ROOF is not None else under(x, z)


def stats(o):
    bm = bmesh.new(); bm.from_mesh(o.data)
    out = (all(e.is_manifold for e in bm.edges) and len(bm.edges) > 0, bm.calc_volume(signed=False), len(bm.faces))
    bm.free()
    return out


def pieces(o):
    """Number of disconnected shells."""
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
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(o.data); bm.free(); o.data.update()


def solid(name, verts, faces):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)  # no non-planar quads reach a boolean
    bm.to_mesh(me); bm.free(); me.update()
    ok, volume, _ = stats(o)
    assert ok and volume > 1e-7, (name, 'not a closed solid', volume)
    return o


def lathe(name, profile, phase=0.0):
    """Solid of revolution about the vertical axis through the emit point. profile is a closed
    (radius, y) polygon; radius 0 points sit on the axis."""
    verts, rings = [], []
    for r, y in profile:
        if r == 0:
            rings.append([len(verts)] * N); verts.append((EX, y, EZ))
        else:
            rings.append(list(range(len(verts), len(verts) + N)))
            verts += [(EX + r * math.cos(phase + 2 * math.pi * i / N), y, EZ + r * math.sin(phase + 2 * math.pi * i / N)) for i in range(N)]
    faces = []
    for k in range(len(rings)):
        a, b = rings[k], rings[(k + 1) % len(rings)]
        for i in range(N):
            j = (i + 1) % N
            face = [a[i], a[j], b[j], b[i]]
            face = [v for n, v in enumerate(face) if v not in face[:n]]
            if len(face) >= 3:
                faces.append(face)
    return solid(name, verts, faces)


def conform_pod():
    """The pod with a conformal roof: sections every cfg['along'] metres along the chord (depth and
    half-width interpolated between the shape's sections), each with cfg['across'] roof vertices
    on the skin grid plus bury, over the same four lower corners as the flat pod."""
    sections = cfg['sections']; rings = [sections[0]]
    for (z0, a0, d0), (z1, a1, d1) in zip(sections, sections[1:]):
        n = max(1, math.ceil(abs(z1 - z0) / cfg['along'] - 1e-9))
        rings += [(z0 + (z1 - z0) * k / n, a0 + (a1 - a0) * k / n, d0 + (d1 - d0) * k / n) for k in range(1, n + 1)]
    m = cfg['across']; K = m + 4; verts = []
    for z, a, d in rings:
        zz = EZ + z + OZ; cx = EX + OX; lift = min(cfg['chamfer'], d * .5); b = a * cfg['flat']
        for i in range(m):
            x = cx - a + 2 * a * i / (m - 1); verts.append((x, roof(x, zz) + cfg['bury'], zz))
        for x, h in ((cx + a, lift - d), (cx + b, -d), (cx - b, -d), (cx - a, lift - d)):
            verts.append((x, under(x, zz) + h, zz))
    n = len(rings); faces = [list(range(K)), list(range(K * n - K, K * n))]
    for s in range(n - 1):
        for i in range(K):
            j = (i + 1) % K
            faces.append([K * s + i, K * s + j, K * s + K + j, K * s + K + i])
    return solid('pod', verts, faces)


def pod():
    if ROOF is not None:
        return conform_pod()
    verts = []
    for z, a, d in cfg['sections']:
        zz = EZ + z + OZ; cx = EX + OX; lift = min(cfg['chamfer'], d * .5); b = a * cfg['flat']
        for x, h in ((cx - a, cfg['bury']), (cx + a, cfg['bury']), (cx + a, lift - d), (cx + b, -d), (cx - b, -d), (cx - a, lift - d)):
            verts.append((x, under(x, zz) + h, zz))
    n = len(cfg['sections']); faces = [list(range(6)), list(range(6 * n - 6, 6 * n))]
    for s in range(n - 1):
        for i in range(6):
            j = (i + 1) % 6
            faces.append([6 * s + i, 6 * s + j, 6 * s + 6 + j, 6 * s + 6 + i])
    return solid('pod', verts, faces)


def box(name, lo, hi):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    return solid(name, verts, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]])


def boolean(target, cutter, operation):
    before = stats(target)
    mod = target.modifiers.new(cutter.name, 'BOOLEAN'); mod.operation = operation; mod.solver = 'EXACT'; mod.object = cutter
    bpy.context.view_layer.objects.active = target
    with bpy.context.temp_override(object=target, active_object=target):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    triangulate(target)
    after = stats(target)
    assert after[0], (cutter.name, 'left the solid non-manifold')
    assert abs(after[1] - before[1]) > 1e-7 and after[2] != before[2], (cutter.name, 'changed nothing', before, after)
    assert pieces(target) == 1, (cutter.name, 'left the solid in more than one piece')
    print('boolean', operation, cutter.name, 'volume %.5f -> %.5f' % (before[1], after[1]), 'faces', before[2], '->', after[2])
    bpy.data.objects.remove(cutter)


bpy.ops.wm.read_factory_settings(use_empty=True)
bell = cfg['bell']; bore = cfg['bore']; groove = cfg['groove']
body = pod()
boolean(body, lathe('bell', [(0, bell['top']), (bell['rTop'], bell['top']), (bell['rLip'], bell['lip']), (0, bell['lip'])]), 'UNION')
# The bore cutter runs past the lip so the mouth is an open recess, not a coplanar cap.
slope = (bore['rMouth'] - bore['rRoof']) / (bore['roof'] - bell['lip'])
boolean(body, lathe('bore', [(0, bore['roof']), (bore['rRoof'], bore['roof']), (bore['rMouth'] + slope * .03, bell['lip'] - .03), (0, bell['lip'] - .03)]), 'DIFFERENCE')
boolean(body, lathe('groove', [(groove['rIn'], groove['y0']), (groove['rOut'], groove['y0']), (groove['rOut'], groove['y1']), (groove['rIn'], groove['y1'])]), 'DIFFERENCE')
vent = cfg['vent']
for side in (-1, 1):
    for i, z in enumerate(vent['z']):
        zz = EZ + z + OZ; a = vent['halfWidth']; yc = under(EX + OX + side * a, zz) - vent['drop']
        x0, x1 = sorted((EX + OX + side * (a - vent['depth']), EX + OX + side * (a + .05)))
        boolean(body, box('vent%d%d' % (side + 1, i), (x0, yc - vent['height'] / 2, zz - vent['length'] / 2), (x1, yc + vent['height'] / 2, zz + vent['length'] / 2)), 'DIFFERENCE')

# The booleans leave fans of coplanar slivers: merge each flat region and split it again cleanly.
bm = bmesh.new(); bm.from_mesh(body.data); count = len(bm.faces)
bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(.5), verts=bm.verts, edges=bm.edges)
bmesh.ops.triangulate(bm, faces=bm.faces, quad_method='BEAUTY', ngon_method='BEAUTY')
bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)  # collinear leftovers
bmesh.ops.triangulate(bm, faces=bm.faces)
assert min(f.calc_area() for f in bm.faces) > 1e-8, 'zero-area triangle left in the solid'
bm.to_mesh(body.data); bm.free(); body.data.update()
ok, volume, faces = stats(body); assert ok, 'cleanup left the solid non-manifold'
print('nacelle jet cleanup: faces %d -> %d, volume %.5f' % (count, faces, volume))
# Faces wholly inside the wing are never seen; they only existed to keep the booleans closed.
bm = bmesh.new(); bm.from_mesh(body.data)
buried = [f for f in bm.faces if all(v.co.y > top(v.co.x, v.co.z) + cfg['bury'] * .5 for v in f.verts)] if cfg.get('dropBuried', True) else []
bmesh.ops.delete(bm, geom=buried, context='FACES')
bm.to_mesh(body.data); bm.free(); body.data.update()

me = body.data
me.polygons.foreach_set('use_smooth', [True] * len(me.polygons))
me.set_sharp_from_angle(angle=math.radians(cfg['smoothAngle']))
me.uv_layers.new(name='uv')
bpy.context.view_layer.objects.active = body; body.select_set(True)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
# Fitted pods sit on tilted seats: a wide projection group there leans far enough to lay the
# throat disc over the lip ring in the atlas (ring colour in the bore), so they unwrap in narrow groups.
bpy.ops.uv.smart_project(angle_limit=math.radians(15 if cfg.get('auto') else 50), island_margin=0.02)
bpy.ops.object.mode_set(mode='OBJECT')
me = body.data
assert all(len(p.vertices) == 3 for p in me.polygons)
corner = np.array([me.vertices[l.vertex_index].co[:] for l in me.loops], 'f8')
normal = np.array([n.vector[:] for n in me.corner_normals], 'f8')
uv = np.array([d.uv[:] for d in me.uv_layers.active.data], 'f8')
tris = np.array([list(p.loop_indices) for p in me.polygons], 'i4')
np.savez(args[1], positions=corner, normals=normal, uvs=uv, tris=tris)
print('nacelle jet solid: %d triangles, %d buried faces dropped' % (len(tris), len(buried)))
