"""Author the NSDF carrier from the owner-supplied side concept.

Blender coordinates: X starboard, Y forward, Z up. Export: Y up, nose -Z.
Run through Build-NSDFCarrier.py. Source artwork stays private and unchanged.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import sys
import random
import hashlib
import io
import numpy as np
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import geo, geo_serializer
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'References/NSDFCarrier'
TEXTURES=SOURCE/'Textures'
MODEL=ROOT/'Assets/ModelFixes'
ASSET='crncarr'
ATLAS=[('d',2048,'DIFFUSE'),('e',2048,'EMIT'),('s',512,'EMIT')]
RUNTIME_SCALE=.4  # 240m NSDF span, consistent with the owner's CCA/APC scale reference.
EXPORT_TANGENTS=False
TAU=math.tau
parts=[]
materials={}
coarse=[]

# Side-image survey, in source pixels. Bow is at u=0. There is no authored
# scale or plan view in the image; 600m length and the beam are staging choices.
SCALE=600/1024
STATIONS=[(0,.6,147,150),(50,25,128,234),(172,53,85,239),
    (426,53,85,239),(454,42,143,246),(550,43,143,253),
    (700,47,143,258),(750,57,96,269),(810,68,53,273),
    (900,73,67,285),(970,65,98,291),(1012,44,142,280),(1024,18,183,261)]
REFERENCE=Path(r'C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Archives\Images\BZ1Concept\Nsdf_carrier.webp')
CCA_REFERENCE=REFERENCE.with_name('CCAfleet3.webp')
REFERENCE_SHA256='9b94132c76ef2948a35ade5edcc501c4be12351e5524391a2ebab834f125645f'
CCA_SHA256='4b1e7208c649755ab88f1570a7a027a5673dbe5a15506006e133b3c2063ad71f'

def yz(u,v):return (512-u)*SCALE,(147-v)*SCALE

def station(u):
    for a,b in zip(STATIONS,STATIONS[1:]):
        if a[0]<=u<=b[0]:
            t=(u-a[0])/(b[0]-a[0])
            w,top,bottom=[a[i]*(1-t)+b[i]*t for i in (1,2,3)]
            return w,(147-top)*SCALE,(147-bottom)*SCALE
    raise ValueError(u)

def side_point(u,v,side,lift=.13):
    w,top,bottom=station(u);y,z=yz(u,v)
    bevel=min(12,(top-bottom)*.23)
    taper=1
    if z>top-bevel:taper=1-.28*(z-(top-bevel))/bevel
    if z<bottom+bevel:taper=1-.28*((bottom+bevel)-z)/bevel
    blend=max(0,min(1,(u-700)/80))
    q=(z-(top+bottom)/2)/((top-bottom)/2)
    round_x=w*math.sqrt(max(0,1-q*q))
    return(side*((w*max(.65,taper))*(1-blend)+round_x*blend+lift),y,z)

def side_card(name,points,side,mat,lift=.18):
    # Viewed from starboard (+X), source U increases aft (-Y), V down (-Z).
    vertices=[side_point(u,v,side,lift) for u,v in points]
    face=tuple(range(len(vertices)))
    if side<0:face=tuple(reversed(face))
    return mesh(name,vertices,[face],mat)

def side_rect(name,u,v,width,height,side,mat,lift=.18):
    if u>700:
        # A four-corner card chords through the rounded afterbody. Subdivide
        # service covers so they stay on the skin rather than clipping into it.
        nu=max(1,math.ceil(width/6));nv=max(1,math.ceil(height/3))
        verts=[side_point(u-width/2+width*i/nu,v-height/2+height*j/nv,side,lift+.55)
               for j in range(nv+1) for i in range(nu+1)]
        faces=[]
        for j in range(nv):
            for i in range(nu):
                a=j*(nu+1)+i;f=(a,a+1,a+nu+2,a+nu+1)
                faces.append(f if side>0 else tuple(reversed(f)))
        return mesh(name,verts,faces,mat)
    return side_card(name,[(u-width/2,v-height/2),(u+width/2,v-height/2),
        (u+width/2,v+height/2),(u-width/2,v+height/2)],side,mat,lift)

def remember(ob):
    # Preserve coarse closed solids before joining the visual mesh. Tiny lamps,
    # seams and service fittings should not consume the native GEO table.
    bpy.context.view_layer.update()
    ob.data.calc_loop_triangles()
    coarse.append(([tuple(ob.matrix_world@v.co) for v in ob.data.vertices],
                   [tuple(t.vertices) for t in ob.data.loop_triangles]))
    return ob

def native_proxy():
    verts=[];faces=[]
    for vv,ff in coarse:
        n=len(verts);verts.extend(vv);faces.extend(tuple(i+n for i in f) for f in ff)
    me=bpy.data.meshes.new('Coarse native carrier hull');me.from_pydata(verts,[],faces);me.update()
    me.uv_layers.new()
    ob=bpy.data.objects.new('Native carrier proxy',me);bpy.context.collection.objects.link(ob)
    return ob

def loft(name,stations,mat):
    verts=[]
    for u,w,t,b in stations:
        y,z0=yz(u,b);_,z1=yz(u,t);c=min(12,(z1-z0)*.23)
        polygon=[(w*.72,z1),(w,z1-c),(w,z0+c),(w*.72,z0),
                 (-w*.72,z0),(-w,z0+c),(-w,z1-c),(-w*.72,z1)]
        blend=max(0,min(1,(u-700)/80))
        for i in range(32):
            a,b=polygon[i//4],polygon[(i//4+1)%8];t=(i%4)/4
            x=a[0]*(1-t)+b[0]*t;z=a[1]*(1-t)+b[1]*t
            angle=math.pi/4-i*TAU/32
            ex=w*math.cos(angle);ez=(z0+z1)/2+(z1-z0)/2*math.sin(angle)
            verts.append((x*(1-blend)+ex*blend,y,z*(1-blend)+ez*blend))
    faces=[]
    for j in range(len(stations)-1):
        for i in range(32):
            a=j*32+i;b=j*32+(i+1)%32
            faces.append((a,a+32,b+32,b))
    faces += [tuple(range(31,-1,-1)),tuple((len(stations)-1)*32+i for i in range(32))]
    ob=mesh(name,verts,faces,mat)
    # This is one closed connected solid, so an outward recalc is unambiguous.
    import bmesh
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    return ob

def beam(name,start,end,width,depth,mat):
    mid=(Vector(start)+Vector(end))*.5;direction=Vector(end)-Vector(start)
    ob=box(name,mid,(width,depth,direction.length),mat,.35)
    ob.rotation_euler=direction.to_track_quat('Z','Y').to_euler()
    return ob

def carrier():
    material('Main hull',(.12,.145,.16),.6,.48)
    material('Dark hull',(.038,.047,.055),.45,.58)
    material('Armour grey',(.36,.39,.39),.5,.43)
    material('Bow ivory',(.68,.68,.61),.42,.44)
    material('Rib light',(.49,.51,.49),.58,.38)
    material('Rib shadow',(.10,.12,.13),.5,.5)
    material('Panel alternate',(.21,.24,.25),.55,.5)
    material('Panel seam',(.027,.034,.039),.4,.6)
    material('Window dark',(.032,.036,.025),.1,.58)
    material('Warm windows',(.62,.68,.12),.1,.35,(.85,.95,.18))
    material('Bright windows',(.9,.91,.32),.1,.3,(1,1,.35))
    material('Engine hot',(.3,.48,.7),.1,.4,(.36,.6,1))
    material('Bay interior',(.012,.019,.025),.25,.65)
    material('Status red',(.4,.015,.008),.1,.4,(.8,.025,.009))
    hull=remember(loft('Surveyed carrier hull',STATIONS,'Main hull'))
    # Pale triangular foredeck, lower black chin and broad forward side plates.
    for side in (-1,1):
        side_card('Large ivory bow wedge',[(2,147),(172,86),(242,130),(45,145)],side,'Bow ivory',.28)
        side_card('Bow lower dark chin',[(5,154),(220,157),(238,236),(50,232)],side,'Dark hull',.23)
        side_card('Forward lower dark plating',[(225,172),(426,172),(426,238),(238,238)],side,'Dark hull',.24)
        side_rect('Forward upper armour bed',306,114,238,49,side,'Armour grey',.22)
        for u in (244,300,357,415):
            y,z=yz(u,133)
            remember(box('Forward structural rib',(side*53.5,y,z-14),(4.2,9,79),'Rib shadow',.4))
            box('Forward hanging armour plate',(side*56,y,z+2),(2.8,17,51),'Armour grey',.32)
            box('Armour plate top rail',(side*57.7,y,33),(1,16,.65),'Rib light',.12)
        # Deliberately sparse and irregular windows; not a uniform passenger-liner grid.
        rng=random.Random(1998)
        regions=[(24,424,153,227,230),(460,548,157,238,95),(758,930,108,145,95)]
        for u0,u1,v0,v1,count in regions:
            for j in range(count):
                u=rng.uniform(u0,u1);v=rng.uniform(v0,v1)
                w,top,bottom=station(u);_,zz=yz(u,v)
                if zz<bottom+7 or zz>top-5:continue
                width=rng.choice((.8,1.1,1.8,3.2,5.0));height=rng.uniform(.35,.75)
                side_rect('Recessed window surround',u,v,width+1.2,height+1.0,side,'Window dark',.29)
                side_rect('Yellow window light',u,v,width,height,side,
                          'Bright windows' if j%9==0 else 'Warm windows',.34)
        for u,v,width,height in [(37,163,67,2.4),(81,179,21,1.3),(127,195,21,1.0),
                                  (196,137,15,1.2),(505,176,30,1.3),(825,126,25,1.2)]:
            side_rect('Long yellow navigation slit',u,v,width,height,side,'Bright windows',.38)
        # Panel lines and service covers conform to the side's bevelled surface.
        for row,(u0,u1,v0,v1) in enumerate([(76,420,144,232),(180,420,90,145),
                                          (460,550,147,246),(752,975,110,260)]):
            for j in range(16):
                u=u0+(u1-u0)*(j+.5)/16
                for k in range(3):
                    v=v0+(v1-v0)*(k+.5)/3
                    w,top,bottom=station(u);_,zz=yz(u,v)
                    height=(v1-v0)/3-3;width=(u1-u0)/16-2
                    if zz-height*SCALE/2<bottom+8 or zz+height*SCALE/2>top-5:continue
                    side_rect('Recessed hull panel',u,v,width,height,side,'Panel seam',.15)
                    side_rect('Hull service plate',u,v,width-.7,height-.7,side,
                              'Panel alternate' if (j+2*k+row)%7==0 else 'Main hull',.19)
        # The high afterbody's layered shoulder is visible behind the rear frame.
        for j in range(10):
            side_rect('Aft shoulder service panel',786+j*15,108+(j%3)*5,12,18,side,
                      'Panel alternate' if j%3==0 else 'Main hull',.38)
    # Low central waist leaves the large rectangular air gap beneath the arch.
    for u in (562,676):
        y,_=yz(u,0)
        for side in (-1,1):
            remember(box('Tall central frame upright',(side*50,y,-1),(10,10,137),'Rib light',1.7))
            box('Frame dark outer channel',(side*55.2,y,-1),(.55,4.2,125),'Panel seam',.1)
        remember(box('Central frame overhead crossmember',(0,y,64),(104,10,12),'Armour grey',1.4))
        remember(box('Central frame lower crossmember',(0,y,-65),(102,10,10),'Rib shadow',1.2))
    for side in (-1,1):
        a=(*[side*49],*yz(425,85));b=(*[side*49],*yz(519,35));c=(*[side*49],*yz(560,35))
        remember(beam('Forward rising arch spar',a,b,10,9,'Rib light'))
        remember(beam('Arch forward landing',b,c,10,9,'Armour grey'))
    remember(box('Bridge lower cabin',(0,-63,-17),(96,67,68),'Main hull',1.3))
    remember(box('Dorsal bridge cap',(0,-63,61),(84,73,26),'Main hull',3))
    # Bridge windows are narrow, warm and physically small for the ship's scale.
    for side in (-1,1):
        for j in range(14):
            box('Bridge light band',(side*42.4,-96+j*5,62),(.12,2.2,.55),'Warm windows',0)
        for j in range(16):
            for k in range(4):
                if (j+3*k)%4==0:continue
                box('Central cabin scattered windows',(side*48.3,-92+j*3.6,10-k*12),
                    (.12,1.0 if j%3 else 2.8,.4),'Warm windows',0)
    # The artwork crops the top fitting and gives no plan or stern view.
    # A low radar fairing and eight recessed engines are inferred details.
    remember(box('Radar pedestal',(0,-52,82),(15,15,14),'Rib shadow',1.5))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=12,radius=15,location=(0,-52,92))
    ob=bpy.context.object;ob.name='Low radar radome';ob.scale=(1,1.3,.65)
    ob.data.materials.append(materials['Armour grey']);parts.append(ob);remember(ob)
    # Vent ribs and access plates across the broad upper foredeck.
    for side in (-1,1):
        for j in range(12):
            y=190-j*11
            box('Foredeck panel gasket',(side*25,y,36.5),(27,9,.2),'Panel seam',.1)
            box('Foredeck armour panel',(side*25,y,36.7),(26.5,8.5,.25),'Armour grey',.1)
        for y in (75,160):
            for k in range(6):
                box('Top heat-exchanger grille',(side*26,y+k*1.2,37.1),(24,.65,.18),'Panel seam',0)
    # Rear drive bank. Bells are built along local Z then rotated toward aft (-Y).
    remember(box('Stern drive mounting structure',(0,-297,-27),(70,3,74),'Dark hull',2))
    engines=[]
    for x in (-20,20):
        for height in (-55,-38,-21,-4):
            if height>5 and abs(x)>25:continue
            start=len(parts)
            bell=lathe('Recessed aft engine bell',[(0,7.1),(-3.0,6.7),(-4.0,5.2),(-6,3.4)],
                       'Dark hull',24,caps=False)
            for ob in parts[start:]:
                ob.rotation_euler.x=math.pi/2;ob.location=(x,-307,height)
            bpy.ops.mesh.primitive_circle_add(vertices=24,radius=3.35,fill_type='NGON',location=(x,-301.0,height))
            ob=bpy.context.object;ob.name='Aft engine emissive throat';ob.rotation_euler.x=math.pi/2
            ob.data.materials.append(materials['Engine hot']);parts.append(ob)
            engines.append([x,height,307])
    return engines


def assemble():
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:ob.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join();ob=bpy.context.object;ob.name='NSDF carrier — concept study'
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    assert ob.location.length<.00001
    # Closed hulls and primitive boxes already have outward normals. Do not
    # recalc disconnected surface cards after joining them.
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.0025)
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob


def inspection():
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=32
    sc.world=bpy.data.worlds.new('Inspection space');sc.world.use_nodes=True
    bg=sc.world.node_tree.nodes.get('Background');bg.inputs[0].default_value=(.045,.055,.075,1);bg.inputs[1].default_value=.35
    for label,loc,power,size,color in [
        ('Key',(-250,400,650),18000000,600,(1,.94,.82)),
        ('Fill',(-600,-150,100),1800000,550,(.7,.82,1)),
        ('Rim',(400,-300,300),15000000,500,(.65,.8,1))]:
        d=bpy.data.lights.new(label,'AREA');d.energy=power*RUNTIME_SCALE**2;d.size=size*RUNTIME_SCALE;d.color=color
        o=bpy.data.objects.new(label,d);sc.collection.objects.link(o);o.location=Vector(loc)*RUNTIME_SCALE
        o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
    d=bpy.data.cameras.new('Concept side');d.type='ORTHO';d.ortho_scale=670*RUNTIME_SCALE;d.clip_end=6000
    cam=bpy.data.objects.new('Concept side',d);sc.collection.objects.link(cam);sc.camera=cam
    sc.render.resolution_x=1600;sc.render.resolution_y=640;sc.render.resolution_percentage=100
    cam.location=(-1000*RUNTIME_SCALE,0,0);cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
    sc.render.filepath=str(SOURCE/'carrier-side.png');bpy.ops.render.render(write_still=True)
    sc.render.resolution_y=900;d.ortho_scale=730*RUNTIME_SCALE
    for label,loc in [('bow',(-780,500,290)),('aft',(-650,-600,250))]:
        cam.location=Vector(loc)*RUNTIME_SCALE;cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
        sc.render.filepath=str(SOURCE/('carrier-'+label+'.png'));bpy.ops.render.render(write_still=True)
    cam.name='Carrier three-quarter inspection'


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--render',action='store_true')
    args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    for path in (SOURCE,TEXTURES,MODEL):path.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    # The geometric survey is self-contained. Original private artwork is not
    # needed on another machine, but reject a changed local reference silently
    # masquerading as the surveyed one.
    if REFERENCE.is_file():
        assert hashlib.sha256(REFERENCE.read_bytes()).hexdigest()==REFERENCE_SHA256,'concept differs from the recorded survey'
    engines=carrier();ob=assemble()
    for vertex in ob.data.vertices:vertex.co*=RUNTIME_SCALE
    for i,(vertices,faces) in enumerate(coarse):
        coarse[i]=([tuple(c*RUNTIME_SCALE for c in p) for p in vertices],faces)
    engines=[[c*RUNTIME_SCALE for c in p] for p in engines]
    bake(ob)
    stats=export_mesh(ob);export_native(ob,stats)
    stats.update({'role':'cinematic static fixture; no AI or production',
        'axis':'game +Z points aft; nose is -Z; Y up',
        'scale_note':'240m concept side span, depth and cropped top/rear inferred; CCA/APC comparison informed scale',
        'reference':REFERENCE.name,'reference_sha256':REFERENCE_SHA256,
        'cca_comparison':CCA_REFERENCE.name,'cca_reference_sha256':CCA_SHA256,
        'engine_exits':engines,'docking_bay':[0,-25*RUNTIME_SCALE,0],
        'runtime_scale_from_600m_survey':RUNTIME_SCALE,
        'stations_source_pixels':STATIONS})
    (SOURCE/'geometry.json').write_text(json.dumps(stats,indent=2)+'\n')
    if args.render:inspection()
    for im in bpy.data.images:
        if im.filepath and Path(im.filepath).parent==TEXTURES:im.filepath='//Textures/'+Path(im.filepath).name
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'NSDF-Carrier.blend'),compress=True)
    print('CARRIER_BUILT',json.dumps(stats),flush=True)


def material(name, color, metal=0.0, rough=.5, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    nt = mat.node_tree
    bs = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Metallic'].default_value = metal
    bs.inputs['Roughness'].default_value = rough
    if emission:
        bs.inputs['Emission Color'].default_value = (*emission, 1)
        bs.inputs['Emission Strength'].default_value = 2
    # Fine material variation is authored in object space, then baked into UVs.
    if not emission:
        coord = nt.nodes.new('ShaderNodeTexCoord')
        noise = nt.nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = 2
        noise.inputs['Detail'].default_value = 2
        streak = nt.nodes.new('ShaderNodeVectorMath');streak.operation='MULTIPLY'
        streak.inputs[1].default_value=(1,1,1)
        ramp = nt.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position = .15
        ramp.color_ramp.elements[0].color = (*(v * .82 for v in color), 1)
        ramp.color_ramp.elements[1].position = .85
        ramp.color_ramp.elements[1].color = (*color, 1)
        nt.links.new(coord.outputs['Object'], streak.inputs[0])
        nt.links.new(streak.outputs['Vector'], noise.inputs['Vector'])
        nt.links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
        nt.links.new(ramp.outputs['Color'], bs.inputs['Base Color'])
    mat['export_specular'] = .18 + metal * .48
    materials[name] = mat
    return mat

def mesh(name, verts, faces, mat, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    ob = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(ob)
    data.materials.append(materials[mat])
    for face in data.polygons:
        face.use_smooth = smooth
    parts.append(ob)
    return ob

def lathe(name, profile, mat, segments=48, center=(0, 0), caps=True):
    verts = [(center[0] + r*math.cos(TAU*i/segments),
              center[1] + r*math.sin(TAU*i/segments), z)
             for z, r in profile for i in range(segments)]
    faces = []
    for j in range(len(profile)-1):
        for i in range(segments):
            a = j*segments+i
            b = j*segments+(i+1) % segments
            faces.append((a, b, b+segments, a+segments))
    if caps:
        faces += [tuple(range(segments-1, -1, -1)),
                  tuple((len(profile)-1)*segments+i for i in range(segments))]
    # Bell walls run from throat to exit (descending Z), while hull profiles
    # run aft to nose. Preserve outward winding explicitly for both cases.
    if profile[1][0]<profile[0][0]:faces=[tuple(reversed(f)) for f in faces]
    ob = mesh(name, verts, faces, mat, True)
    if caps:
        ob.data.polygons[-2].use_smooth = False
        ob.data.polygons[-1].use_smooth = False
    return ob

def box(name, loc, scale, mat, bevel=.08, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.rotation_euler.z = angle
    ob.data.materials.append(materials[mat])
    if bevel:
        mod = ob.modifiers.new('Machined edges', 'BEVEL')
        mod.width, mod.segments = bevel, 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    parts.append(ob)
    return ob

def bake(ob):
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=1
    sc.render.bake.use_clear=True;sc.render.bake.margin=5
    images={}
    nodes=[]
    for mat in ob.data.materials:
        tx=mat.node_tree.nodes.new('ShaderNodeTexImage');mat.node_tree.nodes.active=tx
        nodes.append(tx)
    for suffix,size,kind in ATLAS:
        image=bpy.data.images.new(ASSET+'_'+suffix,width=size,height=size,alpha=False)
        image.colorspace_settings.name='sRGB' if suffix in ('d','e') else 'Non-Color'
        for tx in nodes:tx.image=image
        saved=[]
        if suffix=='s':
            for mat in ob.data.materials:
                bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
                color=bs.inputs['Emission Color'];strength=bs.inputs['Emission Strength']
                saved.append((color,tuple(color.default_value),strength,strength.default_value))
                v=float(mat['export_specular']);color.default_value=(v,v,v,1);strength.default_value=1
        if kind=='DIFFUSE':
            bpy.ops.object.bake(type=kind,pass_filter={'COLOR'})
        else:bpy.ops.object.bake(type=kind)
        for color,c,strength,s in saved:color.default_value=c;strength.default_value=s
        image.filepath_raw=str(TEXTURES/(ASSET+'_'+suffix+'.png'))
        image.file_format='PNG';image.save();images[suffix]=image
    # Geometry carries all bevels/panel relief; use a neutral tangent normal.
    image=bpy.data.images.new(ASSET+'_n',width=16,height=16,alpha=False)
    image.colorspace_settings.name='Non-Color';image.generated_color=(.5,.5,1,1)
    image.filepath_raw=str(TEXTURES/(ASSET+'_n.png'));image.file_format='PNG';image.save()
    images['n']=image
    for tx in nodes:tx.image=images['d']
    return images

def game_vector(p):return (float(p[0]),float(p[2]),float(-p[1]))

def chunk(cid,body):return struct.pack('<HI',cid,len(body)+6)+body

# TODO(toolkit gap): MeshSerializer.write always emits an (empty) SUBMESH_NAME_TABLE chunk; these meshes have none.
def export_mesh(ob):
    data=ob.data;data.calc_loop_triangles()
    if EXPORT_TANGENTS:data.calc_tangents(uvmap=data.uv_layers.active.name)
    uv=data.uv_layers.active.data
    vertices=[];indices=[];lookup={}
    for tri in data.loop_triangles:
        for li in tri.loops:
            vi=data.loops[li].vertex_index
            p=game_vector(data.vertices[vi].co);n=game_vector(data.corner_normals[li].vector)
            u,v=uv[li].uv
            row=(*p,*n,float(u),1-float(v))
            if EXPORT_TANGENTS:
                normal=Vector(n);tangent=Vector(game_vector(data.loops[li].tangent))
                tangent-=normal*tangent.dot(normal)
                if tangent.length_squared<1e-12:
                    tangent=normal.cross(Vector((1,0,0) if abs(normal.x)<.8 else (0,1,0)))
                tangent.normalize();row+=tuple(tangent)
            key=tuple(round(x,6) for x in row)
            if key not in lookup:lookup[key]=len(vertices);vertices.append(row)
            indices.append(lookup[key])
    nv=len(vertices);wide=nv>=65536
    idx=struct.pack('<%d%s'%(len(indices),'I' if wide else 'H'),*indices)
    head=(ASSET+'00\n').encode()+struct.pack('<?I?',False,len(indices),wide)+idx
    elements=[(0,2,1,0,0),(0,2,4,12,0),(0,1,7,24,0)]
    if EXPORT_TANGENTS:elements.append((0,2,9,32,0))
    decl=b''.join(chunk(0x5110,struct.pack('<5H',*e)) for e in elements)
    stride=44 if EXPORT_TANGENTS else 32
    vb=struct.pack('<2H',0,stride)+chunk(0x5210,b''.join(struct.pack('<%df'%(stride//4),*v) for v in vertices))
    geom=chunk(0x5000,struct.pack('<I',nv)+chunk(0x5100,decl)+chunk(0x5200,vb))
    sub=chunk(0x4000,head+geom+chunk(0x4010,struct.pack('<H',4)))
    points=[v[:3] for v in vertices]
    lo=[min(p[i] for p in points) for i in range(3)]
    hi=[max(p[i] for p in points) for i in range(3)]
    radius=max(math.sqrt(sum(x*x for x in p)) for p in points)
    bounds=chunk(0x9000,struct.pack('<7f',*lo,*hi,radius))
    (MODEL/(ASSET+'.mesh')).write_bytes(b'\x00\x10[MeshSerializer_v1.100]\n'+chunk(0x3000,b'\0'+sub+bounds))
    return {'vertices':nv,'triangles':len(indices)//3,'bounds_min':lo,'bounds_max':hi,'radius':radius}

def export_native(ob,stats):
    # A native collision/fallback mesh follows the rebuilt silhouette. Keep the
    # native GEO light while the authored Redux mesh retains all visual detail.
    proxy=native_proxy()
    if len(proxy.data.polygons)>3200:
        mod=proxy.modifiers.new('Coarse native face budget','DECIMATE');mod.ratio=3200/len(proxy.data.polygons)
    deps=bpy.context.evaluated_depsgraph_get();evaluated=proxy.evaluated_get(deps)
    me=evaluated.to_mesh();me.calc_loop_triangles()
    points=[game_vector(v.co) for v in me.vertices]
    normals=[game_vector(v.normal) for v in me.vertices]
    asset=ASSET.encode()
    g=geo.Geo();g.name=ASSET;g.vert_count=len(points)
    g.vertex_pos_buffer=np.array(points,dtype='<f4');g.vertex_normal_buffer=np.array(normals,dtype='<f4')
    uv=me.uv_layers.active.data
    for i,tri in enumerate(me.loop_triangles):
        q=[Vector(points[v]) for v in tri.vertices]
        normal=(q[1]-q[0]).cross(q[2]-q[0]).normalized()
        face=g.create_face(i);face.color=geo.Color3(255,255,255)
        face.plane=geo.SurfacePlane(geo.Vector3(*(-normal)),normal.dot(q[0]))
        face.shade_type=face.texture_type=0;face.texture_name=ASSET+'.map'
        for vi,li in zip(tri.vertices,tri.loops):
            u,v=uv[li].uv;face.create_face_node(vi,vi,geo.UV(float(u),1-float(v)))
    raw=io.BytesIO();geo_serializer.GeoSerializer(raw).write(g)
    (MODEL/(ASSET+'.geo')).write_bytes(raw.getvalue())
    stats['native_vertices']=len(points);stats['native_triangles']=len(me.loop_triangles)
    evaluated.to_mesh_clear();bpy.data.objects.remove(proxy,do_unlink=True)
    # Standard static BWD/SDFC metadata, no dependence on the old Resurgence art.
    # TODO(toolkit gap): SDFSerializer.write always emits 3 EXIT chunks (this file has 2) and cannot omit them.
    prefix=struct.pack('<4si4sii',b'BWD2',8,b'REV\0',12,8)
    prefix+=struct.pack('<4si16si5fi',b'SDFC',78,asset,1,2000.,1e20,1e20,1e20,1e20,0)
    prefix+=b'xbldx1.xdf'.ljust(14,b'\0')+b'null'.ljust(12,b'\0')
    assert len(prefix)==98
    center=[(a+b)/2 for a,b in zip(stats['bounds_min'],stats['bounds_max'])]
    half=[(b-a)/2 for a,b in zip(stats['bounds_min'],stats['bounds_max'])]
    rec=struct.pack('<8s12f8s7fiii4f',asset,1,0,0,0,1,0,0,0,1,0,0,0,b'WORLD',*center,stats['radius'],*half,60,0,0,0,0,0,0)
    null=bytes(120);null=b'NULL'+null[4:]
    body=struct.pack('<i',1)+rec+null*5
    (MODEL/(ASSET+'.sdf')).write_bytes(prefix+struct.pack('<4si',b'SGEO',8+len(body))+body+struct.pack('<4si',b'EXIT',8)*2)


if __name__=='__main__':main()
