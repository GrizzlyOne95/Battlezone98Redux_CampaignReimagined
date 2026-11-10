"""Guard the restored fighter's native asset contract, balance and shipping."""
from pathlib import Path
from hashlib import sha256
import io,json,re,struct,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import importlib.util
from bzmodellibs import bwd2_serializer,ogremesh_serializer,ogreskeleton_serializer
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1]
ORIGINAL=ROOT/'References/FuryFighter/original'
ASSETS=ROOT/'Assets/ModelFixes'
checks=0
def check(ok,why):
    global checks
    assert ok,why
    checks+=1
def namespaced(data):return re.sub(b'hra11',b'cfr11',data,flags=re.I)
files={p.name.lower():p for p in ORIGINAL.iterdir()}
manifest=json.loads((ORIGINAL.parent/'provenance.json').read_text())
for name,digest in manifest['original_sha256'].items():
    check(sha256(files[name.lower()].read_bytes()).hexdigest()==digest,'source asset provenance '+name)
check('ISDF' not in manifest['source_folder'],'owner-selected standalone source')
# The wing cannons (Tools/Build-HardpointMounts.py) move cfr11GC1/GC2 to their muzzles
# (References/Hardpoints/crfraz.json, applied by Tools/Build-UnitAnimSlots.py). Those parts must
# sit exactly at the receipt; putting the original values back must give every original byte.
hp={p['name']:p for p in json.loads((ROOT/'References/Hardpoints/crfraz.json').read_text())['parts']}
check(sorted(hp)==['cfr11GC1','cfr11GC2'] and all(p['existing'] and p['parent']==p['owner'] for p in hp.values()),'hardpoint receipt moves only the two existing wing cannon parts')
near=lambda a,b:len(a)==len(b) and all(abs(x-y)<=1e-5 for x,y in zip(a,b))
M12=lambda t:[t.rx,t.ry,t.rz,t.ux,t.uy,t.uz,t.fx,t.fy,t.fz,t.px,t.py,t.pz]
original=namespaced(files['hvraz.vdf'].read_bytes())
old=bwd2_serializer.VDFSerializer(io.BytesIO(original)).read();new=bwd2_serializer.VDFSerializer(io.BytesIO((ASSETS/'crfraz.vdf').read_bytes())).read()
olds=list(old.all_geo_objects(raw=True));news=list(new.all_geo_objects(raw=True))
check(olds and [o.name for o in olds]==[o.name for o in news],'VDF part records unchanged')
seen=[]
for o,n in zip(olds,news):
    if n.name in hp:
        check(n.parent_name()==hp[n.name]['parent'] and near(M12(n.transform),hp[n.name]['matrix']),'VDF hardpoint at its receipt: '+n.name)
        n.transform=o.transform;seen.append(n.name)
check(sorted(set(seen))==sorted(hp),'every receipt hardpoint has VDF records')
for name,p in hp.items():
    m,m0=new.anim_obj.mesh_map[name],old.anim_obj.mesh_map[name]
    keys=list(new.anim_obj.slice_mesh_position_keyframes(m));keys0=list(old.anim_obj.slice_mesh_position_keyframes(m0))
    check(keys and len(keys)==len(keys0) and all(near([k.position.x,k.position.y,k.position.z],p['matrix'][9:]) for k in keys) and near(M12(m.frame_transform),p['matrix']),'rest-only ANIM track follows the receipt: '+name)
    for k,k0 in zip(keys,keys0):k.position=k0.position
    m.frame_transform=m0.frame_transform
out=io.BytesIO();bwd2_serializer.VDFSerializer(out).write(new)
check(out.getvalue()==original,'native collision/animation bytes unchanged except part namespace and the receipt hardpoints')
original=namespaced(files['hvraz.skeleton'].read_bytes())
old=ogreskeleton_serializer.SkeletonSerializer(io.BytesIO(original)).read();new=ogreskeleton_serializer.SkeletonSerializer(io.BytesIO((ASSETS/'crfraz.skeleton').read_bytes())).read()
for name,p in hp.items():
    b,b0=new.get_bone_by_name(name),old.get_bone_by_name(name)
    check(near([b.position.x,b.position.y,b.position.z],p['matrix'][9:]) and vars(b.orientation)==vars(b0.orientation),'skeleton hardpoint bone at its receipt: '+name)
    b.position=b0.position
out=io.BytesIO();ogreskeleton_serializer.SkeletonSerializer(out).write(new)
check(out.getvalue()==original,'skeleton bytes unchanged except part namespace and the receipt hardpoint bones')
for key,path in files.items():
    if key.endswith('.geo'):
        check(namespaced(path.read_bytes())==(ASSETS/('cfr11'+key[5:])).read_bytes(),'every legacy GEO companion is present and geometry unchanged: '+key)
