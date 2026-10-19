"""Author the Mars-art CCA rocket in Blender, including editable source and exports.

Run through Build-Misn06Rocket.py, or Blender -b --factory-startup --python
Tools/Author-Misn06Rocket.py -- --render. Coordinates are metres, Blender Z-up;
the exported game model is Y-up with its original origin and nozzle plane.
"""
import argparse
import json
import math
from pathlib import Path
import io
import struct
import sys

import numpy as np
import bpy
from mathutils import Vector
from mathutils import Quaternion

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bzmodellibs import geo, geo_serializer
from bzstaticmodel import mesh_bounds, static_mesh_bytes, static_sdf_bytes

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
        noise.inputs['Scale'].default_value = .65
        noise.inputs['Detail'].default_value = 4
        streak = nt.nodes.new('ShaderNodeVectorMath');streak.operation='MULTIPLY'
        streak.inputs[1].default_value=(1,1,.22)
        ramp = nt.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position = .15
        ramp.color_ramp.elements[0].color = (*(v * .28 for v in color), 1)
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
    # Close geometric study of Coxxon's Total Command CCA Rocketship. These
    # primitives, panel meshes and procedural materials are authored here;
    # no Total Command mesh triangles, UVs or texture pixels are copied.
    material('Ivory', (.59,.565,.50), .28,.48)
    material('Alternate panel', (.43,.44,.40), .36,.53)
    material('Bright trim', (.78,.77,.68), .52,.38)
    material('Steel', (.22,.24,.23), .7,.4)
    material('Bell alloy', (.34,.35,.31), .65,.44)
    material('Dark recess', (.027,.034,.034), .4,.63)
    material('Engine ceramic', (.065,.105,.11), .3,.63)
    material('Red', (.46,.024,.013), .15,.5)
    material('Amber lamp', (.98,.83,.16), .15,.3, (1,.83,.18))
    material('Red lamp', (.65,.015,.008), .1,.3, (1,.025,.006))
    material('Bell liner', (.12,.085,.04), .65,.5)
    scale=97/77.58216095
    def z(h):return h*scale-48.5
    def r(radius):return radius*scale
    def shell(name,profile,mat='Ivory',segments=64,caps=True,center=(0,0)):
        return lathe(name,[(z(h),r(rad)) for h,rad in profile],mat,segments,center,caps)
    def skin(name,h0,h1,r0,r1,mat='Ivory',n=16):
        # Thin panel gaps, with broad irregular machinery fields on the lower
        # stage instead of the previous continuous cylindrical hull.
        shell(name+' seam bed',[(h0,r0-.035),(h1,r1-.035)],'Dark recess')
        for row in range(2 if h1-h0>6 else 1):
            rows=2 if h1-h0>6 else 1
            lo=h0+(h1-h0)*row/rows;hi=h0+(h1-h0)*(row+1)/rows
            rr0=r0+(r1-r0)*row/rows;rr1=r0+(r1-r0)*(row+1)/rows
            for i in range(n):
                a=TAU*(i+.5*(row%2))/n
                patch(name+' plate %02d'%i,z(lo)+.055,z(hi)-.055,
                    a+.004,a+TAU/n-.004,r(rr0)+.015,r(rr1)+.015,
                    'Alternate panel' if (i+row)%11==3 else mat,4)
    def lenses(name,h,rad,count=24,color='Amber lamp',height=.44):
        for i in range(count):
            a=TAU*(i+.5)/count
            plate(name+' socket',a,z(h),r(.91),r(height+.32),r(rad+.015),'Dark recess')
            plate(name+' lens',a,z(h),r(.63),r(height),r(rad+.055),color)
    def field(name,a,h0,h1,r0,r1,width):
        patch(name,z(h0),z(h1),a-width/2,a+width/2,r(r0+.13),r(r1+.13),'Dark recess',6)
        # Four stacked exposed machinery trays: dark pipes and pale access
        # covers remain legible from the film's low engine-side angle.
        for j in range(4):
            lo=h0+(h1-h0)*j/4+.12;hi=h0+(h1-h0)*(j+.87)/4
            rr0=r0+(r1-r0)*(lo-h0)/(h1-h0)
            rr1=r0+(r1-r0)*(hi-h0)/(h1-h0)
            patch(name+' tray',z(lo),z(hi),a-width*.39,a+width*.39,
                  r(rr0+.18),r(rr1+.18),'Steel',4)
            for k in range(4):
                aa=a-width*.34+k*width*.22
                patch(name+' pipe',z(lo+.12),z(hi-.12),aa-.018,aa+.018,
                      r(rr0+.25),r(rr1+.25),'Dark recess',1)
            patch(name+' cover',z(lo+.16),z(hi-.14),a-width*.22,a+width*.03,
                  r(rr0+.29),r(rr1+.29),'Alternate panel',2)
            patch(name+' cover seam',z(lo+.17),z(hi-.15),a-width*.12,a-width*.10,
                  r(rr0+.31),r(rr1+.31),'Bright trim',1)

    # Eight long enclosed engine cans, dark midsections and short ribbed bells.
    # The measured TC hardpoints lie on a 7m circle at h=1.168m. The geometry
    # exits are h=0; normalize the complete reference to our fixed 97m height.
    nozzles=[]
    for i in range(8):
        a=TAU*i/8;x,y=r(7)*math.cos(a),r(7)*math.sin(a)
        nozzles.append([x,-48.5,-y])
        shell('Engine can %02d'%i,[(3.0,2.65),(3.5,2.65),(12.7,2.65),(13.3,2.18)],
              'Bell alloy',32,True,(x,y))
        shell('Engine dark heat shield',[(5.4,2.68),(9.6,2.68)],'Engine ceramic',32,True,(x,y))
        for k in range(8):
            aa=TAU*k/8
            verts=[]
            for h in (3.2,5.25):
                for da in (-.018,.018):
                    verts.append((x+r(2.70)*math.cos(aa+da),y+r(2.70)*math.sin(aa+da),z(h)))
            mesh('Engine ceramic casing joint',verts,[(0,1,3,2)],'Dark recess',True)
        shell('Engine bell',[(3,2.12),(2.75,2.10),(.20,2.68),(0,2.68),
                            (0,2.4),(.25,2.38),(2.75,1.9)],'Steel',32,False,(x,y))
        for j in range(7):
            h=.15+j*.39;rad=2.67-h*.20
            shell('Bell cooling rib',[(h,rad),(h+.09,rad+.06),(h+.16,rad-.025)],
                  'Bell alloy',32,False,(x,y))
        shell('Bell hot throat',[(2.72,.02),(2.75,1.90)],'Bell liner',24,True,(x,y))
        for k in range(8):
            aa=TAU*k/8
            # Light seams around the can's ivory top section.
            verts=[(x+r(2.67)*math.cos(aa+d),y+r(2.67)*math.sin(aa+d),z(h))
                   for h in (9.7,12.7) for d in (-.014,.014)]
            mesh('Engine upper casing seam',verts,[(0,1,3,2)],'Dark recess',True)

    shell('Aft structural deck',[(13.3,9.5),(14.77,10.5),(17.0,10.7),(18.08,10.8),
           (18.29,12),(18.65,11.92)],'Steel')
    lenses('Underside engine floodlights',14.25,10.1,24,height=.52)
    lenses('Lower collar status',17.15,10.78,4,'Red lamp',.22)

    # Reference's dominant lower conical skirt: maximum radius 12m at h18.29,
    # narrowing to 8m at h37.72. The centre and upper cone retain their steps.
    skin('Lower tapered hull',18.29,27.6,12,10)
    skin('Upper tapered hull',27.7,37.72,10,8)
    shell('Mid skirt seam',[(37.72,8),(38.75,7.5),(39.75,7.95)],'Steel')
    skin('Upper command cone',39.75,49.0,7.95,5.95,n=12)
    shell('Forward skirt lip',[(48.96,5.95),(49.17,7.0),(49.32,6.97)],'Steel')
    skin('Forward cone',49.32,58.17,6.97,4.0,n=12)
    shell('Needle skirt lip',[(58.17,4),(58.38,5),(58.55,4.97)],'Steel')
    skin('Needle lower skin',58.55,65.2,4.97,3.26,n=12)
    skin('Needle upper skin',65.3,70.4,3.24,1.93,n=12)
    shell('Needle tip',[(70.45,1.92),(75.0,.67),(77.58216095,.015)],'Bright trim')
    for h,rad in [(65.25,3.28),(70.4,1.97)]:
        ring('Nose circumferential seam',z(h),r(rad),r(.07),'Steel',64)
    for h,rad in [(23.5,11.0),(38.2,7.92)]:
        ring('Warm lamp ring recess',z(h),r(rad),r(.72),'Dark recess',64)
        lenses('Warm segmented lamp ring',h,rad,32,height=.40)
    lenses('Red command skirt lip',49.12,6.88,24,'Red lamp',.16)
    lenses('Red upper skirt lip',39.6,7.91,24,'Red lamp',.14)

    # TC's dark upper command inset and ladder grille, repeated around the cone.
    for i in range(4):
        a=TAU*i/4
        patch('Command inset',z(40.2),z(48.7),a-.24,a+.24,r(7.98),r(6.17),'Engine ceramic',8)
        for j in range(7):
            h=40.6+j*.72;rad=7.95-(h-39.75)*2/9.25
            patch('Command cooling grille',z(h),z(h+.22),a+.35,a+.52,
                  r(rad+.12),r(rad+.10),'Dark recess',2)
    # Wide stepped maintenance wells and ivory panel covers on the main skirt.
    for a in (-math.pi/6,5*math.pi/6):
        field('Main machinery well',a,23.8,36.4,10.84,8.28,.76)
        field('Lower machinery well',a-1.0,20.6,26.0,11.55,10.43,.42)
    # Access hatch at the bottom of the main body, with small red status lamps.
    for a in (0,math.pi):
        patch('Hatch gasket',z(18.8),z(22.6),a-.15,a+.15,r(11.98),r(11.18),'Dark recess',4)
        patch('Hatch inset',z(19),z(22.4),a-.13,a+.13,r(11.99),r(11.20),'Alternate panel',4)
        star(a,z(21.0),r(11.64))
        plate('Hatch indicator',a,z(18.45),r(.28),r(.18),r(12.01),'Red lamp')
    # Close-to-reference forward sensor band rather than a solid red stripe.
    for i in range(48):
        a=TAU*i/48
        patch('Forward sensor slot',z(62.6),z(63.6),a+.015,a+TAU/48-.015,
              r(3.95),r(3.69),'Engine ceramic',1)
    # Small outline hatches and broad hull panel variation, not pristine plastic.
    for i in range(8):
        a=TAU*(i+.25)/8
        patch('Lower service hatch gasket',z(29.3),z(32.0),a-.12,a+.12,r(9.79),r(9.22),'Dark recess',3)
        patch('Lower service hatch panel',z(29.45),z(31.86),a-.105,a+.105,r(9.77),r(9.25),'Alternate panel',3)
    # Fine staggered repair-panel outlines break up the large conical plates.
    for i in range(12):
        a=TAU*(i+.4)/12
        for h0,h1,rr0,rr1 in [(19.1,22.2,11.90,11.26),(33.1,36.2,8.92,8.28),
                               (51.0,54.8,6.64,5.38)]:
            w=.085 if h0>40 else .10
            patch('Repair panel seam',z(h0),z(h1),a-w,a+w,r(rr0+.015),r(rr1+.015),'Steel',3)
            patch('Repair panel face',z(h0+.07),z(h1-.07),a-w+.006,a+w-.006,
                  r(rr0+.015),r(rr1+.045),'Ivory' if i%3 else 'Alternate panel',3)
    return nozzles



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
    nv=len(vertices)
    lo,hi,radius=mesh_bounds(vertices)
    (MODEL/'cr06rok.mesh').write_bytes(static_mesh_bytes('cr06rok'+'00',vertices,indices))
    return {'vertices':nv,'triangles':len(indices)//3,'bounds_min':lo,'bounds_max':hi,'radius':radius}


def export_native(ob,stats):
    # A native collision/fallback mesh follows the rebuilt silhouette. Keep the
    # native GEO light while the authored Redux mesh retains all visual detail.
    proxy=ob.copy();proxy.data=ob.data.copy();bpy.context.collection.objects.link(proxy)
    mod=proxy.modifiers.new('Native fallback reduction','DECIMATE');mod.ratio=.07
    deps=bpy.context.evaluated_depsgraph_get();evaluated=proxy.evaluated_get(deps)
    me=evaluated.to_mesh();me.calc_loop_triangles()
    points=[game_vector(v.co) for v in me.vertices]
    normals=[game_vector(v.normal) for v in me.vertices]
    g=geo.Geo();g.name='cr06rok';g.vert_count=len(points)
    g.vertex_pos_buffer=np.array(points,dtype='<f4');g.vertex_normal_buffer=np.array(normals,dtype='<f4')
    uv=me.uv_layers.active.data
    for i,tri in enumerate(me.loop_triangles):
        q=[Vector(points[v]) for v in tri.vertices]
        normal=(q[1]-q[0]).cross(q[2]-q[0]).normalized()
        face=g.create_face(i);face.color=geo.Color3(255,255,255)
        face.plane=geo.SurfacePlane(geo.Vector3(*(-normal)),normal.dot(q[0]))
        face.shade_type=face.texture_type=0;face.texture_name='cr06rok.map'
        for vi,li in zip(tri.vertices,tri.loops):
            u,v=uv[li].uv;face.create_face_node(vi,vi,geo.UV(float(u),1-float(v)))
    raw=io.BytesIO();geo_serializer.GeoSerializer(raw).write(g)
    (MODEL/'cr06rok.geo').write_bytes(raw.getvalue())
    stats['native_vertices']=len(points);stats['native_triangles']=len(me.loop_triangles)
    evaluated.to_mesh_clear();bpy.data.objects.remove(proxy,do_unlink=True)
    # Standard static BWD/SDFC metadata (shared writer), no dependence on the old Resurgence art.
    center=[(a+b)/2 for a,b in zip(stats['bounds_min'],stats['bounds_max'])]
    half=[(b-a)/2 for a,b in zip(stats['bounds_min'],stats['bounds_max'])]
    (MODEL/'cr06rok.sdf').write_bytes(static_sdf_bytes('cr06rok',center,half,stats['radius']))


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
    stats.update({'nozzles':nozzles,'nozzle_plane':-48.5,'source':'CR-authored close study of Total Command CCA Rocketship',
                  'model_reference':'Coxxon / Total Command / sbconecox00.msh',
                  'reference_sha256':'58e4336cedd89c2f8a8864cdcb6ea45706f1b5544b47a2ebc34013c36e482213'})
    (SOURCE/'geometry.json').write_text(json.dumps(stats,indent=2)+'\n',encoding='utf-8')
    if args.render:inspection(ob)
    for image in bpy.data.images:
        if image.filepath and Path(image.filepath).parent==TEXTURES:
            image.filepath='//Textures/'+Path(image.filepath).name
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'CCA-Mars-Transport.blend'),compress=True)
    print('ROCKET_REBUILT',json.dumps(stats),flush=True)


if __name__=='__main__':main()
