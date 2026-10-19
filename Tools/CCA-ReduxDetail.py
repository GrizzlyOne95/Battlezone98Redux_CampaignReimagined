"""CCA art direction, secondary construction and paint/normal atlas baking.

Stock svapc/svrecy/svtank/sblpad are visual references only. The material tile
is original generated artwork; every insignia, panel and mechanical part here
is authored geometry. Detail is fitted to the actual hull, not a floating grid.
"""
import math
from pathlib import Path
import random
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A=None
tree=None
ship=None
detail_counts={}


def count(k):detail_counts[k]=detail_counts.get(k,0)+1


def surface(origin,direction):
    p,n,_,_=tree.ray_cast(Vector(origin),Vector(direction),500)
    return p,n


def side(y,z,s):return surface((s*200,y,z),(-s,0,0))
def top(x,y):return surface((x,y,200),(0,0,-1))


def box(name,p,dims,mat,bevel=.08):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p)
    ob=bpy.context.object;ob.name=name;ob.dimensions=dims
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(A.materials[mat])
    if bevel and min(dims)>=.16:
        mod=ob.modifiers.new('CCA hard-surface chamfer','BEVEL');mod.width=bevel;mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    A.parts.append(ob);return ob


def patch(name,coords,mat):
    ob=A.mesh(name,coords,[tuple(range(len(coords)))],mat)
    # Geometry winding is chosen at each caller, never globally recalculated.
    return ob


def fitted_plate(name,points,normal,mat,thickness=.12):
    """Closed chamfered plate follows an inclined hull instead of floating."""
    pts=[Vector(p) for p in points];n=Vector(normal)
    verts=[tuple(p+n*d) for d in (0,thickness) for p in pts]
    faces=[(3,2,1,0),(4,5,6,7)]+[(i,(i+1)%4,(i+1)%4+4,i+4) for i in range(4)]
    ob=A.mesh(name,verts,faces,mat)
    import bmesh
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new('Fitted armour chamfer','BEVEL');mod.width=.045;mod.segments=1
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob


def panel_side(y,z,w,h,s,mat='Plate grey',frame=True):
    points=[side(y+dy,z+dz,s)[0] for dy,dz in [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]]
    if any(p is None for p in points):return
    if max(p.x*s for p in points)-min(p.x*s for p in points)>4.0:return
    x=sum(p.x for p in points)/4
    outward=Vector((s,0,0))
    if frame:patch('Armour panel dark gasket',[tuple(p+outward*.035) for p in (points if s>0 else list(reversed(points)))],'Recess')
    inset=[]
    for dy,dz in [(-w/2+.08,-h/2+.08),(w/2-.08,-h/2+.08),(w/2-.08,h/2-.08),(-w/2+.08,h/2-.08)]:
        p,_=side(y+dy,z+dz,s);inset.append(p+outward*.075)
    fitted_plate('Replaceable CCA armour plate',inset,outward,mat)
    count('armour_panels')
    if w>2.4 and h>1.8:
        for dy,dz in [(-w*.38,-h*.34),(w*.38,h*.34)]:
            p,_=side(y+dy,z+dz,s)
            if p:box('Recessed plate fastener',(p.x+s*.217,y+dy,z+dz),(.035,.12,.12),'Bare steel',.025)


def panel_top(x,y,w,h,mat='Plate grey'):
    pts=[top(x+dx,y+dy)[0] for dx,dy in [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]]
    if any(p is None for p in pts):return
    if max(p.z for p in pts)-min(p.z for p in pts)>3.5:return
    z=sum(p.z for p in pts)/4
    patch('Deck armour seam',[tuple(p+Vector((0,0,.03))) for p in pts],'Recess')
    inset=[]
    for dx,dy in [(-w/2+.08,-h/2+.08),(w/2-.08,-h/2+.08),(w/2-.08,h/2-.08),(-w/2+.08,h/2-.08)]:
        p,_=top(x+dx,y+dy)
        if p is None:return
        inset.append(p+Vector((0,0,.08)))
    fitted_plate('Fitted deck armour tile',inset,(0,0,1),mat)
    count('deck_panels')