vdf=bwd2_serializer.VDFSerializer(io.BytesIO((ASSETS/'crfraz.vdf').read_bytes())).read()
check(vdf.objcount==12,'complete 12-part VDF')
parts={o.name for o in vdf.primary_objects()}
for gc in ('cfr11GC1','cfr11GC2'):
    check(gc in parts,'original weapon hardpoint survives: '+gc)
def read_mesh(data):return ogremesh_serializer.MeshSerializer(io.BytesIO(data)).read()
# The mesh carries exactly one trailing crfraz_hpmount submesh (the wing cannons); without it every
# original submesh, bound and name must be unchanged.
spec=importlib.util.spec_from_file_location('mounts',ROOT/'Tools/Build-HardpointMounts.py');mounts=importlib.util.module_from_spec(spec);spec.loader.exec_module(mounts)
old=read_mesh(files['hvraz.mesh'].read_bytes());new=read_mesh(mounts.without_mount((ASSETS/'crfraz.mesh').read_bytes(),'crfraz'))
check((old.skeleton_name is None)==(new.skeleton_name is None) and len(old.submesh_list)==len(new.submesh_list),'skeletal flag and submesh count preserved')
check(new.skeleton_name=='crfraz.skeleton','only intended skeleton resource is selected')
for so,sn in zip(old.submesh_list,new.submesh_list):
    check(sn.material_name=='crfraz','only intended material resource is selected')
    check(so.index_count==sn.index_count and bytes(so.get_index_buffer())==bytes(sn.get_index_buffer()),'index data is byte-identical')
    check(so.vertex_data.vertex_count==sn.vertex_data.vertex_count and [vars(e) for e in so.vertex_data.vertex_declaration.vertex_element_list]==[vars(e) for e in sn.vertex_data.vertex_declaration.vertex_element_list],'vertex layout is unchanged')
    for bind,vb in so.vertex_data.vertex_buffer_map.items():
        check(namespaced(bytes(vb.buffer))==bytes(sn.vertex_data.get_vertex_buffer(bind).buffer),'vertex/UV/normal data are byte-identical')
    key=lambda s:[(v.vertex_index,v.bone_index,v.weight) for v in s.bone_assignments()]
    check(key(so)==key(sn),'weights are unchanged')
check(vars(old.aabb)==vars(new.aabb) and old.bound_radius==new.bound_radius and old.name_table==new.name_table,'bounds and submesh names are unchanged')
def odf(name):
    text=(ROOT/'ODF'/f'{name}.odf').read_text()
    return {m[1].lower():m[2].strip().strip('"') for m in re.finditer(r'(?m)^(\w+)\s*=\s*([^/\n]*)',text)}
craft=odf('crfraz');pulse=odf('crfp0');arc=odf('crfa0')
check(craft['basename']=='crfraz' and craft['classlabel']=='wingman','uses its own model and commandable hover process')
check(craft['pilotname']=='' and int(craft['pilotcost'])==0,'no human pilot ejects from alien hull')
check(int(craft['maxhealth'])==2400 and float(craft['velocforward'])==35,'lighter/faster balance baseline')
check(craft['weaponname1']=='crfpuls' and craft['weaponname2']=='crfarc' and craft['weaponmask']=='00011','both custom cannons enabled')
dps=float(pulse['damageballistic'])/float(odf('crfpuls')['shotdelay'])+float(arc['damageballistic'])/float(odf('crfarc')['shotdelay'])
check(abs(dps-210)<0.001,'combined sustained damage below stock 250 DPS Bolt Buddy')
check(float(pulse['shotSpeed'.lower()])*float(pulse['lifespan'])==180,'pulse maximum range 180 m')
check(float(arc['shotspeed'])*float(arc['lifespan'])==160,'arc maximum range 160 m')
dds=(ROOT/'Assets/Textures/crfraz_d.dds').read_bytes()
check(bc_dds_problem(dds,1024) is None,'shipped BC1 atlas with full offline mips')
lock=json.loads((ROOT/'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members={x['source'].replace('\\','/'):x['runtime'] for x in lock['files']}
shipped=[p for p in ASSETS.iterdir() if p.name.startswith(('crfraz.','cfr11'))]
shipped+=[ROOT/'Assets/Textures/crfraz_d.dds',ROOT/'Materials/crfraz.material',ROOT/'Scripts/CRFuryRoster.lua']
shipped+=[ROOT/'ODF'/f'{n}.odf' for n in ('crfraz','crfpuls','crfp0','crfarc','crfa0')]
for p in shipped:check(members.get(p.relative_to(ROOT).as_posix())==p.name,'shipping admission: '+p.name)
print(f'Fury fighter assets: {checks} checks passed')
