"""Offline preview: stock svsav beside savfury, rendered with Blender (Cycles, CPU).

python Tools/UnitsAndBuildings/Render-SavFuryPreview.py OUT.png [--blender PATH]

Exports the mesh to an .npz for Blender (the mesh is read only through the toolkit's
Ogre serializer), converts the stock DDS atlases to PNG, then runs this file's
`--in-blender` branch inside Blender.
"""
from pathlib import Path
import subprocess, sys, tempfile
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BLENDER = Path(r'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe')


def export(tmp):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import importlib.util
    from PIL import Image
    spec = importlib.util.spec_from_file_location('build_savfury', ROOT / 'Tools/UnitsAndBuildings/Build-SavFury.py')
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    mesh = mod.read_mesh((ROOT / 'Assets/ModelFixes/savfury.mesh').read_bytes())
    pos, uv, tris = mod.geometry(mesh)
    sub = mesh.submesh_list[0]
    b0 = np.frombuffer(bytes(sub.vertex_data.get_vertex_buffer(0).buffer), dtype='<f4').reshape(-1, 6)
    np.savez(tmp / 'mesh.npz', pos=pos, uv=uv, tris=tris, nrm=b0[:, 3:6].astype(np.float64))
    Image.open(mod.SRC / 'svsav_D.dds').convert('RGB').save(tmp / 'stock_d.png')
    Image.open(mod.SRC / 'svsav_E.dds').convert('RGB').save(tmp / 'stock_e.png')
    Image.open(ROOT / 'References/SavFury/savfury-diffuse.png').convert('RGB').save(tmp / 'fury_d.png')
    Image.open(ROOT / 'References/SavFury/savfury-emission.png').convert('RGB').save(tmp / 'fury_e.png')


def in_blender(tmp, out):
    import bpy, math
    from mathutils import Vector
    d = np.load(tmp / 'mesh.npz')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'; sc.cycles.samples = 48
    sc.render.resolution_x, sc.render.resolution_y = 1800, 760
    sc.render.filepath = str(out)

    def build(name, dtex, etex, offset, estrength):
        pos = d['pos']
        verts = [(x + offset, -z, y) for x, y, z in pos]
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], d['tris'].tolist())
        me.update()
        uvl = me.uv_layers.new(name='uv')
        for poly in me.polygons:
            for li, vi in zip(poly.loop_indices, poly.vertices):
                u, v = d['uv'][vi]
                uvl.data[li].uv = (u, 1 - v)
        for p in me.polygons: p.use_smooth = True
        ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob)
        mat = bpy.data.materials.new(name); mat.use_nodes = True
        nt = mat.node_tree; bsdf = nt.nodes['Principled BSDF']
        t1 = nt.nodes.new('ShaderNodeTexImage'); t1.image = bpy.data.images.load(str(tmp / dtex))
        t2 = nt.nodes.new('ShaderNodeTexImage'); t2.image = bpy.data.images.load(str(tmp / etex))
        nt.links.new(t1.outputs['Color'], bsdf.inputs['Base Color'])
        nt.links.new(t2.outputs['Color'], bsdf.inputs['Emission Color'])
        bsdf.inputs['Emission Strength'].default_value = estrength
        bsdf.inputs['Roughness'].default_value = .45
        bsdf.inputs['Metallic'].default_value = .5
        ob.data.materials.append(mat)
    build('stock', 'stock_d.png', 'stock_e.png', -15, 1.5)
    build('fury', 'fury_d.png', 'fury_e.png', 15, 2.2)
    world = bpy.data.worlds.new('w'); sc.world = world; world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.12, .13, .15, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0
    for loc, en in (((0, -40, 40), 6), ((-30, 30, 20), 2.5)):
        sun = bpy.data.lights.new('s', 'SUN'); sun.energy = en
        o = bpy.data.objects.new('s', sun); sc.collection.objects.link(o)
        o.location = loc
        o.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam = bpy.data.cameras.new('c'); cam.lens = 42
    co = bpy.data.objects.new('c', cam); sc.collection.objects.link(co); sc.camera = co
    co.location = (0, -62, 36)
    co.rotation_euler = (Vector((0, 0, 5)) - co.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    if '--in-blender' in sys.argv:
        a = sys.argv[sys.argv.index('--in-blender') + 1:]
        in_blender(Path(a[0]), Path(a[1]))
    else:
        out = Path(sys.argv[1]).resolve()
        blender = Path(sys.argv[sys.argv.index('--blender') + 1]) if '--blender' in sys.argv else BLENDER
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t); export(tmp)
            subprocess.run([str(blender), '-b', '--factory-startup', '-P', str(Path(__file__).resolve()), '--', '--in-blender', str(tmp), str(out)], check=True)