def side_poly(name,yz,mat,s,offset=.35):
    points=[]
    for y,z in yz:
        p,_=side(y,z,s)
        if p is None:return
        p.x+=s*offset;points.append(tuple(p))
    # In YZ, (right,up) has normal +X.
    if s<0:points.reverse()
    return patch(name,points,mat)


def stripe(y,z,w,h,s,mat='Warning ivory'):
    return side_poly('CCA painted stripe',[(y-w/2,z-h/2),(y+w/2,z-h/2),
                     (y+w/2,z+h/2),(y-w/2,z+h/2)],mat,s,.38)


def roundel(y,z,r,s):
    # Stock CCA five-point red star in an interrupted circular unit marking.
    for ring,material,outer in [(0,'Mark ivory',r),(1,'Mark red',r*.87)]:
        points=[]
        for i in range(10):
            a=math.pi/2+i*math.pi/5;rr=outer if i%2==0 else outer*.42
            points.append((y+math.cos(a)*rr,z+math.sin(a)*rr))
        side_poly('CCA red-star roundel' if ring else 'CCA star pale keyline',points,material,s,.41+ring*.025)
    for j in range(5):
        pts=[]
        for i in range(13):
            a=j*math.tau/5+.08+i*(math.tau/5-.16)/12
            pts.append((y+math.cos(a)*r*1.17,z+math.sin(a)*r*1.17))
        for i in range(12,-1,-1):
            a=j*math.tau/5+.08+i*(math.tau/5-.16)/12
            pts.append((y+math.cos(a)*r*1.08,z+math.sin(a)*r*1.08))
        side_poly('Interrupted red CCA ring',pts,'Mark red',s,.45)
    count('faction_roundels')


def label(y,z,text,size,s,mat='Mark ivory'):
    p,_=side(y,z,s)
    if p is None:return
    curve=bpy.data.curves.new('CCA hull stencil','FONT');curve.body=text
    curve.size=size;curve.align_x='CENTER';curve.align_y='CENTER';curve.space_character=1.16
    curve.extrude=0;curve.resolution_u=1
    ob=bpy.data.objects.new('Painted CCA stencil '+text,curve);bpy.context.collection.objects.link(ob)
    # Font lies in XY, local X runs along the hull, local Y up, normal outward.
    from mathutils import Matrix
    basis=Matrix(((0,0,s),(s,0,0),(0,1,0)))
    ob.rotation_euler=basis.to_euler();ob.location=(p.x+s*.48,y,z)
    curve.materials.append(A.materials[mat])
    bpy.context.view_layer.objects.active=ob;ob.select_set(True)
    bpy.ops.object.convert(target='MESH');ob=bpy.context.object;A.parts.append(ob)
    bpy.context.view_layer.update();world=ob.matrix_world.copy();inverse=world.inverted()
    for v in ob.data.vertices:
        q=world@v.co;p,_=side(q.y,q.z,s)
        if p:q.x=p.x+s*.55;v.co=inverse@q
    ob.select_set(False);count('stencils')


def hazard(y,z,w,h,s):
    stripe(y,z,w,h,s,'Recess')
    # Paint is actual slanted polygons, fitted to the hull and baked into UVs.
    n=max(2,int(w/(h*1.6)))
    step=w/n
    for i in range(n):
        yy=y-w/2+i*step
        side_poly('CCA diagonal safety chevron',[(yy,z-h/2),(yy+step*.43,z-h/2),
            (yy+step*.92,z+h/2),(yy+step*.49,z+h/2)],'Warning ivory',s,.43)
    count('warning_strips')


