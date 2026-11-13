"""Blender background diagnostic renderer for the exported weapon-rig assets.

Grey is fixed geometry; cyan/blue are independently animated gun pieces.
Images are offline pose/closure studies, never described as native captures.
"""
import sys as _sys; from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent))
from pathlib import Path
import argparse, importlib.util, json, math, sys
import bpy
from mathutils import Matrix, Vector, Quaternion
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'Tools'))
import weaponrigs as wr
import cockpitglass as cg
import numpy as np
from bzmodellibs import legacy, legacy_port

def xyz(v):return Vector((v[0],-v[2],v[1]))

def material(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bsdf=m.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(*color,1);bsdf.inputs['Roughness'].default_value=.7
    m.use_backface_culling=True
    return m

def scene(path,fired,world):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    mesh=wr.ogre.read_mesh(path.read_bytes());skel=wr.read_skeleton(ROOT/'Assets/Models'/mesh.skeleton)
    effects={}
    if fired:
        for a in skel.animations:
            if not a.name.startswith('cr_fire_'):continue
            for track in a.tracks:
                keys=track.keyframes
                if not keys:continue
                # Quarter-turn sample for the rotating cluster, kicked pose otherwise.
                key=keys[1] if len(keys)==5 else keys[0]
                p,q=wr.flash.bone_world(skel,track.bone)
                rot=Matrix([wr.flash._rotate(q,axis) for axis in np.eye(3)]).transposed()
                k=key.orientation;Q=Quaternion((k[3],k[0],k[1],k[2])).to_matrix()
                R=rot@Q@rot.transposed();delta=rot@Vector(key.translation)
                effects[track.bone]=(Vector(p),R,delta)
    def visible(handle):
        if not world:return True
        b=skel.bones[handle]
        while b is not None:
            if len(b.name)>3 and b.name[3]=='2':return False
            b=skel.bones[b.parent] if b.parent is not None else None
        return True
    fixed=material('Fixed hardware',(.38,.43,.49));colors=[material('Gun '+str(i),c) for i,c in enumerate([(.015,.65,.75),(.08,.28,.9),(.7,.25,.03),(.45,.08,.7)])]
    allpoints=[]
    for sub in mesh.submeshes:
        if 'glass' in sub.material.lower():continue
        g=mesh.shared_geometry if sub.uses_shared_vertices else sub.geometry;p=g.attribute(1)
        assigns=mesh.bone_assignments if sub.uses_shared_vertices else sub.bone_assignments;owners={i:b for i,b,w in assigns if w>.99}
        points=[]
        for i,v in enumerate(p):
            v=Vector(v);handle=owners.get(i)
            if handle in effects:
                pivot,R,delta=effects[handle];v=pivot+R@(v-pivot)+delta
            points.append(xyz(v))
        faces=[f for f in sub.triangles() if all(i in owners and visible(owners[i]) for i in f)]
        if not faces:continue
        data=bpy.data.meshes.new(sub.material);data.from_pydata(points,[],faces);data.update()
        obj=bpy.data.objects.new(sub.material,data);bpy.context.collection.objects.link(obj)
        obj.data.materials.append(fixed)
        for m in colors:obj.data.materials.append(m)
        for poly,f in zip(data.polygons,faces):
            name=skel.bones[owners[f[0]]].name
            if name.startswith('crgun_'):poly.material_index=1+(int(name.split('_')[1])-1)%4
        allpoints.extend(points[i] for f in faces for i in f)
    return skel,allpoints

def camera(position,target,ortho=None,basis=None):
    data=bpy.data.cameras.new('Review camera');obj=bpy.data.objects.new('Review camera',data);bpy.context.collection.objects.link(obj);obj.location=position
    if basis is None:obj.rotation_euler=(target-position).to_track_quat('-Z','Y').to_euler()
    else:obj.matrix_world=basis;obj.location=position
    if ortho:data.type='ORTHO';data.ortho_scale=ortho
    else:data.type='PERSP';data.sensor_fit='VERTICAL';data.angle=math.radians(64)
    data.clip_start=.02;data.clip_end=1000;bpy.context.scene.camera=obj

def lighting():
    sc=bpy.context.scene;sc.world.color=(.65,.65,.65)
    for pos,power,size in [((9,-12,18),1800,10),((-12,-4,12),1200,9),((0,12,15),1600,10)]:
        d=bpy.data.lights.new('Softbox','AREA');d.energy=power;d.shape='DISK';d.size=size;o=bpy.data.objects.new('Softbox',d);bpy.context.collection.objects.link(o);o.location=pos;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()

def render(model,record):
    out=ROOT/'References/WeaponRigs/review';out.mkdir(parents=True,exist_ok=True)
    worldpath=ROOT/'Assets/ModelFixes'/(model+'.mesh')
    for label,fired,view in [('rest',False,(1.2,-1.8,.85)),('firing',True,(1.2,-1.8,.85)),('rear',True,(-1.1,1.8,-.35))]:
        skel,pts=scene(worldpath,fired,True);p=np.asarray(pts);center=Vector((p.min(0)+p.max(0))/2);span=max(p.max(0)-p.min(0))
        camera(center+Vector(view)*span,center,span*1.65);lighting()
        sc=bpy.context.scene;sc.render.filepath=str(out/(model+'-'+label+'.jpg'));bpy.ops.render.render(write_still=True)
    cp=next((ROOT/k for k in record['outputs'] if k.endswith('.mesh') and Path(k).name!=model+'.mesh'),None)
    if cp:
        skel,pts=scene(cp,True,False);eye=next(b for b in skel.bones if b.name.lower().endswith('pov'));pos,q=wr.flash.bone_world(skel,eye.handle)
        R=np.asarray([wr.flash._rotate(q,a) for a in np.eye(3)]).T
        # The VDF's local POV basis is authoritative (as in tankcockpits.native_eye).
        source=legacy_port.AssetSource(folders=[ROOT/'Assets/ModelFixes',ROOT/'Assets/Models'],archives=[wr.GAME/'bzone.zfs',wr.GAME/'tro_cam.zfs'])
        raw=source(model+'.vdf');native=next(p for p in legacy.read_vdf(raw).parts if p.name==eye.name)
        mirror=np.diag([-1.,1.,1.]);local=mirror@np.asarray(native.matrix[:9]).reshape(3,3).T@mirror
        parentq=wr.flash.bone_world(skel,eye.parent)[1] if eye.parent is not None else (0,0,0,1)
        parentR=np.asarray([wr.flash._rotate(parentq,a) for a in np.eye(3)]).T;R=parentR@local
        # Preserve the actual eye. Camera looks along native +Z; source +X is screen-left.
        right=xyz(-R[:,0]);up=xyz(R[:,1]);back=xyz(-R[:,2]);M=Matrix((right,up,back)).transposed().to_4x4()
        camera(xyz(pos),Vector(),basis=M);lighting();sc=bpy.context.scene
        sc.render.filepath=str(out/(model+'-cockpit.jpg'));bpy.ops.render.render(write_still=True)
        camera(xyz(pos),Vector(),basis=M@Matrix.Rotation(math.radians(-25),4,'X'))
        sc.render.filepath=str(out/(model+'-cockpit-down.jpg'));bpy.ops.render.render(write_still=True)
        (out/(model+'-camera.json')).write_text(json.dumps({'eye':eye.name,'position':pos,'basis':R.tolist(),'vertical_fov_degrees':64,'aspect':[960,540],'source':('CR eyeoverrides position' if model in __import__('eyeoverrides').EYES else 'unchanged eye position')+'; native VDF local POV rotation'},indent=2)+'\n')

if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    p=argparse.ArgumentParser();p.add_argument('--models',nargs='*');a=p.parse_args(args)
    sc=bpy.context.scene;sc.render.engine='BLENDER_EEVEE' if bpy.app.version>=(5,0,0) else 'BLENDER_EEVEE_NEXT';sc.render.resolution_x=960;sc.render.resolution_y=540;sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='JPEG';sc.render.image_settings.quality=90;sc.render.film_transparent=False;sc.world.color=(.7,.7,.7)
    records=json.loads((ROOT/'References/WeaponRigs/build.json').read_text())
    for model,record in records.items():
        if a.models and model not in a.models:continue
        render(model,record)
