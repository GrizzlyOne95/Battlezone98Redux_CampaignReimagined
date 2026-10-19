"""CCA art direction, secondary construction and paint/normal atlas baking.

Stock svapc/svrecy/svtank/sblpad are visual references only. The material tile
is original generated artwork; every insignia, skin joint and mechanical part here
is authored geometry. Paint is clipped to actual hull facets; there are no raised armour grids.
"""
import math
from pathlib import Path
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


def side_poly(name,yz,mat,s,offset=.022):
    if name!='Flush engraved hull joint':
        return A.project_detail(name,yz,mat,s,offset)
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
                     (y+w/2,z+h/2),(y-w/2,z+h/2)],mat,s,.024)


def seam_side(path,s,width=.045):
    """Sparse flush skin joints, following CCA APC construction, never tiles."""
    for (y0,z0),(y1,z1) in zip(path,path[1:]):
        dy,dz=y1-y0,z1-z0;length=math.hypot(dy,dz)
        if length<.001:continue
        steps=max(1,math.ceil(length/.8));ny,nz=-dz/length*width/2,dy/length*width/2
        for j in range(steps):
            ya,za=y0+dy*j/steps,z0+dz*j/steps;yb,zb=y0+dy*(j+1)/steps,z0+dz*(j+1)/steps
            pts=[side(y,z,s)[0] for y,z in [(ya+ny,za+nz),(yb+ny,zb+nz),(yb-ny,zb-nz),(ya-ny,za-nz)]]
            if any(p is None for p in pts) or max(p.x for p in pts)-min(p.x for p in pts)>1:continue
            side_poly('Flush engraved hull joint',[(ya+ny,za+nz),(yb+ny,zb+nz),(yb-ny,zb-nz),(ya-ny,za-nz)],'Panel seam',s,.026)
    count('flush_joint_paths')


def hatch(y,z,w,h,s):
    c=min(w,h)*.18
    path=[(y-w/2+c,z-h/2),(y+w/2-c,z-h/2),(y+w/2,z-h/2+c),
          (y+w/2,z+h/2-c),(y+w/2-c,z+h/2),(y-w/2+c,z+h/2),
          (y-w/2,z+h/2-c),(y-w/2,z-h/2+c),(y-w/2+c,z-h/2)]
    seam_side(path,s,.065)
    stripe(y+w*.28,z,.18,h*.23,s,'Recess')
    stripe(y+w*.28-.15,z,.10,h*.14,s,'Bare steel')
    count('flush_service_hatches')


def roundel(y,z,r,s):
    # Stock CCA five-point red star in an interrupted circular unit marking.
    for ring,material,outer in [(0,'Mark ivory',r),(1,'Mark red',r*.95)]:
        points=[]
        for i in range(10):
            a=math.pi/2+i*math.pi/5;rr=outer if i%2==0 else outer*.42
            points.append((y+math.cos(a)*rr,z+math.sin(a)*rr))
        side_poly('CCA red-star roundel' if ring else 'CCA star pale keyline',points,material,s,.030+ring*.006)
    for j in range(5):
        pts=[]
        for i in range(13):
            a=j*math.tau/5+.08+i*(math.tau/5-.16)/12
            pts.append((y+math.cos(a)*r*1.17,z+math.sin(a)*r*1.17))
        for i in range(12,-1,-1):
            a=j*math.tau/5+.08+i*(math.tau/5-.16)/12
            pts.append((y+math.cos(a)*r*1.08,z+math.sin(a)*r*1.08))
        side_poly('Interrupted red CCA ring',pts,'Mark red',s,.038)
    count('faction_roundels')


def label(y,z,text,size,s,mat='Mark ivory'):
    p,_=side(y,z,s)
    if p is None:return
    curve=bpy.data.curves.new('CCA hull stencil','FONT');curve.body=text
    curve.size=size;curve.align_x='CENTER';curve.align_y='CENTER';curve.space_character=1.16
    curve.extrude=0;curve.resolution_u=4
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
        if p:q.x=p.x+s*.042;v.co=inverse@q
    ob.select_set(False);count('stencils')


