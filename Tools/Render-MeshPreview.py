"""Render shipped CR .mesh binaries side by side with their material diffuse/normal maps.

Offline texture check on the shipped mesh (not the .blend): Blender Cycles, ortho camera.
    python Tools/Render-MeshPreview.py OUT.png mesh1.mesh [mesh2.mesh ...] [--root REPO]
Blender: CR_BLENDER env var, else the default 5.2 install path. Alpha is wired only for
materials named *Branch*/*Cutout*/*Leaves*. Mirrored axes are fine for a preview.
"""
import os, sys, io, re, json, shutil, subprocess, tempfile
from pathlib import Path
import numpy as np

BLENDER = os.environ.get('CR_BLENDER') or r'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'


def materials(root):
    out = {}
    for f in (root / 'Materials').glob('*.material'):
        cur = None
        for line in f.read_text(errors='ignore').splitlines():
            m = re.match(r'\s*material\s+(\S+)', line)
            if m:
                cur = m.group(1); out.setdefault(cur, {}); continue
            m = re.match(r'\s*set_texture_alias\s+(\w+)\s+(\S+)', line)
            if m and cur:
                out[cur][m.group(1)] = m.group(2)
    return out


def export(root, meshes, tmp):
    sys.path.insert(0, str(root / 'Tools'))
    from bzmodellibs import ogremesh as om, ogremesh_serializer as oms
    from PIL import Image
    mats = materials(root)

    def values(vd, sem):
        el = vd.vertex_declaration.find_by_semantic(sem)
        vb = vd.get_vertex_buffer(el.source)
        return np.ndarray((vd.vertex_count, el.get_type_count()), '<f4', buffer=vb.buffer, offset=el.offset,
                          strides=(vb.vertex_size, 4)).astype(np.float64)

    scene = []
    texs = {}
    for k, name in enumerate(meshes):
        path = Path(name) if Path(name).is_file() else root / 'Assets/Models' / name
        mesh = oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
        for j, sub in enumerate(mesh.submesh_list):
            vd = sub.vertex_data if sub.vertex_data is not None else mesh.shared_vertex_data
            if vd.vertex_declaration.find_by_semantic(om.VES.TEXTURE_COORDINATES) is None:
                sys.exit(f'{name} submesh {j} ({sub.material_name}) has no UVs')
            pos = values(vd, om.VES.POSITION); uv = values(vd, om.VES.TEXTURE_COORDINATES)[:, :2]
            tris = np.asarray(sub.get_index_array()).astype(np.int64).reshape(-1, 3)
            key = f'm{k}_{j}'
            np.savez(tmp / (key + '.npz'), pos=pos, uv=uv, tris=tris)
            alias = mats.get(sub.material_name, {})
            entry = {'key': key, 'mesh': k, 'mat': sub.material_name}
            for slot in ('DiffuseMap', 'NormalMap'):
                t = alias.get(slot)
                if t and (root / 'Assets/Textures' / t).exists():
                    if t not in texs:
                        texs[t] = str(tmp / (t + '.png'))
                        Image.open(root / 'Assets/Textures' / t).convert('RGBA').save(texs[t])
                    entry[slot] = texs[t]
            scene.append(entry)
            print(name, sub.material_name, len(tris), entry.get('DiffuseMap'))
    (tmp / 'scene.json').write_text(json.dumps({'parts': scene, 'n': len(meshes)}))


