"""Author the Mars-art CCA rocket in Blender, including editable source and exports.

Run through Build-Misn06Rocket.py, or Blender -b --factory-startup --python
Tools/Author-Misn06Rocket.py -- --render. Coordinates are metres, Blender Z-up;
the exported game model is Y-up with its original origin and nozzle plane.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector
from mathutils import Quaternion

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'References/Misn06Rocket'
TEXTURES = SOURCE / 'Textures'
MODEL = ROOT / 'Assets/ModelFixes'
TAU = math.tau
parts = []
materials = {}


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
        noise.inputs['Scale'].default_value = 10
        noise.inputs['Detail'].default_value = 2
        ramp = nt.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position = .15
        ramp.color_ramp.elements[0].color = (*(v * .84 for v in color), 1)
        ramp.color_ramp.elements[1].position = .85
        ramp.color_ramp.elements[1].color = (*color, 1)
        nt.links.new(coord.outputs['Object'], noise.inputs['Vector'])
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


def ring(name, z, radius, height, mat, segments=48):
    return lathe(name, [(z-height/2, radius-.08), (z-height/2+.08, radius),
                        (z+height/2-.08, radius), (z+height/2, radius-.08)],
                 mat, segments)


def patch(name, z0, z1, a0, a1, radius0, radius1, mat, segments=4):
    verts = []
    for z, r in ((z0, radius0), (z1, radius1)):
        verts.extend((r*math.cos(a0+(a1-a0)*i/segments),
                      r*math.sin(a0+(a1-a0)*i/segments), z)
                     for i in range(segments+1))
    n = segments+1
    return mesh(name, verts, [(i, i+1, i+1+n, i+n) for i in range(segments)], mat, True)


def plate(name, angle, z, width, height, radius, mat):
    return patch(name, z-height/2, z+height/2, angle-width/(2*radius),
                 angle+width/(2*radius), radius, radius, mat)


def armour_panel(name,z0,z1,a0,a1,r0,r1,mat):
    """Chamfered, slightly interlocking armour plate wrapped around the hull."""
    angle=(a0+a1)/2; radius=(r0+r1)/2
    half=(a1-a0)*radius/2
    def surface(inset,lift,material_name):
        w=half-inset;lo=z0+inset;hi=z1-inset;mid=(lo+hi)/2
        outline=[(-w+.35,lo),(w-.35,lo),(w,lo+.6),(w,mid-.8),
                 (w-.28,mid-.5),(w-.28,mid+.5),(w,mid+.8),
                 (w,hi-.6),(w-.35,hi),(-w+.35,hi),(-w,hi-.6),(-w,lo+.6)]
        def point(u,z):
            r=r0+(r1-r0)*(z-z0)/(z1-z0)+lift
            a=angle+u/radius
            return(r*math.cos(a),r*math.sin(a),z)
        verts=[point(0,mid)]+[point(u,z) for u,z in outline]
        return mesh(name,verts,[(0,i+1,(i+1)%len(outline)+1) for i in range(len(outline))],material_name,True)
    surface(0,.06,'Dark recess')
    surface(.14,.105,'Steel')
    surface(.23,.14,mat)


def star(angle, z, radius=10.96):
    # Curved geometric marking: no texture projection or alpha sorting dependency.
    verts = [(radius*math.cos(angle), radius*math.sin(angle), z)]
    for i in range(10):
        t = math.pi/2 + i*math.pi/5
        r = 2.05 if i % 2 == 0 else .86
        a = angle + r*math.cos(t)/radius
        verts.append((radius*math.cos(a), radius*math.sin(a), z+r*math.sin(t)))
    return mesh('CCA red star', verts, [(0, i+1, (i+1) % 10+1) for i in range(10)], 'Red')


def make_rocket():
    material('Ivory', (.74, .71, .61), .28, .44)
    material('Alternate panel', (.61, .61, .55), .32, .48)
    material('Bright trim', (.82, .8, .7), .55, .32)
    material('Steel', (.24, .26, .25), .75, .35)
    material('Bell alloy', (.60,.57,.46), .48, .43)
    material('Dark recess', (.035, .043, .047), .45, .54)
    material('Red', (.48, .025, .014), .12, .47)
    material('Amber lamp', (.95, .58, .035), .2, .25, (1, .64, .04))
    material('Red lamp', (.6, .015, .008), .1, .3, (1, .025, .006))
    material('Bell liner', (.105, .10, .085), .7, .48)

    # The nozzle plane remains -48.5 m; major structure fits the old ~30 m width.
    lathe('Aft engine deck', [(-35.0, 10.9), (-34.6, 12.9), (-32.5, 13.25),
                            (-29.8, 13.25), (-29.0, 12.65), (-26.0, 11.0)], 'Steel')
    for z, r, h, mat in [(-34.5, 12.85, .55, 'Bright trim'),
                          (-31.9, 13.4, .45, 'Dark recess'),
                          (-29.6, 13.3, .6, 'Bright trim'),
                          (-26.1, 11.12, .45, 'Steel')]:
        ring('Engine collar', z, r, h, mat)
    for i in range(24):
        a = TAU*i/24
        # Readable blocks of warm collar lights, between black metal fittings.
        plate('Collar light socket', a, -30.6, .95, 1.25, 13.32, 'Dark recess')
        plate('Amber collar lens', a, -30.6, .57, .72, 13.39, 'Amber lamp')
        if i % 6 == 0:
            plate('Aft red status', a, -33.35, .45, .6, 13.08, 'Red lamp')

    nozzle_centers = []
    for i in range(8):
        a = TAU*(i+.5)/8
        x, y = 8.0*math.cos(a), 8.0*math.sin(a)
        nozzle_centers.append([x, -48.5, -y])  # exported Y-up game coordinates
        # Continuous closed wall: outer flare, lip, inner flare, closed throat.
        profile = [(-35.0, 1.6), (-37.4, 1.42), (-40.0, 1.65),
                   (-44.8, 2.3), (-48.15, 2.85), (-48.5, 2.85),
                   (-48.5, 2.61), (-48.1, 2.60), (-44.7, 2.04),
                   (-40.0, 1.39), (-37.6, 1.15)]
        bell=lathe('Flared engine bell %02d' % (i+1), profile, 'Bell alloy', 32, (x,y), False)
        bell.data.materials.append(materials['Bell liner'])
        for face in bell.data.polygons:
            if face.index//32>=6:face.material_index=1
        lathe('Dark bell throat %02d' % (i+1), [(-37.65, 1.15), (-37.55, .02)],
              'Bell liner', 24, (x,y))
        for z, r in [(-39.8, 1.73), (-43.0, 2.13), (-46.6, 2.68)]:
            lathe('Bell reinforcement', [(z-.12, r-.06), (z, r), (z+.12, r-.06)],
                  'Bright trim', 24, (x,y), False)
        lathe('Bell mounting neck', [(-37.5, 1.65), (-36.8, 1.93), (-34.8, 1.93)],
              'Bright trim', 24, (x,y))

    # A continuous near-cylindrical body replaces the old stack of cone skirts.
    lathe('Pressure hull and seam bed', [(-26,10.75), (-12.3,10.60),
          (2.65,10.43), (16.8,9.88), (19.4,8.78), (23.8,6.15)], 'Dark recess')
    bands = [(-25.8, -12.3, 10.91, 10.76), (-12.15, 2.5, 10.76, 10.59),
             (2.65, 16.8, 10.59, 10.03)]
    for j, (z0,z1,r0,r1) in enumerate(bands):
        for i in range(12):
            a = TAU*i/12
            armour_panel('Ivory hull panel %d-%02d' % (j,i), z0,z1,
                  a+.006, a+TAU/12-.006, r0,r1,
                  'Alternate panel' if (i+2*j) % 7 == 0 else 'Ivory')
    lathe('Shoulder', [(16.9,10.0),(19.4,8.9),(23.8,6.3)], 'Ivory')
    ring('Shoulder seam', 17.0, 10.05, .16, 'Steel')
    # Long nose with fine longitudinal seams, never an overlapping cone skirt.
    profile = [(23.8,6.3),(29,5.0),(35,3.45),(41,1.94),(46.5,.48),(48.5,.025)]
    lathe('Nose seam bed', profile, 'Steel')
    for i in range(12):
        a = TAU*i/12
        for j in range(len(profile)-1):
            z0,r0=profile[j]; z1,r1=profile[j+1]
            patch('Needle nose skin', z0,z1,a+.003,a+TAU/12-.003,
                  r0+.015,r1+.015,'Bright trim' if i % 4 == 0 else 'Ivory',4)
    # The red forward band follows the taper.
    patch_count = 48
    for i in range(patch_count):
        a = TAU*i/patch_count
        patch('CCA forward red band', 28.2,29.0,a,a+TAU/patch_count,
              5.235,5.035,'Red',1)
    for i in range(4):
        a = TAU*(i+.125)/4
        r=10.76
        box('Longitudinal hull rail', (r*math.cos(a),r*math.sin(a),-5),
            (.29,.43,36),'Bright trim',.07,a)
    for i in range(8):
        a = TAU*(i+.5)/8
        z = -18.3 if i % 2 == 0 else 7.2
        rad = 10.91 if z < 0 else 10.47
        plate('Access hatch gasket',a,z,2.8,4.1,rad+.08,'Dark recess')
        plate('Access hatch',a,z,2.55,3.84,rad+.11,'Alternate panel')
        plate('Hatch handle',a,z-.8,.6,.16,rad+.15,'Steel')
        for side in (-1,1):
            plate('Hatch latch',a+side*.9/rad,z+1.1,.25,.4,rad+.17,'Steel')
    for a,z,r in [(-math.pi/2,10.5,10.48),(math.pi/2,-7,10.78),(0,-7,10.78)]:
        plate('Marking plaque outline',a,z,5.4,6.2,r+.14,'Steel')
        plate('Marking plaque',a,z,5.18,5.98,r+.17,'Ivory')
        star(a,z,r+.21)

    # Raised dorsal spine with an arched, AFT-facing four-lamp housing. The
    # artwork shows these lamps above the collar, looking toward the engines.
    box('Dorsal service spine',(0,-10.48,-3.5),(7.8,1.7,39),'Steel',.28)
    for x in (-3.35,3.35):
        box('Spine bright rail',(x,-11.52,-3.5),(.32,.42,38.5),'Bright trim',.08)
    for z in (-18,-13,10.5,14):
        box('Spine removable cover',(0,-11.52,z),(5.65,.42,2.4),'Alternate panel',.18)
        for x in (-2.25,2.25):
            box('Spine cover latch',(x,-11.78,z),(.3,.2,.65),'Steel',.04)
    outline=[(-4.1,-10.9)]+[(4.1*math.cos(math.pi-i*math.pi/8),
              -11.0-4.9*math.sin(math.pi-i*math.pi/8)) for i in range(9)]+[(4.1,-10.9)]
    nv=len(outline)
    verts=[(x,y,z) for z in (-8.5,5.5) for x,y in outline]
    faces=[tuple(range(nv-1,-1,-1)),tuple(nv+i for i in range(nv))]
    faces += [(i,(i+1)%nv,(i+1)%nv+nv,i+nv) for i in range(nv)]
    mesh('Arched dorsal lamp housing',verts,faces,'Steel')
    # A flat black rear mask and four domed lamps face down the rocket axis.
    mask=[(x*.91,-11+(y+11)*.9,-8.58) for x,y in outline]
    mesh('Aft lamp mask',mask,[tuple(range(len(mask)-1,-1,-1))],'Dark recess')
    for x in (-2.4,-.8,.8,2.4):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8,
                                           radius=.68,location=(x,-14.05,-8.78))
        ob=bpy.context.object;ob.name='Amber avionics lens';ob.scale=(1,1,.45)
        ob.data.materials.append(materials['Amber lamp'])
        for p in ob.data.polygons:p.use_smooth=True
        parts.append(ob)
    for x in (-2.85,2.85):
        box('Housing roof seam',(x,-14.5,-1),(.18,.2,11.8),'Bright trim',.04)
    # Raised service channels on the side faces interrupt the clean cylinder.
    for a in (-.3,math.pi+.3):
        for z in (-18.5,-5,9):
            r=10.95 if z<0 else 10.55
            plate('Service channel dark border',a,z,1.7,8.5,r+.16,'Dark recess')
            plate('Service channel cover',a,z,1.28,7.9,r+.22,'Alternate panel')
            plate('Service channel latch',a,z-2.6,.55,.65,r+.27,'Steel')

    # Aft side fairings and small red hazard tabs ground the machine visually.
    for i in range(8):
        a=TAU*i/8
        box('Collar structural cleat',(11.4*math.cos(a),11.4*math.sin(a),-26),
            (1.5,1.25,4.2),'Ivory',.18,a)
        plate('Red hazard tab',a,-27.4,.7,1.2,12.15,'Red')
    return nozzle_centers


def join_and_uv():
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:ob.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    ob=bpy.context.object;ob.name='CCA Mars transport — rebuilt'
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # The first part was authored at the origin; retain the tested fixture pivot.
    assert ob.location.length < .00001
    # Every authored primitive has explicit outward winding. A blanket normal
    # recalculation can arbitrarily reverse disconnected paint/armour cards.
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(68),island_margin=.006)
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob


def bake(ob):
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=1
    sc.render.bake.use_clear=True;sc.render.bake.margin=5
    images={}
    nodes=[]
    for mat in ob.data.materials:
        tx=mat.node_tree.nodes.new('ShaderNodeTexImage');mat.node_tree.nodes.active=tx
        nodes.append(tx)
    for suffix,size,kind in [('d',2048,'DIFFUSE'),('e',1024,'EMIT'),('s',512,'EMIT')]:
        image=bpy.data.images.new('cr06rok_'+suffix,width=size,height=size,alpha=False)
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
        image.filepath_raw=str(TEXTURES/('cr06rok_'+suffix+'.png'))
        image.file_format='PNG';image.save();images[suffix]=image
    # Geometry carries all bevels/panel relief; use a neutral tangent normal.
    image=bpy.data.images.new('cr06rok_n',width=16,height=16,alpha=False)
    image.colorspace_settings.name='Non-Color';image.generated_color=(.5,.5,1,1)
    image.filepath_raw=str(TEXTURES/'cr06rok_n.png');image.file_format='PNG';image.save()
    images['n']=image
    for tx in nodes:tx.image=images['d']
    return images


def game_vector(p):return (float(p[0]),float(p[2]),float(-p[1]))


def chunk(cid,body):return struct.pack('<HI',cid,len(body)+6)+body


def export_mesh(ob):
    data=ob.data;data.calc_loop_triangles()
    uv=data.uv_layers.active.data
    vertices=[];indices=[];lookup={}
    for tri in data.loop_triangles:
        for li in tri.loops:
            vi=data.loops[li].vertex_index
            p=game_vector(data.vertices[vi].co);n=game_vector(data.corner_normals[li].vector)
            u,v=uv[li].uv
            row=(*p,*n,float(u),1-float(v))
            key=tuple(round(x,6) for x in row)
            if key not in lookup:lookup[key]=len(vertices);vertices.append(row)
            indices.append(lookup[key])
    nv=len(vertices);wide=nv>=65536
    idx=struct.pack('<%d%s'%(len(indices),'I' if wide else 'H'),*indices)
    head=b'cr06rok00\n'+struct.pack('<?I?',False,len(indices),wide)+idx
    decl=b''.join(chunk(0x5110,struct.pack('<5H',*e)) for e in [(0,2,1,0,0),(0,2,4,12,0),(0,1,7,24,0)])
    vb=struct.pack('<2H',0,32)+chunk(0x5210,b''.join(struct.pack('<8f',*v) for v in vertices))
    geom=chunk(0x5000,struct.pack('<I',nv)+chunk(0x5100,decl)+chunk(0x5200,vb))
    sub=chunk(0x4000,head+geom+chunk(0x4010,struct.pack('<H',4)))
    points=[v[:3] for v in vertices]
    lo=[min(p[i] for p in points) for i in range(3)]
    hi=[max(p[i] for p in points) for i in range(3)]
    radius=max(math.sqrt(sum(x*x for x in p)) for p in points)
    bounds=chunk(0x9000,struct.pack('<7f',*lo,*hi,radius))
    (MODEL/'cr06rok.mesh').write_bytes(b'\x00\x10[MeshSerializer_v1.100]\n'+chunk(0x3000,b'\0'+sub+bounds))
    return {'vertices':nv,'triangles':len(indices)//3,'bounds_min':lo,'bounds_max':hi,'radius':radius}


def export_native(ob,stats):
    # A native collision/fallback mesh follows the rebuilt silhouette. Keep the
    # native GEO light while the authored Redux mesh retains all visual detail.
    proxy=ob.copy();proxy.data=ob.data.copy();bpy.context.collection.objects.link(proxy)
    mod=proxy.modifiers.new('Native fallback reduction','DECIMATE');mod.ratio=.12
    deps=bpy.context.evaluated_depsgraph_get();evaluated=proxy.evaluated_get(deps)
    me=evaluated.to_mesh();me.calc_loop_triangles()
    points=[game_vector(v.co) for v in me.vertices]
    normals=[game_vector(v.normal) for v in me.vertices]
    raw=struct.pack('<4si16siii',b'OEG.',0,b'cr06rok',len(points),len(me.loop_triangles),0)
    raw+=b''.join(struct.pack('<3f',*p) for p in points+normals)
    uv=me.uv_layers.active.data
    for i,tri in enumerate(me.loop_triangles):
        q=[Vector(points[v]) for v in tri.vertices]
        normal=(q[1]-q[0]).cross(q[2]-q[0]).normalized()
        raw+=struct.pack('<iiBBBffffi3s13sii',i,3,255,255,255,*(-normal),normal.dot(q[0]),0,bytes(3),b'cr06rok.map',0,0)
        for vi,li in zip(tri.vertices,tri.loops):
            u,v=uv[li].uv;raw+=struct.pack('<iiff',vi,vi,float(u),1-float(v))
    (MODEL/'cr06rok.geo').write_bytes(raw)
    stats['native_vertices']=len(points);stats['native_triangles']=len(me.loop_triangles)
    evaluated.to_mesh_clear();bpy.data.objects.remove(proxy,do_unlink=True)
    # Standard static BWD/SDFC metadata, no dependence on the old Resurgence art.
    prefix=struct.pack('<4si4sii',b'BWD2',8,b'REV\0',12,8)
    prefix+=struct.pack('<4si16si5fi',b'SDFC',78,b'cr06rok',1,2000.,1e20,1e20,1e20,1e20,0)
    prefix+=b'xbldx1.xdf'.ljust(14,b'\0')+b'null'.ljust(12,b'\0')
    assert len(prefix)==98
    center=[(a+b)/2 for a,b in zip(stats['bounds_min'],stats['bounds_max'])]
    half=[(b-a)/2 for a,b in zip(stats['bounds_min'],stats['bounds_max'])]
    rec=struct.pack('<8s12f8s7fiii4f',b'cr06rok',1,0,0,0,1,0,0,0,1,0,0,0,b'WORLD',*center,stats['radius'],*half,60,0,0,0,0,0,0)
    null=bytes(120);null=b'NULL'+null[4:]
    body=struct.pack('<i',1)+rec+null*5
    (MODEL/'cr06rok.sdf').write_bytes(prefix+struct.pack('<4si',b'SGEO',8+len(body))+body+struct.pack('<4si',b'EXIT',8)*2)


def inspection(ob):
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=32
    sc.world=bpy.data.worlds.new('Inspection world');sc.world.use_nodes=True
    bg=next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND')
    bg.inputs[0].default_value=(.12,.14,.17,1);bg.inputs[1].default_value=.5
    for name,loc,power,size in [('Key',(70,-100,90),240000,90),('Fill',(-80,-20,20),90000,65),('Rim',(30,70,60),200000,70)]:
        ld=bpy.data.lights.new(name,'AREA');ld.energy=power;ld.shape='DISK';ld.size=size
        light=bpy.data.objects.new(name,ld);sc.collection.objects.link(light);light.location=loc
        light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
    cd=bpy.data.cameras.new('Inspection camera');cd.type='ORTHO';cd.ortho_scale=114
    cam=bpy.data.objects.new('Inspection camera',cd);sc.collection.objects.link(cam);sc.camera=cam
    sc.render.resolution_x=800;sc.render.resolution_y=1000;sc.render.resolution_percentage=100
    for label,loc in [('front',(150,-270,22)),('engines',(100,-210,-105))]:
        cam.location=loc;cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
        sc.render.filepath=str(SOURCE/('rebuilt-'+label+'.png'));bpy.ops.render.render(write_still=True)
    cd.type='PERSP';cd.lens=35
    sc.render.resolution_x=1000;sc.render.resolution_y=750
    cam.location=(45,-95,-60)
    cam.rotation_euler=((-cam.location).to_track_quat('-Z','Y') @ Quaternion((0,0,1),math.radians(45))).to_euler()
    sc.render.filepath=str(SOURCE/'rebuilt-concept-angle.png');bpy.ops.render.render(write_still=True)


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--render',action='store_true')
    args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    for path in (SOURCE,TEXTURES,MODEL):path.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    nozzles=make_rocket();ob=join_and_uv();bake(ob)
    stats=export_mesh(ob);export_native(ob,stats)
    stats.update({'nozzles':nozzles,'nozzle_plane':-48.5,'source':'CR-authored reconstruction of marspict.png',
                  'reference_sha256':'58e4336cedd89c2f8a8864cdcb6ea45706f1b5544b47a2ebc34013c36e482213'})
    (SOURCE/'geometry.json').write_text(json.dumps(stats,indent=2)+'\n',encoding='utf-8')
    if args.render:inspection(ob)
    for image in bpy.data.images:
        if image.filepath and Path(image.filepath).parent==TEXTURES:
            image.filepath='//Textures/'+Path(image.filepath).name
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'CCA-Mars-Transport.blend'),compress=True)
    print('ROCKET_REBUILT',json.dumps(stats),flush=True)


if __name__=='__main__':main()
