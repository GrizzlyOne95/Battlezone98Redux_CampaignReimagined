"""Read-only inspection of installed CCA geometry/UVs; private renders only.

Run with Blender --python ... -- --install <game> --output <private folder>.
Stock assets are never copied into the authored fleet or repository.
"""
import argparse
from pathlib import Path
import sys
import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).parent))
from ogrebin import Mesh,Reader,chunks,_read_geometry,_attribute


def main():
    p=argparse.ArgumentParser();p.add_argument('--install',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    a.output.mkdir(parents=True,exist_ok=True)
    for asset in ('svapc','svtank','svrecy'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        m=Mesh(a.install/'BZ_ASSETS/common/models'/(asset+'.mesh'))
        for sm in m.submeshes:
            # The main external material; cockpit interiors are unnecessary here.
            if sm['material']!=asset+'00':continue
            g=m.shared
            if not sm['shared']:
                cs,ce=sm['chunk'];r=Reader(m.data,cs+6,ce);r.s();r.b();n=r.u32();wide=r.b();r.p+=n*(4 if wide else 2)
                for cid,s,e in chunks(m.data,r.p,ce):
                    if cid==0x5000:g=_read_geometry(m.data,s,e)
            pos=sm['positions'];uv=_attribute(g,7);norm=_attribute(g,4)
            mesh=bpy.data.meshes.new(asset);mesh.from_pydata([(x,-z,y) for x,y,z in pos],[],sm['tris'].tolist());mesh.update()
            ob=bpy.data.objects.new(asset,mesh);bpy.context.collection.objects.link(ob)
            layer=mesh.uv_layers.new()
            for loop in mesh.loops:layer.data[loop.index].uv=(uv[loop.vertex_index][0],1-uv[loop.vertex_index][1])
            mesh.normals_split_custom_set_from_vertices([(x,-z,y) for x,y,z in norm])
            mat=bpy.data.materials.new(asset);mat.use_nodes=True;nt=mat.node_tree;bs=nt.nodes.get('Principled BSDF')
            tex=nt.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(a.output/(asset+'.png')))
            nt.links.new(tex.outputs['Color'],bs.inputs['Base Color']);bs.inputs['Roughness'].default_value=.55
            mesh.materials.append(mat)
        obs=[o for o in bpy.context.scene.objects if o.type=='MESH']
        if not obs:raise RuntimeError('No external material for '+asset)
        coords=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
        mn=Vector(tuple(min(v[i] for v in coords) for i in range(3)));mx=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
        centre=(mn+mx)/2;size=max(mx-mn)
        sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True
        sc.world=bpy.data.worlds.new('Neutral');sc.world.use_nodes=True;sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.08,.09,.11,1)
        for name,loc,power in [('Key',(-1,1,1.5),55),('Fill',(1,-1,.8),25)]:
            d=bpy.data.lights.new(name,'AREA');d.energy=power*size*size;d.size=size
            light=bpy.data.objects.new(name,d);sc.collection.objects.link(light);light.location=centre+Vector(loc)*size
            light.rotation_euler=(centre-light.location).to_track_quat('-Z','Y').to_euler()
        d=bpy.data.cameras.new('Stock inspection');d.type='ORTHO';d.ortho_scale=size*1.4
        cam=bpy.data.objects.new('Stock inspection',d);sc.collection.objects.link(cam);sc.camera=cam
        cam.location=centre+Vector((-1.7,1,.8))*size;cam.rotation_euler=(centre-cam.location).to_track_quat('-Z','Y').to_euler()
        sc.render.resolution_x=1400;sc.render.resolution_y=900;sc.render.resolution_percentage=100
        sc.render.filepath=str(a.output/(asset+'-geometry.png'));bpy.ops.render.render(write_still=True)
        print('STOCK_REFERENCE_RENDERED',asset,flush=True)


if __name__=='__main__':main()