def in_blender(tmp, out):
    import bpy, math
    from mathutils import Vector
    sc_data = json.loads((tmp / 'scene.json').read_text())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 24; sc.cycles.device = 'CPU'
    sc.render.resolution_x = 640 * sc_data['n']; sc.render.resolution_y = 640
    world = bpy.data.worlds.new('w'); sc.world = world; world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.45, .5, .55, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .8
    objs = {}
    imgcache = {}

    def img(p):
        if p not in imgcache:
            imgcache[p] = bpy.data.images.load(p)
        return imgcache[p]

    for part in sc_data['parts']:
        d = np.load(tmp / (part['key'] + '.npz'))
        pos = d['pos'][:, [0, 2, 1]] * [1, 1, 1]  # Ogre Y-up -> Blender Z-up (mirror ok for preview)
        me = bpy.data.meshes.new(part['key'])
        me.from_pydata(pos.tolist(), [], d['tris'][:, ::-1].tolist())
        uvl = me.uv_layers.new()
        uv = d['uv'][d['tris'][:, ::-1].reshape(-1)]
        uvl.data.foreach_set('uv', np.c_[uv[:, 0], 1 - uv[:, 1]].reshape(-1))
        me.shade_smooth() if hasattr(me, 'shade_smooth') else None
        ob = bpy.data.objects.new(part['key'], me); sc.collection.objects.link(ob)
        objs.setdefault(part['mesh'], []).append(ob)
        mat = bpy.data.materials.new(part['key']); mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        bsdf.inputs['Roughness'].default_value = .85
        if 'DiffuseMap' in part:
            t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(part['DiffuseMap'])
            nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
            if 'Branch' in part['mat'] or 'Cutout' in part['mat'] or 'Leaves' in part['mat']:
                nt.links.new(t.outputs['Alpha'], bsdf.inputs['Alpha'])
        if 'NormalMap' in part:
            t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(part['NormalMap']); t.image.colorspace_settings.name = 'Non-Color'
            sep = nt.nodes.new('ShaderNodeSeparateColor'); comb = nt.nodes.new('ShaderNodeCombineColor')
            inv = nt.nodes.new('ShaderNodeMath'); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1
            nt.links.new(t.outputs['Color'], sep.inputs[0])
            nt.links.new(sep.outputs[0], comb.inputs[0]); nt.links.new(sep.outputs[1], inv.inputs[1])
            nt.links.new(inv.outputs[0], comb.inputs[1]); nt.links.new(sep.outputs[2], comb.inputs[2])
            nm = nt.nodes.new('ShaderNodeNormalMap'); nm.uv_map = uvl.name
            nt.links.new(comb.outputs[0], nm.inputs['Color']); nt.links.new(nm.outputs[0], bsdf.inputs['Normal'])
        me.materials.append(mat)
    # lay meshes out in a row, each scaled to unit height
    x = 0.0
    for k in sorted(objs):
        lo = np.min([np.min([o.matrix_world @ Vector(c) for c in o.bound_box], axis=0) for o in objs[k]], axis=0)
        hi = np.max([np.max([o.matrix_world @ Vector(c) for c in o.bound_box], axis=0) for o in objs[k]], axis=0)
        s = 2.0 / max(hi - lo)
        for o in objs[k]:
            o.scale = (s, s, s)
            o.location = (x - (lo[0] + hi[0]) / 2 * s, -(lo[1] + hi[1]) / 2 * s, -lo[2] * s)
        x += 2.6
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 2.6 * len(objs)
    cx = (x - 2.6) / 2
    cam.location = (cx, -12, 3.2); cam.rotation_euler = (math.radians(78), 0, 0)
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
    sun.data.energy = 3.5; sun.rotation_euler = (math.radians(50), math.radians(20), math.radians(-35))
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    if '--in-blender' in sys.argv:
        a = sys.argv[sys.argv.index('--') + 1:]
        in_blender(Path(a[0]), a[1])
    else:
        import argparse
        p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
        p.add_argument('out'); p.add_argument('meshes', nargs='+')
        p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
        a = p.parse_args()
        out = str(Path(a.out).resolve())
        if not Path(BLENDER).is_file():
            sys.exit(f'Blender not found at {BLENDER}; set CR_BLENDER')
        tmp = Path(tempfile.mkdtemp(prefix='cr_meshprev_'))
        try:
            export(a.root, a.meshes, tmp)
            r = subprocess.run([BLENDER, '-b', '--factory-startup', '--python', __file__, '--', str(tmp), out, '--in-blender'],
                               capture_output=True, text=True, errors='replace', timeout=900)
            if r.returncode or not Path(out).exists():
                print(r.stdout[-3000:], r.stderr[-3000:])
                sys.exit(1)
            print('done', out)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
