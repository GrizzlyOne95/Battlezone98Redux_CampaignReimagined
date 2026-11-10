"""Blender background renderer for Tools/Build-NacelleJets.py review images.

    blender -b --python Tools/nacellejet_render.py -- scene.json

Draws the arrays the build tool hands over (unit mesh with its diffuse texture, the thruster
housings with their generated maps), a magenta dot at each engine flame emit point and an
illustrative flame cone. Offline studies, never described as native captures.
"""
import json, math, sys
from pathlib import Path
import bpy, bmesh
import numpy as np
from mathutils import Vector

scene_file = json.loads(Path(sys.argv[sys.argv.index('--') + 1]).read_text())
OUT = Path(scene_file['out'])


def xyz(v):
    """Ogre (Y up) to Blender (Z up)."""
    return Vector((v[0], -v[2], v[1]))


def principled(name, colour=(.5, .5, .5), roughness=.6, emission=None, alpha=1.):
    m = bpy.data.materials.new(name); m.use_nodes = True; b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*colour, 1); b.inputs['Roughness'].default_value = roughness
    if emission:
        b.inputs['Emission Color'].default_value = (*emission[:3], 1); b.inputs['Emission Strength'].default_value = emission[3]
    if alpha < 1:
        b.inputs['Alpha'].default_value = alpha; m.surface_render_method = 'BLENDED'
    return m


def textured(name, diffuse, emissive=None, normal=None):
    m = principled(name); tree = m.node_tree; b = tree.nodes['Principled BSDF']
    def image(path, data=False):
        node = tree.nodes.new('ShaderNodeTexImage'); node.image = bpy.data.images.load(path)
        if data:
            node.image.colorspace_settings.name = 'Non-Color'
        return node
    tree.links.new(image(diffuse).outputs['Color'], b.inputs['Base Color'])
    if emissive:
        tree.links.new(image(emissive).outputs['Color'], b.inputs['Emission Color']); b.inputs['Emission Strength'].default_value = 2.5
    if normal:
        # The maps use +v-down green (the game shader's binormal); Blender wants +v-up.
        split = tree.nodes.new('ShaderNodeSeparateColor'); join = tree.nodes.new('ShaderNodeCombineColor'); flip = tree.nodes.new('ShaderNodeMath')
        flip.operation = 'SUBTRACT'; flip.inputs[0].default_value = 1; bump = tree.nodes.new('ShaderNodeNormalMap')
        tree.links.new(image(normal, True).outputs['Color'], split.inputs['Color']); tree.links.new(split.outputs['Green'], flip.inputs[1])
        tree.links.new(split.outputs['Red'], join.inputs['Red']); tree.links.new(flip.outputs['Value'], join.inputs['Green']); tree.links.new(split.outputs['Blue'], join.inputs['Blue'])
        tree.links.new(join.outputs['Color'], bump.inputs['Color']); tree.links.new(bump.outputs['Normal'], b.inputs['Normal'])
    return m


def add_mesh(name, positions, tris, uvs=None, smooth=0):
    me = bpy.data.meshes.new(name); me.from_pydata([xyz(p) for p in positions], [], [tuple(int(i) for i in t) for t in tris]); me.update()
    if uvs is not None:
        layer = me.uv_layers.new(name='uv')
        for loop in me.loops:
            layer.data[loop.index].uv = (uvs[loop.vertex_index][0], 1 - uvs[loop.vertex_index][1])
    if smooth:
        # Game vertices are split along UV seams; weld them so only real creases shade hard.
        bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5); bm.to_mesh(me); bm.free()
        me.polygons.foreach_set('use_smooth', [True] * len(me.polygons)); me.set_sharp_from_angle(angle=math.radians(smooth))
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    return o


def cone(name, top, axis, radius, length, tip, material):
    """Flame stand-in: starts at the emit point and runs along the flame direction (mesh space)."""
    top = np.array(top, float); axis = np.array(axis, float) / np.linalg.norm(axis)
    u = np.cross(axis, (0, 0, 1) if abs(axis[2]) < .9 else (1, 0, 0)); u /= np.linalg.norm(u); v = np.cross(axis, u)
    ring = [tuple(top + axis * y + u * r * math.cos(a) + v * r * math.sin(a)) for y, r in ((0, radius), (length, tip)) for a in np.linspace(0, 2 * math.pi, 24, endpoint=False)]
    faces = [(i, (i + 1) % 24, 24 + (i + 1) % 24, 24 + i) for i in range(24)]
    o = add_mesh(name, ring, faces); o.data.materials.append(material)
    return o


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; sc.render.engine = 'BLENDER_EEVEE' if bpy.app.version >= (5, 0, 0) else 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x, sc.render.resolution_y = scene_file['size']; sc.render.image_settings.file_format = 'PNG'
sc.world = bpy.data.worlds.new('Studio'); sc.world.use_nodes = True
sc.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.36, .39, .43, 1); sc.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.1
sc.view_settings.view_transform = 'Standard'