def hazard(y,z,w,h,s):
    stripe(y,z,w,h,s,'Recess')
    # Paint is actual slanted polygons, fitted to the hull and baked into UVs.
    n=max(2,int(w/(h*1.6)))
    step=w/n
    for i in range(n):
        yy=y-w/2+i*step
        side_poly('CCA diagonal safety chevron',[(yy,z-h/2),(yy+step*.43,z-h/2),
            (yy+step*.92,z+h/2),(yy+step*.49,z+h/2)],'Warning ivory',s,.035)
    count('warning_strips')


def vent(y,z,w,h,s):
    p,_=side(y,z,s)
    if p is None:return
    x=p.x+s*.04
    box('Flush radiator lip',(x,y,z),(.06,w+.18,h+.15),'Bare steel',0)
    box('Black recessed radiator well',(x+s*.04,y,z),(.03,w,h),'Recess',0)
    for i in range(max(4,int(w/.42))):
        yy=y-w*.45+i*(w*.9)/(max(4,int(w/.42))-1)
        ob=box('CCA cooling louvre',(x+s*.08,yy,z),(.10,.12,h*.86),'Radiator',0)
        ob.rotation_euler.z=s*.20
    count('radiators')



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



def detail_ship(author,definition):
    global A,tree,ship,detail_counts
    A=author;ship=definition;detail_counts={}
    # A stable baseline BVH excludes details added afterward; surface queries
    # never stack fitted surface details on one another by accident.
    verts=[];faces=[]
    # Paint polygons now lie exactly on the structural facets. Include them
    # so flush markings sit above paint, not underneath its fifteen-mm lift.
    for ob in A.parts:
        bpy.context.view_layer.update();ob.data.calc_loop_triangles()
        offset=len(verts);verts.extend(tuple(ob.matrix_world@v.co) for v in ob.data.vertices)
        faces.extend(tuple(offset+i for i in t.vertices) for t in ob.data.loop_triangles)
    tree=BVHTree.FromPolygons(verts,faces,all_triangles=True)
    materials()
    if ship['id']=='crccarr':carrier_detail()
    elif ship['id']=='crcred1':red1_detail()
    else:red2_detail()
    engine_detail()
    return dict(detail_counts)


def seam_top(path,width=.05):
    for (x0,y0),(x1,y1) in zip(path,path[1:]):
        dx,dy=x1-x0,y1-y0;length=math.hypot(dx,dy)
        if length<.001:continue
        nx,ny=-dy/length*width/2,dx/length*width/2
        n=max(1,math.ceil(length/.8))
        for j in range(n):
            xa,ya=x0+dx*j/n,y0+dy*j/n;xb,yb=x0+dx*(j+1)/n,y0+dy*(j+1)/n
            pts=[top(x,y)[0] for x,y in [(xa+nx,ya+ny),(xb+nx,yb+ny),(xb-nx,yb-ny),(xa-nx,ya-ny)]]
            if any(p is None for p in pts) or max(p.z for p in pts)-min(p.z for p in pts)>.8:continue
            patch('Flush dorsal skin joint',[tuple(p+Vector((0,0,.025))) for p in pts],'Panel seam')
    count('dorsal_joint_paths')