def vent(y,z,w,h,s):
    p,_=side(y,z,s)
    if p is None:return
    x=p.x+s*.30
    box('Radiator recessed surround',(x,y,z),(.24,w+.5,h+.4),'Bare steel',.13)
    box('Black recessed radiator well',(x+s*.14,y,z),(.12,w,h),'Recess',.07)
    for i in range(max(4,int(w/.42))):
        yy=y-w*.45+i*(w*.9)/(max(4,int(w/.42))-1)
        ob=box('CCA cooling louvre',(x+s*.24,yy,z),(.22,.16,h*.86),'Radiator',.035)
        ob.rotation_euler.z=s*.20
    count('radiators')


def port(y,z,r,s):
    p,_=side(y,z,s)
    if p is None:return
    start=len(A.parts)
    A.lathe('Round pressure hatch',[(0,r),(.12,r),(.22,r*.86),(.23,r*.78)],'Bare steel',24)
    A.lathe('Recessed hatch centre',[(.24,r*.75),(.27,r*.75)],'Recess',24)
    for ob in A.parts[start:]:ob.rotation_euler.y=s*math.pi/2;ob.location=(p.x+s*.35,y,z)
    box('Hatch locking bar',(p.x+s*.65,y,z),(.10,r*1.1,.15),'Ivory',.025)
    count('pressure_hatches')


def conduit(y0,y1,z,s):
    # Two exposed pipes protected by recessed dark equipment trough.
    p,_=side((y0+y1)/2,z,s)
    if p is None:return
    x=p.x+s*.42;length=abs(y1-y0)
    box('Protected conduit channel',(x,(y0+y1)/2,z),(.18,length,1.25),'Recess',.09)
    for dz in (-.28,.28):
        start=len(A.parts)
        A.lathe('CCA hydraulic / power conduit',[(0,.12),(length,.12)],'Bare steel',10)
        ob=A.parts[start];ob.rotation_euler.x=math.pi/2;ob.location=(x+s*.18,max(y0,y1),z+dz)
    for yy in [min(y0,y1)+i*4 for i in range(int(length/4)+1)]:
        box('Conduit retaining clamp',(x+s*.25,yy,z),(.12,.22,1.0),'Plate grey',.04)
    count('conduit_runs')


def amber(y,z,s,width=1.0):
    p,_=side(y,z,s)
    if p is None:return
    box('Armoured lamp bezel',(p.x+s*.40,y,z),(.22,width+.25,.65),'Bare steel',.08)
    box('CCA amber running lamp',(p.x+s*.53,y,z),(.05,width,.32),'Amber',.05)
    count('lamps')


def turret_top(x,y,size=1.0):
    p,_=top(x,y)
    if p is None:return
    # Compact point-defense fitting, subordinate to the concept silhouette.
    z=p.z;start=len(A.parts)
    A.lathe('Point-defence ring',[(0,1.1*size),(.22*size,1.1*size)],'Bare steel',16)
    for ob in A.parts[start:]:ob.location=(x,y,z+.13)
    box('Small armoured point-defence cupola',(x,y,z+.72*size),(1.65*size,2.1*size,1.1*size),'Plate grey',.25*size)
    for dx in (-.32,.32):
        ob=box('Point defence barrel',(x+dx*size,y+1.4*size,z+.80*size),(.18*size,2.0*size,.18*size),'Bare steel',.03)
    count('point_defence_fittings')


def detail_ship(author,definition):
    global A,tree,ship,detail_counts
    A=author;ship=definition;detail_counts={}
    # A stable baseline BVH excludes details added afterward; surface queries
    # never stack one panel on another by accident.
    verts=[];faces=[]
    bpy.context.view_layer.update()
    for ob in A.parts:
        offset=len(verts);ob.data.calc_loop_triangles()
        verts.extend(tuple(ob.matrix_world@v.co) for v in ob.data.vertices)
        faces.extend(tuple(offset+i for i in t.vertices) for t in ob.data.loop_triangles)
    tree=BVHTree.FromPolygons(verts,faces,all_triangles=True)
    materials()
    if ship['id']=='crccarr':carrier_detail()
    elif ship['id']=='crcred1':red1_detail()
    else:red2_detail()
    engine_detail()
    return dict(detail_counts)


