"""Author the THREE large CCA hulls from CCAfleet3.webp.

The five bottom-right objects are STOCK SCALE COMPARISONS, per the owner;
they are deliberately not recreated. All silhouettes are measured source
polygons. Width, unseen surfaces and recessed engines are interpretations.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys
import bpy
import bmesh
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('carrier_author',ROOT/'Tools/Author-NSDFCarrier.py')
A=importlib.util.module_from_spec(spec);spec.loader.exec_module(A)
SOURCE=ROOT/'References/CCAFleet'
SCALE=.25  # 14.6186m installed svapc / ~59 source px, rounded for concept fidelity.
SHIPS=[
    dict(id='crccarr',name='CCA fork-bow carrier',center=(527,270),span=(49,1007),atlas=2048),
    dict(id='crcred1',name='CCA upper-left red hull',center=(283,88),span=(55,512),atlas=1024),
    dict(id='crcred2',name='CCA upper-right red hull',center=(804,86),span=(550,1057),atlas=1024),
]
current=None
survey=[]


def point(u,v,x=0):
    cu,cv=current['center']
    return x,(cu-u)*SCALE,(cv-v)*SCALE


def solid(label,polygon,depth,mat,taper=None,bevel=.12):
    """Closed extrusion of the surveyed side outline; depth is authored metres.

    Recalculate this connected solid before joining disconnected lamps/cards.
    A depth taper can narrow the prow without changing its surveyed profile.
    """
    verts=[]
    for side in (-1,1):
        for u,v in polygon:
            width=depth*(taper(u) if taper else 1)
            verts.append(point(u,v,side*width))
    n=len(polygon)
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    ob=A.mesh(label,verts,faces,mat)
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    if bevel:
        bpy.context.view_layer.objects.active=ob
        mod=ob.modifiers.new('Small edge catchlight','BEVEL');mod.width=bevel;mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    A.remember(ob)
    survey.append(dict(part=label,outline=polygon,half_width=depth,material=mat))
    return ob


def card(label,poly,depth,mat):
    for side in (-1,1):
        verts=[point(u,v,side*(depth(u) if callable(depth) else depth)) for u,v in poly]
        ob=A.mesh(label,verts,[tuple(range(len(poly)))],mat)
        # Source u increases aft, v down. Set the desired outward side explicitly.
        normal=ob.data.polygons[0].normal
        if normal.x*side<0:
            bm=bmesh.new();bm.from_mesh(ob.data)
            bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()


def rect(label,u0,v0,u1,v1,depth,mat):
    card(label,[(u0,v0),(u1,v0),(u1,v1),(u0,v1)],depth,mat)


def engine_bank(u,positions,radius):
    """Inferred engine exits; stored in game-local metres for future shot FX."""
    # The concept has no stern view. Keep each complete nozzle outside the
    # closed afterbody: burying the emissive throat behind its end cap hides it.
    u+=(radius*.85+.4)/SCALE
    exits=[]
    for x,v in positions:
        _,y,z=point(u,v)
        start=len(A.parts)
        A.lathe('Recessed engine nozzle',[(0,radius),(-radius*.45,radius*.92),
               (-radius*.85,radius*.59)],'Charcoal',20,caps=False)
        for ob in A.parts[start:]:ob.rotation_euler.x=math.pi/2;ob.location=(x,y,z)
        bpy.ops.mesh.primitive_circle_add(vertices=20,radius=radius*.58,fill_type='NGON',
                                        location=(x,y+radius*.83,z))
        ob=bpy.context.object;ob.name='Engine emissive throat';ob.rotation_euler.x=math.pi/2
        ob.data.materials.append(A.materials['Engine']);A.parts.append(ob)
        exits.append([x,z,-y])
    return exits


def palette():
    for name,color,metal,rough in [
        ('Grey',(.24,.255,.26),.42,.55),('Light grey',(.39,.40,.40),.4,.52),
        ('Upper grey',(.30,.315,.32),.4,.5),('Dark grey',(.085,.095,.10),.4,.6),
        ('Charcoal',(.018,.023,.027),.28,.66),('Panel seam',(.035,.041,.045),.3,.6),
        ('Red',(.48,.025,.018),.35,.5),('Red light',(.68,.10,.08),.3,.5),
        ('Red dark',(.20,.011,.009),.4,.55),('Ivory',(.78,.77,.71),.22,.5),
        ('White',(.88,.88,.82),.2,.48),('Warm shadow',(.38,.22,.20),.3,.55)]:
        A.material(name,color,metal,rough)
    A.material('Windows',(.25,.35,.10),.1,.4,(.60,.72,.22))
    A.material('Engine',(.35,.48,.68),.1,.4,(.45,.65,1))
    A.material('Red lamp',(.45,.006,.002),.1,.4,(.8,.015,.005))


def carrier():
    # The nose opening is REAL EMPTY SPACE, not painted onto a solid box.
    taper=lambda u:.18+.82*min(1,max(0,(u-49)/(420-49)))
    solid('Upper fork / stepped dorsal hull',[(49,235),(128,207),(299,176),
        (413,176),(434,182),(553,176),(568,185),(691,176),(707,188),
        (707,214),(420,214),(397,244),(80,251)],28,'Upper grey',taper)
    solid('Lower fork',[(97,287),(397,262),(397,309),(97,302)],28,'Grey',taper)
    solid('Lower fork dark keel',[(97,302),(397,309),(423,351),(397,348)],25,'Dark grey',taper)
    solid('Main rectangular carrier housing',[(420,214),(707,214),(707,304),
        (420,306),(397,325),(397,245)],29,'Grey')
    solid('Carrier lower keel and spar',[(422,306),(707,306),(732,334),
        (707,366),(435,366),(435,342),(422,336)],22,'Dark grey')
    solid('Lower aft spar',[(484,318),(707,310),(733,325),(707,333),(484,333)],31,'Upper grey')
    solid('Large angular afterbody',[(732,241),(831,266),(867,253),(1004,269),
        (1004,328),(868,354),(831,342),(732,371),(707,335),(707,310)],35,'Grey')
    # Upper aft boom is separate from the drive housing, like the reference.
    solid('Upper aft boom root',[(706,159),(733,158),(733,165),(831,165),
        (831,213),(732,215),(707,189)],25,'Dark grey')
    solid('Upper aft boom pale cap',[(732,166),(831,166),(831,171),(905,168),
        (1005,178),(1005,190),(832,191),(732,190)],26,'Light grey')
    solid('Upper aft boom underside',[(732,190),(1005,190),(1005,199),
        (872,214),(832,214),(832,207),(732,214)],24,'Dark grey')
    solid('Forward dorsal antenna rail',[(485,159),(706,159),(706,162),(485,163)],1,'Grey',bevel=0)
    for lo,hi in [(302,415),(438,554),(569,696)]:
        rect('Stepped dorsal armour',lo,177,hi,198,28.15,'Upper grey')
    card('Forejaw bevel strip',[(50,235),(299,202),(397,201),(397,215),(80,243)],lambda u:28*taper(u)+.13,'Light grey')
    # Deep side equipment panel with the offset border visible in the painting.
    rect('Recessed broad rectangular bay',465,227,662,297,29.12,'Panel seam')
    rect('Broad bay inset',470,231,660,296,29.23,'Grey')
    rect('Bay upper catchlight',468,227,662,230,29.26,'Light grey')
    rect('Side bay forward rail',465,229,469,295,29.29,'Dark grey')
    for side in (-1,1):
        for u in (434,558,694):
            x,y,z=point(u,344,side*22.2)
            A.box('Lower hull structural rib',(x,y,z),(.9,1.0,8),'Grey',.08)
    card('Afterbody upper bevel',[(732,242),(831,267),(867,254),(1003,270),
         (1003,290),(867,273),(843,281),(732,255)],35.13,'Light grey')
    card('Afterbody lower bevel',[(732,285),(831,315),(866,313),(1004,314),
         (1004,328),(868,354),(831,342),(732,370),(732,337)],35.14,'Dark grey')
    rect('Aft collar',831,274,844,337,35.25,'Upper grey')
    rect('Small aft collar',956,261,967,320,35.25,'Upper grey')
    # Restrained small-scale lights; the large silhouette stays the focus.
    for u in range(478,658,23):rect('Bay yellow indicators',u,292,u+2,293,29.30,'Windows')
    return engine_bank(1006,[(-16,294),(16,294),(-16,318),(16,318)],3.3)


def red_left():
    solid('Dark lower gunship hull',[(154,98),(438,98),(438,135),(167,135),
         (167,126),(137,119),(137,109)],16,'Charcoal')
    solid('Long needle gun',[(55,110),(136,110),(151,104),(151,122),(136,117),(55,116)],1.2,'Red dark',bevel=.04)
    solid('Faceted red upper bow',[(92,69),(168,51),(215,45),(215,99),
         (117,99),(92,82)],17,'Red',lambda u:.3+.7*min(1,(u-92)/80))
    solid('Pale broad middle body',[(214,61),(439,61),(439,135),(214,135)],15.4,'Ivory')
    solid('Black lower middle band',[(215,99),(438,99),(438,135),(215,135)],15.6,'Charcoal')
    solid('Red front collar',[(167,64),(213,47),(213,135),(167,135)],17.2,'Red dark')
    rect('Bright front collar',168,64,212,99,17.34,'Red')
    solid('Red stepped dorsal housing',[(228,39),(423,39),(431,49),(431,61),
         (354,66),(326,89),(280,89),(241,69),(228,59)],17.8,'Red dark')
    card('Dorsal upper red face',[(232,40),(422,40),(426,56),(249,57)],17.93,'Red')
    card('Dorsal recessed V-shaped side',[(241,63),(353,63),(327,82),(281,82)],17.95,'Red')
    solid('Red aft drive hull',[(440,42),(456,43),(475,55),(475,63),(512,69),
         (512,124),(477,135),(440,135)],17.3,'Red dark')
    card('Red aft shoulders',[(442,57),(458,55),(477,66),(512,74),(512,98),
         (442,98)],17.45,'Red')
    solid('Aft vertical collar',[(438,48),(447,47),(449,135),(439,135)],18,'Red')
    for u in (244,291,344,392):rect('Pale lower vertical rib',u,99,u+8,135,16.18,'White')
    rect('White lower end plate',400,99,437,135,16.20,'Ivory')
    for u in (223,245,270,405):rect('Red hull nav lamp',u,94,u+2,95,15.84,'Windows')
    return engine_bank(513,[(-8,115),(8,115)],2.1)


def red_right():
    taper=lambda u:.20+.8*min(1,(u-551)/200)
    solid('Long pale wedge bow',[(551,84),(630,67),(717,58),(758,54),
         (759,94),(733,99),(716,135),(634,135),(595,95),(551,95)],18,'Warm shadow',
         taper)
    card('Pale upper wedge',[(551,84),(630,69),(717,62),(758,55),(758,93),
         (716,81),(631,81),(592,94),(551,95)],lambda u:18*taper(u)+.12,'Ivory')
    # The pale upright cabin is the defining break between wedge and red stern.
    solid('White cabin',[(759,54),(838,54),(839,94),(759,94)],19,'White')
    rect('Cabin front bevel',759,57,764,86,19.15,'Light grey')
    rect('Cabin side',795,56,838,93,19.14,'Ivory')
    solid('Dark ventral keel',[(756,94),(839,94),(900,121),(834,140),
         (753,133),(714,119),(738,110)],13,'Charcoal')
    solid('Red ventral blister',[(717,115),(776,107),(827,107),(852,118),
         (804,133),(754,128),(717,123)],17,'Red dark')
    card('Ventral red upper edge',[(721,114),(774,104),(827,106),(848,116)],17.14,'Red')
    solid('Angled lower red fitting',[(798,139),(835,128),(841,140),(806,151)],6,'Red',bevel=.07)
    # The raised lip owns the upper rear roof; keep the main roof below it.
    # Duplicating the lip's exact upper outline creates coplanar Z-fighting.
    solid('Red aft command hull',[(840,55),(891,56),(893,73),(996,73),
         (1057,94),(1038,100),(1008,130),
         (981,136),(894,133),(841,96)],21,'Red dark')
    card('Red aft upper facet',[(842,61),(891,59),(893,78),(997,78),(1036,84),
         (1055,91),(1017,106),(900,105),(842,91)],21.13,'Red light')
    card('Red aft lower facet',[(849,97),(901,108),(1016,108),(1034,101),
         (1006,128),(982,132),(895,130)],21.17,'Red')
    solid('Rear top lip',[(996,68),(1034,72),(1057,77),(1057,91),
         (1037,91),(996,79)],22,'Red light')
    solid('Red dorsal sensor stalk',[(859,37),(878,36),(881,56),(857,56)],3,'Red',bevel=.08)
    solid('Asymmetric red dorsal sensor cap',[(829,27),(862,21),(900,21),
         (900,35),(859,39),(829,33)],6,'Red')
    for u in (771,783,811,823):rect('Pale cabin indicators',u,87,u+2,88,19.29,'Windows')
    return engine_bank(1057,[(-10,96),(10,96)],2.2)


def inspect(ob):
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=24
    sc.world=bpy.data.worlds.new('Fleet inspection');sc.world.use_nodes=True
    sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.035,.038,.044,1)
    sc.world.node_tree.nodes['Background'].inputs[1].default_value=.4
    size=max(max(v.co.y for v in ob.data.vertices)-min(v.co.y for v in ob.data.vertices),40)
    for label,loc,power,color in [('Key',(-.9,1.2,1.3),24,(1,.93,.84)),
         ('Fill',(1.3,-.4,.6),9,(.72,.84,1)),('Rim',(-.4,-1,.9),14,(.8,.88,1))]:
        d=bpy.data.lights.new(label,'AREA');d.energy=power*size*size;d.shape='DISK';d.size=size*.8;d.color=color
        lamp=bpy.data.objects.new(label,d);sc.collection.objects.link(lamp);lamp.location=Vector(loc)*size
        lamp.rotation_euler=(-lamp.location).to_track_quat('-Z','Y').to_euler()
    d=bpy.data.cameras.new('Concept side');d.type='ORTHO';d.ortho_scale=size*1.12;d.clip_end=5000
    cam=bpy.data.objects.new('Concept side',d);sc.collection.objects.link(cam);sc.camera=cam
    sc.render.resolution_x=1600;sc.render.resolution_y=600;sc.render.resolution_percentage=100
    for label,loc in [('side',(-2,0,0)),('hero',(-1.8,1.2,.65)),('aft',(-1.6,-1.5,.6))]:
        cam.location=Vector(loc)*size;cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
        if label!='side':sc.render.resolution_y=900
        sc.render.filepath=str(A.SOURCE/(label+'.png'));bpy.ops.render.render(write_still=True)


def overview():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    # Same 0.25m/px scale and sheet positions, not three individually resized ships.
    for ship in SHIPS:
        path=SOURCE/ship['id']/(ship['id']+'.blend')
        with bpy.data.libraries.load(str(path),link=False) as (src,dst):
            dst.objects=[n for n in src.objects if n.startswith('CCA ')]
        ob=next(o for o in dst.objects if o and o.type=='MESH')
        bpy.context.collection.objects.link(ob)
        cu,cv=ship['center'];ob.location=(0,(555-cu)*SCALE,(200-cv)*SCALE)
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=24
    sc.world=bpy.data.worlds.new('Fleet sheet');sc.world.use_nodes=True
    sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.03,.031,.034,1)
    sc.world.node_tree.nodes['Background'].inputs[1].default_value=.5
    for name,loc,power,color in [('Sheet key',(-250,120,300),1800000,(1,.94,.85)),
         ('Sheet fill',(220,-120,150),600000,(.7,.83,1))]:
        d=bpy.data.lights.new(name,'AREA');d.energy=power;d.size=250;d.color=color
        o=bpy.data.objects.new(name,d);sc.collection.objects.link(o);o.location=loc
        o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
    d=bpy.data.cameras.new('Matched reference sheet');d.type='ORTHO';d.ortho_scale=285;d.clip_end=5000
    cam=bpy.data.objects.new('Matched reference sheet',d);sc.collection.objects.link(cam);sc.camera=cam
    cam.location=(-650,0,0);cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
    sc.render.resolution_x=1800;sc.render.resolution_y=760;sc.render.resolution_percentage=100
    sc.render.filepath=str(SOURCE/'fleet-side.png');bpy.ops.render.render(write_still=True)
    # Keep an editable assembly with relative dependencies inside this folder.
    for im in bpy.data.images:
        if im.filepath:
            p=Path(bpy.path.abspath(im.filepath))
            if SOURCE in p.parents:im.filepath='//'+p.relative_to(SOURCE).as_posix()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'CCA-Fleet.blend'),compress=True)


def main():
    global current,survey
    ap=argparse.ArgumentParser();ap.add_argument('--render',action='store_true');ap.add_argument('--only',choices=[s['id'] for s in SHIPS])
    args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    SOURCE.mkdir(parents=True,exist_ok=True)
    if A.CCA_REFERENCE.is_file():assert hashlib.sha256(A.CCA_REFERENCE.read_bytes()).hexdigest()==A.CCA_SHA256
    for ship in SHIPS:
        if args.only and ship['id']!=args.only:continue
        current=ship;survey=[]
        bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
        A.parts=[];A.coarse=[];A.materials={};A.ASSET=ship['id']
        A.SOURCE=SOURCE/ship['id'];A.TEXTURES=A.SOURCE/'Textures';A.TEXTURES.mkdir(parents=True,exist_ok=True)
        A.ATLAS=[('d',ship['atlas'],'DIFFUSE'),('e',ship['atlas'],'EMIT'),('s',512,'EMIT')]
        palette();engines={'crccarr':carrier,'crcred1':red_left,'crcred2':red_right}[ship['id']]()
        ob=A.assemble();ob.name=ship['name'];A.bake(ob)
        stats=A.export_mesh(ob);A.export_native(ob,stats)
        stats.update(asset=ship['id'],name=ship['name'],reference='CCAfleet3.webp',reference_sha256=A.CCA_SHA256,
            scale_metres_per_pixel=SCALE,source_center=ship['center'],source_span=ship['span'],
            role='neutral cinematic fixture; names provisional, no canonical class asserted',
            scale_basis='installed stock svapc length14.6186099m / about59px = .247773; rounded .25m/px',
            axis='Y up; nose -Z; engines +Z',engine_exits=engines,source_polygons=survey,
            inference='width, hidden surfaces, engine bank and small lamps; side outlines measured',
            excluded='all five bottom-right elements are stock unit scale comparisons',
            atlas_sizes={s:n for s,n,_ in A.ATLAS}|{'n':16})
        (A.SOURCE/'geometry.json').write_text(json.dumps(stats,indent=2)+'\n')
        if args.render:inspect(ob)
        for im in bpy.data.images:
            if im.filepath and Path(im.filepath).parent==A.TEXTURES:im.filepath='//Textures/'+Path(im.filepath).name
        bpy.ops.wm.save_as_mainfile(filepath=str(A.SOURCE/(ship['id']+'.blend')),compress=True)
        print('CCA_SHIP_BUILT',ship['id'],stats['triangles'],flush=True)
    if args.render and all((SOURCE/s['id']/(s['id']+'.blend')).is_file() for s in SHIPS):overview()


if __name__=='__main__':main()