def deck_band(y,w,mat):
    # The APC's narrow ochre body band follows the faceted upper skin.
    heights=[p.z for x in range(-23,24) if (p:=top(x,y)[0]) is not None]
    typical=sorted(heights)[len(heights)//2] if heights else 0
    for x in range(-23,23):
        points=[top(xx,yy)[0] for xx,yy in [(x,y-w/2),(x+1,y-w/2),(x+1,y+w/2),(x,y+w/2)]]
        if any(p is None for p in points):continue
        if max(p.z for p in points)-min(p.z for p in points)>.8 or max(p.z for p in points)>typical+1:continue
        patch('CCA identification band on deck',[tuple(p+Vector((0,0,.04))) for p in points],mat)


def carrier_detail():
    for s in (-1,1):
        # Broad uninterrupted armour: only structural station joints, no grid.
        for y in (-96,-69,39,76):seam_side([(y,-9),(y,4),(y-3,8),(y-3,13)],s)
        seam_side([(-112,-6),(-63,-6),(-54,-2)],s)
        seam_side([(31,7),(64,7),(70,10),(102,10)],s)
        roundel(-90,-8.0,2.5,s);label(-101,-7.5,'CCCP',1.25,s)
        label(50,9.5,'06',1.8,s);roundel(79,9.5,2.0,s)
        # The concept's single broad bay is kept as one integrated door.
        seam_side([(-33,-5),(-33,8),(16,8),(16,-5),(-33,-5)],s,.09)
        for y in (-17,0):seam_side([(y,-4.8),(y,7.8)],s,.06)
        for y in (-29,12):hatch(y,-1,3.0,5.8,s)
        hazard(-8,-5.8,34,.55,s);label(-8,6.5,'06  CARGO',.85,s)
        for y in (-90,-62):vent(y,-.8,4.8,2.0,s)
        vent(41,10.2,4.5,1.7,s)
        for y,z in [(-103,3),(-55,5),(49,-7.5),(91,7.8)]:hatch(y,z,3.2,2.0,s)
        conduit(-49,-27,-15.0,s)
        for y in (-100,-59,-21,13,42,94):amber(y,-9.7 if y<0 else 6.3,s,.9)
        stripe(-61,1.0,.45,12,s,'Ochre');stripe(-61.7,1.0,.14,12,s,'Recess')
    for y in (-94,-61,-31,31,70,97):seam_top([(-24,y),(-13,y),(0,y-4),(13,y),(24,y)])
    for x in (-12,12):
        seam_top([(x,-109),(x,-78),(x*.7,-65)])
        seam_top([(x,28),(x,96)])
        deck_radiator(x,-64,6,12)
    deck_band(-60,.45,'Ochre')
    # Low, wedge-shaped navigation housing echoes the recycler head.
    bridge(0,6,15,5,1.1)


def red1_detail():
    for s in (-1,1):
        for y in (-26,-10,8):seam_side([(y,-10),(y,1.8),(y-2,4.8)],s)
        # A single angular joint through the large red cap, like the Czar wings.
        seam_side([(-29,10),(-16,10),(-12,6.5),(1,6.5)],s)
        roundel(12,.3,1.45,s);label(-26,1.5,'CCCP',.85,s,'Mark red')
        label(31,.7,'14',1.6,s)
        stripe(20,1.0,.42,13,s,'Ochre');stripe(20.6,1,.13,13,s,'Recess')
        for y in (-20,-4):vent(y,-7.1,3.2,2.0,s)
        hatch(-33,1.0,3.2,2.7,s)
        hatch(-43,.2,3.0,4.0,s);hatch(31,-3.5,3.5,2.0,s)
        hazard(-11,-2.6,16,.45,s)
        for y in (-45,-23,12,35):amber(y,-3.0,s,.8)
    for y in (-35,-16,3,29):seam_top([(-16,y),(-8,y),(0,y-3),(8,y),(16,y)])
    for x in (-8,8):
        seam_top([(x,-27),(x,-8),(x*.6,1)])
        deck_radiator(x,-31,5,7)
    deck_band(20,.42,'Ochre')
    # Retain the painting's single low forward spike, with the Czar's stepped
    # barrel sleeve and dark/ivory collar language, rather than invented guns.
    start=len(A.parts)
    A.lathe('CCA forward spike / reinforced probe',[(0,.65),(5,.65),(5.2,.48),(23,.32)],'Bare steel',16)
    for ob in A.parts[start:]:
        ob.rotation_euler.x=-math.pi/2;ob.location=(0,33.5,-6.2);A.remember(ob)
    for yy in (36.0,38.0):box('Probe ivory reinforcement',(0,yy,-6.2),(1.6,.48,1.6),'Ivory',.18)


def red2_detail():
    for s in (-1,1):
        seam_side([(21,-4),(21,1),(24,3)],s)
        seam_side([(40,-1.5),(40,2.2)],s)
        for y in (-45,-25):seam_side([(y,-7),(y,2),(y+3,4)],s)
        roundel(34,-.5,2.2,s);label(19,.5,'CCCP',.85,s,'Mark red')
        label(-32,.3,'08',1.8,s);roundel(-46,-3.2,1.8,s)
        stripe(-10,.7,.44,10,s,'Ochre');stripe(-10.7,.7,.13,10,s,'Recess')
        vent(-23,-4.0,4.3,2.1,s);vent(-49,-3.2,3.5,1.8,s)
        for y,z in [(6,2),(25,-1),(-36,-2)]:hatch(y,z,3.0,2.2,s)
        hazard(-31,-7.0,19,.45,s)
        for y in (-53,-33,-12,5,23,43):amber(y,-5.0,s,.7)
    for y in (-44,-25,23,40):seam_top([(-16,y),(-8,y),(0,y-3),(8,y),(16,y)])
    for x in (-10,10):
        seam_top([(x,-48),(x,-25),(x*.5,-20)])
        seam_top([(x,8),(x,30),(x*.4,42)])
        deck_radiator(x,-29,5,9)
    deck_band(-10,.44,'Ochre')
    # The concept already has a distinctive sensor cap; don't pile a second
    # rectangular bridge and miniature turrets onto its roof.


def deck_radiator(x,y,w,h):
    p,_=top(x,y)
    if p is None:return
    z=p.z+.045
    box('Deck heat-exchanger well',(x,y,z),(w,h,.07),'Recess',0)
    for i in range(max(5,int(h/.50))):
        yy=y-h*.45+i*h*.9/(max(5,int(h/.50))-1)
        box('Heat exchanger fin',(x,yy,z+.08),(w*.94,.14,.10),'Radiator',0)
    for xx in (x-w/2,x+w/2):box('Radiator lip',(xx,y,z+.07),(.08,h+.12,.09),'Bare steel',0)
    count('deck_heat_exchangers')


def bridge(x,y,w,h,height):
    p,_=top(x,y)
    if p is None:return
    z=p.z+.02
    # Broad sloped sides and a narrower roof echo the recycler's upper head.
    verts=[(x+sx*w*.5,y+sy*h*.5,z) for sy in (-1,1) for sx in (-1,1)]
    verts +=[(x+sx*w*.38,y+sy*h*.32,z+height) for sy in (-1,1) for sx in (-1,1)]
    ob=A.mesh('Faceted CCA navigation housing',verts,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],'Plate grey')
    import bmesh
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    # Glazing is one slim integrated band, with structural mullions.
    yy=y+h*.5-h*.18*.48
    box('Recessed navigation glazing',(x,yy+.015,z+height*.48),(w*.7,.035,.24),'Bridge glass',0)
    for xx in (x-w*.23,x,x+w*.23):box('Navigation window mullion',(xx,yy+.04,z+height*.48),(.10,.06,.29),'Dark grey',0)
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
      'Recess':(.010,.015,.019),'Warning ivory':(.65,.63,.52),'Ochre':(.53,.32,.035),
      'Mark ivory':(.74,.70,.59),'Mark red':(.43,.023,.013)}
    for name,c in colours.items():
        mat=A.materials.get(name) or A.material(name,c,.45,.55)
        nt=mat.node_tree;nt.nodes.clear()
        out=nt.nodes.new('ShaderNodeOutputMaterial');bs=nt.nodes.new('ShaderNodeBsdfPrincipled')
        bs.inputs['Metallic'].default_value=.22 if name not in ('Bare steel','Radiator') else .7
        bs.inputs['Roughness'].default_value=.61
        nt.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
        coord=nt.nodes.new('ShaderNodeTexCoord');mapping=nt.nodes.new('ShaderNodeVectorMath');mapping.operation='SCALE'
        mapping.inputs[3].default_value=.075
        nt.links.new(coord.outputs['Object'],mapping.inputs[0])
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=tile;tex.projection='BOX';tex.projection_blend=.20
        nt.links.new(mapping.outputs['Vector'],tex.inputs['Vector'])
        gray=nt.nodes.new('ShaderNodeRGBToBW');nt.links.new(tex.outputs['Color'],gray.inputs[0])
        ramp=nt.nodes.new('ShaderNodeValToRGB')
        # Paint stays smooth across broad facets. Sparse chips break it up;
        # uniform high-contrast grain made the previous pass look like concrete.
        ramp.color_ramp.elements[0].position=.10;ramp.color_ramp.elements[0].color=(*(v*.70 for v in c),1)
        ramp.color_ramp.elements[1].position=.29;ramp.color_ramp.elements[1].color=(*c,1)
        nt.links.new(gray.outputs[0],ramp.inputs['Fac'])
        ao=nt.nodes.new('ShaderNodeAmbientOcclusion');ao.inputs['Distance'].default_value=.85;ao.samples=8
        mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=.63
        nt.links.new(ramp.outputs[0],mix.inputs[1]);nt.links.new(ao.outputs['Color'],mix.inputs[2])
        nt.links.new(mix.outputs[0],bs.inputs['Base Color'])
        rough=nt.nodes.new('ShaderNodeMapRange');rough.inputs['From Min'].default_value=.1;rough.inputs['From Max'].default_value=.6
        rough.inputs['To Min'].default_value=.48;rough.inputs['To Max'].default_value=.64
        nt.links.new(gray.outputs[0],rough.inputs['Value']);nt.links.new(rough.outputs[0],bs.inputs['Roughness'])
        bevel=nt.nodes.new('ShaderNodeBevel');bevel.inputs['Radius'].default_value=.035;bevel.samples=3
        bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.12;bump.inputs['Distance'].default_value=.012
        nt.links.new(gray.outputs[0],bump.inputs['Height']);nt.links.new(bevel.outputs['Normal'],bump.inputs['Normal'])
        nt.links.new(bump.outputs['Normal'],bs.inputs['Normal'])
        mat['export_specular']=.38;mat['cca_paint_tile']=True
    A.material('Amber',(.6,.22,.025),.1,.32,(1,.43,.055))
    A.material('Bridge glass',(.016,.06,.07),.6,.23,(.03,.15,.17))