def carrier_detail():
    # Large bay: an actual framed loading aperture / shutter assembly with
    # rails, segmented leaves, warning sill and maintenance access below it.
    for s in (-1,1):
        for y in range(-31,15,6):
            for z in (-.5,5.2):panel_side(y,z,5.6,5.2,s,'Ivory' if y%12 else 'Plate grey')
        for y in range(32,99,7):
            panel_side(y,10.0,6.6,3.8,s,'Plate grey')
            panel_side(y,5.5,6.6,3.6,s,'Grey')
        for y in range(38,99,7):panel_side(y,-7.7,6.6,3.2,s,'Dark grey')
        for y in range(-109,-54,7):
            for z in (-8.5,-2,4.5):panel_side(y,z,6.5,5.7,s,'Plate grey' if z>0 else 'Dark grey')
        # Put the main ship identity on a clean broad shoulder, not the hangar.
        roundel(-78,4.8,3.1,s);label(-91,4.2,'CCCP',1.6,s)
        label(50,8.3,'K-06',2.2,s);roundel(78,9.5,2.0,s)
        # Shutter teeth occupy a dedicated dark service bay distinct from armour.
        p,_=side(-8,0,s)
        if p:
            x=p.x+s*.40
            box('Large carrier shutter recess',(x,-8,0),(.3,35,10.2),'Recess',.30)
            for j in range(11):
                box('Carrier hangar shutter leaf',(x+s*.25,-23+j*3,0),(.18,2.82,9.1),'Dark grey',.12)
                box('Shutter vertical reinforcement',(x+s*.40,-23+j*3,0),(.17,.18,8.8),'Bare steel',.04)
            for zz in (-5.3,5.3):box('Hangar door runner',(x+s*.47,-8,zz),(.42,36, .38),'Bare steel',.10)
            for yy in (-26,10):box('Hangar jamb',(x+s*.46,yy,0),(.45,.6,11.2),'Ivory',.12)
            count('hangar_assemblies')
        hazard(-8,-5.8,34,.85,s);label(-8,6.6,'06   CARGO',1.1,s)
        for y in (-90,-67,42,66):vent(y,-.5 if y<0 else 10,4.2,2.5,s)
        for y in (-99,-54,30,90):port(y,-8.8 if y<0 else -8.0,.8,s)
        conduit(-49,-11,-15.0,s)
        for y in (-100,-81,-59,-24,0,39,72,94):amber(y,-10.2 if y<0 else 6.3,s,.65)
        hazard(-92,-13.8,17,.75,s)
    # Deck scale: long armoured modules and grouped cooling blocks.
    for y in range(-105,106,9):
        for x in (-19,-10,0,10,19):panel_top(x,y,8.2,8.4,'Plate grey' if y<10 else 'Grey')
    for x,y in [(-17,-80),(17,-80),(-15,13),(15,13),(-10,75),(10,75)]:turret_top(x,y,1.0)
    deck_radiator(-12,-64,9,12);deck_radiator(12,-64,9,12)
    deck_radiator(-12,22,8,17);deck_radiator(12,22,8,17)
    bridge(-3,10,15,5,1.3)