clay_hull = principled('Clay hull', (.3, .32, .35)); clay = principled('Clay housing', (.78, .74, .66), .5); wire = principled('Wire', (.02, .02, .02))
housing, hulls = [], []
for i, part in enumerate(scene_file['parts']):
    data = np.load(part['mesh'])
    o = add_mesh('part%d' % i, data["positions"], data["tris"], data["uvs"], 35 if part["housing"] else 40)
    o.data.materials.append(textured('part%d' % i, part['diffuse'], part.get('emissive'), part.get('normal')) if part['diffuse'] else principled('part%d' % i, (.2, .22, .24)))
    o.data.materials.append(clay if part['housing'] else clay_hull)
    (housing if part['housing'] else hulls).append(o)
    if part['housing']:
        cage = add_mesh('wire%d' % i, data['positions'], data['tris']); cage.data.materials.append(wire)
        mod = cage.modifiers.new('wire', 'WIREFRAME'); mod.thickness = .0035; mod.use_replace = True; mod.use_even_offset = False; housing.append(cage)
dot = principled('Emit point', (1, 0, 1), emission=(1, 0, 1, 6)); flame = principled('Flame', (1, .45, .08), emission=(1, .4, .06, 4), alpha=.45)
core = principled('Flame axis', (1, .9, .5), emission=(1, .85, .4, 8))
markers, flames = [], []
for e, axis in zip(scene_file['emit'], scene_file.get('flameDir') or [(0, -1, 0)] * len(scene_file['emit'])):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=.022, location=xyz(e)); bpy.context.object.data.materials.append(dot); markers.append(bpy.context.object)
    f = scene_file['flame']
    flames.append(cone('flame', e, axis, f['halfWidth'], f['length'], .03, flame)); flames.append(cone('axis', e, axis, .008, f['length'], .008, core))
for n, mark in enumerate(scene_file.get('marks', [])):  # reference points: stock emit points, existing ports
    bpy.ops.mesh.primitive_uv_sphere_add(radius=mark['radius'], location=xyz(mark['at']))
    bpy.context.object.data.materials.append(principled('Mark %d' % n, mark['colour'], emission=(*mark['colour'], 6))); markers.append(bpy.context.object)
sun = bpy.data.objects.new('Key', bpy.data.lights.new('Key', 'SUN')); sun.data.energy = 3.2; sun.data.angle = math.radians(25); bpy.context.collection.objects.link(sun)
fill = bpy.data.objects.new('Fill', bpy.data.lights.new('Fill', 'SUN')); fill.data.energy = 1.1; fill.data.angle = math.radians(60); bpy.context.collection.objects.link(fill)
camera = bpy.data.objects.new('Review camera', bpy.data.cameras.new('Review camera')); bpy.context.collection.objects.link(camera); sc.camera = camera
camera.data.clip_start = .02; camera.data.clip_end = 200

for view in scene_file['views']:
    eye, target = xyz(view['eye']), xyz(view['target']); aim = (target - eye).normalized()
    camera.location = eye; camera.rotation_euler = aim.to_track_quat('-Z', 'Y').to_euler()
    if 'ortho' in view:
        camera.data.type = 'ORTHO'; camera.data.ortho_scale = view['ortho']
    else:
        camera.data.type = 'PERSP'; camera.data.sensor_fit = 'HORIZONTAL'; camera.data.angle = math.radians(view['fov'])
    # Key light from beside the camera so undersides read; fill from the far side.
    right = aim.cross(Vector((0, 0, 1))); right = right.normalized() if right.length > 1e-6 else Vector((1, 0, 0))
    sun.rotation_euler = (-(aim + right * .45 + Vector((0, 0, -.35)))).to_track_quat('Z', 'Y').to_euler()
    fill.rotation_euler = (-(aim - right * .9 + Vector((0, 0, .5)))).to_track_quat('Z', 'Y').to_euler()
    is_clay = bool(view.get('clay'))
    for o in housing:
        o.hide_render = not view['housing'] or (o.name.startswith('wire') and not is_clay)
    for o in housing + hulls:
        if not o.name.startswith('wire'):
            for poly in o.data.polygons:
                poly.material_index = int(is_clay)
    for o in markers:
        o.hide_render = not view['marker']; o.scale = (view.get('markerScale', 1.),) * 3
    for o in flames:
        o.hide_render = not view['flame']
    sc.render.filepath = str(OUT / (view['file'] + '.png')); bpy.ops.render.render(write_still=True)