def bake(ob,source,sizes):
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=4
    sc.render.bake.use_clear=True;sc.render.bake.margin=8
    sc.render.bake.normal_space='TANGENT';sc.render.bake.normal_r='POS_X';sc.render.bake.normal_g='NEG_Y';sc.render.bake.normal_b='POS_Z'
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


def rebake_saved_normal(source,asset):
    """Rebake only the DirectX (-Y) game normal map from the editable geometry."""
    bpy.ops.wm.open_mainfile(filepath=str(source/(asset+'.blend')))
    bpy.context.preferences.filepaths.save_version=0
    ob=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=4
    sc.render.bake.use_clear=True;sc.render.bake.margin=8
    sc.render.bake.normal_space='TANGENT';sc.render.bake.normal_r='POS_X';sc.render.bake.normal_g='NEG_Y';sc.render.bake.normal_b='POS_Z'
    im=bpy.data.images.new(asset+'_n_runtime',width=2048,height=2048,alpha=False);im.colorspace_settings.name='Non-Color'
    nodes=[]
    for mat in ob.data.materials:
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;mat.node_tree.nodes.active=node;nodes.append((mat,node))
    bpy.ops.object.bake(type='NORMAL')
    im.filepath_raw=str(source/'Textures'/(asset+'_n.png'));im.file_format='PNG';im.save()
    for mat,node in nodes:mat.node_tree.nodes.remove(node)
    bpy.ops.wm.save_as_mainfile(filepath=str(source/(asset+'.blend')),compress=True)
    print('DIRECTX_NORMAL_REBAKED',asset,flush=True)