def red1_detail():
    for s in (-1,1):
        for y in range(-29,15,5):
            panel_side(y,1.0,4.6,3.6,s,'Ivory')
            panel_side(y,-8.8,4.6,3.7,s,'Dark grey')
        for y in range(-46,-34,4):
            panel_side(y,-1.5,3.6,5.5,s,'Red')
            panel_side(y,3.8,3.6,3.0,s,'Red light')
        for y in range(22,44,4):
            panel_side(y,1.4,3.6,5.7,s,'Red')
            panel_side(y,6.5,3.6,3.2,s,'Red light')
        roundel(-2,2.1,2.3,s);label(-17,2.1,'CCCP  14',1.15,s)
        label(32,.5,'14',1.8,s);hazard(-3,-2.7,32,.70,s)
        # The pale lower ribs remain visual landmarks from the concept.
        for y in (2.5,-9.5,-22.5):vent(y,-7.3,3.4,2.6,s)
        for y in (-37,17):port(y,-7.5,.72,s)
        conduit(-24,10,-10.7,s)
        for y in (-48,-28,-8,12,34):amber(y,-3.5,s,.65)
    for y in range(-42,43,5):
        for x in (-10,0,10):panel_top(x,y,8.2,4.6,'Red' if y<-30 or y>18 else 'Red dark')
    deck_radiator(-8,-32,6,8);deck_radiator(8,-32,6,8)
    for x,y in [(-9,-12),(9,-12)]:turret_top(x,y,.70)
    # A braced, sleeved forward gun rather than a long flat rectangular stick.
    y0,y1=33.0,56.0
    p,_=side(37,-6,1)
    for x in (-.58,.58):
        start=len(A.parts)
        A.lathe('Forward weapon recoil sleeve',[(0,.62),(7,.62),(8,.46),(22,.46)],'Bare steel',16)
        for ob in A.parts[start:]:
            ob.rotation_euler.x=-math.pi/2;ob.location=(x,35,-6.2);A.remember(ob)
    bridge(0,14,9,4,1.0)


def red2_detail():
    for s in (-1,1):
        for y in range(18,56,4):panel_side(y,-.5,3.6,4.3,s,'Ivory')
        for y in range(-57,-14,5):
            panel_side(y,-4.0,4.6,4.5,s,'Red')
            panel_side(y,1.2,4.6,4.4,s,'Red light')
        for y in (-6,0,6):panel_side(y,2.1,5.5,6.0,s,'Ivory')
        roundel(35,-.5,2.4,s);label(20,1,'CCCP',1.25,s)
        label(-33,.9,'08',2.3,s);roundel(-46,-3.9,2.2,s)
        hazard(-31,-7.0,32,.7,s);vent(-15,-3,3.4,2.8,s);vent(-49,-4,3.5,2.5,s)
        for y in (-26,-6,18):port(y,-8.3,.70,s)
        conduit(-45,-20,-10.0,s)
        for y in (-53,-33,-12,4,22,41):amber(y,-5.7,s,.60)
    for y in range(-53,57,5):
        for x in (-10,0,10):panel_top(x,y,8.5,4.5,'Red' if y< -8 else 'Ivory')
    deck_radiator(-12,-29,6,10);deck_radiator(12,-29,6,10)
    for x,y in [(-10,-41),(10,-41),(-10,24),(10,24)]:turret_top(x,y,.65)
    # Concept's dorsal cap now has a functional ribbed sensor face and support.
    bridge(0,2,14,6,1.15)


def deck_radiator(x,y,w,h):
    p,_=top(x,y)
    if p is None:return
    z=p.z+.30
    box('Deck heat-exchanger well',(x,y,z),(w,h,.3),'Recess',.15)
    for i in range(max(5,int(h/.50))):
        yy=y-h*.45+i*h*.9/(max(5,int(h/.50))-1)
        box('Heat exchanger fin',(x,yy,z+.20),(w*.92,.17,.30),'Radiator',.04)
    for xx in (x-w/2,x+w/2):box('Radiator protective rail',(xx,y,z+.35),(.16,h+.3,.25),'Bare steel',.05)
    count('deck_heat_exchangers')


def bridge(x,y,w,h,height):
    p,_=top(x,y)
    if p is None:return
    z=p.z
    box('Armoured bridge / sensor plinth',(x,y,z+height*.5),(w,h,height),'Dark grey',.30)
    box('Bridge overhanging armour',(x,y,z+height+.15),(w+.7,h+.5,.45),'Plate grey',.17)
    for xx in [x-w*.40+i*w*.8/7 for i in range(8)]:
        box('Recessed bridge glazing',(xx,y+h*.51,z+height*.6),(w*.07,.08,.30),'Bridge glass',.04)
    for xx in (x-w*.4,x+w*.4):
        box('Dorsal aerial base',(xx,y,z+height+.5),(.8,.8,.5),'Bare steel',.12)
        box('Dorsal narrow aerial',(xx,y,z+height+1.1),(.11,.11,1.3),'Bare steel',.03)
    count('bridge_sensor_assemblies')


def engine_detail():
    # Fit collars and plumbing around the same fixed attachment exits.
    # Geometry below is visual-only and never added to the coarse native proxy.
    for ob in list(A.parts):
        if ob.name.startswith('Engine emissive throat'):
            x,y,z=ob.location;r=max(v.co.length for v in ob.data.vertices)/.58
            start=len(A.parts)
            A.lathe('CCA drive armoured collar',[(0,r*1.12),(.36,r*1.12),(.48,r*.98)],'Bare steel',32,caps=False)
            for part in A.parts[start:]:part.rotation_euler.x=math.pi/2;part.location=(x,y-r*.65,z)
            for k in range(12):
                a=k*math.tau/12
                part=box('Drive collar radial heat rib',(x+math.cos(a)*r*1.09,y-r*.55,z+math.sin(a)*r*1.09),
                         (.16,.8,.28),'Radiator',.035)
            count('detailed_engine_collars')


def materials():
    tile=bpy.data.images.load(str(Path(__file__).resolve().parents[1]/'References/CCAFleet/Materials/cca_painted_steel.png'),check_existing=True)
    # Work in linear colour, matching the measured muted CCA APC/recycler
    # ivory/charcoal and red unit markings. Core red concept zones are retained.
    colours={'Grey':(.26,.285,.29),'Light grey':(.42,.44,.43),'Upper grey':(.32,.35,.35),
      'Dark grey':(.070,.081,.085),'Charcoal':(.018,.025,.028),
      'Red':(.40,.035,.025),'Red light':(.53,.066,.045),'Red dark':(.19,.021,.017),
      'Ivory':(.72,.70,.63),'White':(.82,.80,.72),'Warm shadow':(.32,.31,.28),
      'Plate grey':(.31,.335,.335),'Bare steel':(.17,.19,.19),'Radiator':(.065,.076,.078),
      'Recess':(.010,.015,.019),'Warning ivory':(.65,.63,.52),
      'Mark ivory':(.74,.70,.59),'Mark red':(.43,.023,.013)}
    for name,c in colours.items():
        mat=A.materials.get(name) or A.material(name,c,.45,.55)
        nt=mat.node_tree;nt.nodes.clear()
        out=nt.nodes.new('ShaderNodeOutputMaterial');bs=nt.nodes.new('ShaderNodeBsdfPrincipled')
        bs.inputs['Metallic'].default_value=.38 if name not in ('Bare steel','Radiator') else .7
        bs.inputs['Roughness'].default_value=.61
        nt.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
        coord=nt.nodes.new('ShaderNodeTexCoord');mapping=nt.nodes.new('ShaderNodeVectorMath');mapping.operation='SCALE'
        mapping.inputs[3].default_value=.20  # one fine paint tile per five metres
        nt.links.new(coord.outputs['Object'],mapping.inputs[0])
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=tile;tex.projection='BOX';tex.projection_blend=.20
        nt.links.new(mapping.outputs['Vector'],tex.inputs['Vector'])
        gray=nt.nodes.new('ShaderNodeRGBToBW');nt.links.new(tex.outputs['Color'],gray.inputs[0])
        ramp=nt.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position=.14;ramp.color_ramp.elements[0].color=(*(v*.45 for v in c),1)
        ramp.color_ramp.elements[1].position=.57;ramp.color_ramp.elements[1].color=(*c,1)
        nt.links.new(gray.outputs[0],ramp.inputs['Fac'])
        ao=nt.nodes.new('ShaderNodeAmbientOcclusion');ao.inputs['Distance'].default_value=.85;ao.samples=8
        mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=.48
        nt.links.new(ramp.outputs[0],mix.inputs[1]);nt.links.new(ao.outputs['Color'],mix.inputs[2])
        nt.links.new(mix.outputs[0],bs.inputs['Base Color'])
        rough=nt.nodes.new('ShaderNodeMapRange');rough.inputs['From Min'].default_value=.1;rough.inputs['From Max'].default_value=.6
        rough.inputs['To Min'].default_value=.42;rough.inputs['To Max'].default_value=.74
        nt.links.new(gray.outputs[0],rough.inputs['Value']);nt.links.new(rough.outputs[0],bs.inputs['Roughness'])
        bevel=nt.nodes.new('ShaderNodeBevel');bevel.inputs['Radius'].default_value=.035;bevel.samples=3
        bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.23;bump.inputs['Distance'].default_value=.028
        nt.links.new(gray.outputs[0],bump.inputs['Height']);nt.links.new(bevel.outputs['Normal'],bump.inputs['Normal'])
        nt.links.new(bump.outputs['Normal'],bs.inputs['Normal'])
        mat['export_specular']=.38;mat['cca_paint_tile']=True
    A.material('Amber',(.6,.22,.025),.1,.32,(1,.43,.055))
    A.material('Bridge glass',(.016,.06,.07),.6,.23,(.03,.15,.17))


def bake(ob,source,sizes):
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=4
    sc.render.bake.use_clear=True;sc.render.bake.margin=8
    sc.render.bake.normal_space='TANGENT';sc.render.bake.normal_r='POS_X';sc.render.bake.normal_g='POS_Y';sc.render.bake.normal_b='POS_Z'
    images={};targets=[]
    for mat in ob.data.materials:
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');mat.node_tree.nodes.active=node;targets.append(node)
    for suffix,kind in [('d','DIFFUSE'),('n','NORMAL'),('e','EMIT'),('s','EMIT')]:
        n=sizes[suffix];im=bpy.data.images.new(A.ASSET+'_'+suffix,width=n,height=n,alpha=False)
        im.colorspace_settings.name='sRGB' if suffix in 'de' else 'Non-Color'
        for node in targets:node.image=im;node.id_data.nodes.active=node
        saved=[]
        if suffix=='s':
            for mat in ob.data.materials:
                nt=mat.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
                color=bs.inputs['Emission Color'];strength=bs.inputs['Emission Strength']
                temp=None
                if bs.inputs['Roughness'].is_linked:
                    temp=nt.nodes.new('ShaderNodeMath');temp.operation='SUBTRACT';temp.inputs[0].default_value=1
                    nt.links.new(bs.inputs['Roughness'].links[0].from_socket,temp.inputs[1]);nt.links.new(temp.outputs[0],color)
                saved.append((nt,color,tuple(color.default_value),strength,strength.default_value,temp))
                color.default_value=(mat.get('export_specular',.18),)*3+(1,);strength.default_value=1
        if kind=='DIFFUSE':bpy.ops.object.bake(type=kind,pass_filter={'COLOR'})
        else:bpy.ops.object.bake(type=kind)
        for nt,color,value,strength,power,temp in saved:
            if temp:nt.nodes.remove(temp)
            color.default_value=value;strength.default_value=power
        im.filepath_raw=str(source/'Textures'/(A.ASSET+'_'+suffix+'.png'));im.file_format='PNG';im.save();images[suffix]=im
    for node in targets:node.image=images['d']
    return images
