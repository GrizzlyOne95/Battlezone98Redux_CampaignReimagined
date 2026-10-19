"""Guard the restored fighter's native asset contract, balance and shipping."""
from pathlib import Path
from hashlib import sha256
import io,json,re,struct,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import bwd2_serializer,ogremesh_serializer
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
for old,new in [('hvraz.vdf','crfraz.vdf'),('hvraz.skeleton','crfraz.skeleton')]:
    check(namespaced(files[old].read_bytes())==(ASSETS/new).read_bytes(),'native collision/animation bytes unchanged except part namespace')
for key,path in files.items():
    if key.endswith('.geo'):
        check(namespaced(path.read_bytes())==(ASSETS/('cfr11'+key[5:])).read_bytes(),'every legacy GEO companion is present and geometry unchanged: '+key)
vdf=bwd2_serializer.VDFSerializer(io.BytesIO((ASSETS/'crfraz.vdf').read_bytes())).read()
check(vdf.objcount==12,'complete 12-part VDF')
parts={o.name for o in vdf.primary_objects()}
for hp in ('cfr11GC1','cfr11GC2'):
    check(hp in parts,'original weapon hardpoint survives: '+hp)
def read_mesh(data):return ogremesh_serializer.MeshSerializer(io.BytesIO(data)).read()
old=read_mesh(files['hvraz.mesh'].read_bytes());new=read_mesh((ASSETS/'crfraz.mesh').read_bytes())
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
check(dds[:4]==b'DDS ' and struct.unpack_from('<II',dds,12)==(1024,1024) and struct.unpack_from('<I',dds,80)[0]==0x41 and struct.unpack_from('<I',dds,88)[0]==32,'shipped RGBA8 atlas with engine-generated mipmaps')
lock=json.loads((ROOT/'Shipping/shipping.lock.json').read_text())
members={x['source'].replace('\\','/'):x['runtime'] for x in lock['files']}
shipped=[p for p in ASSETS.iterdir() if p.name.startswith(('crfraz.','cfr11'))]
shipped+=[ROOT/'Assets/Textures/crfraz_d.dds',ROOT/'Materials/crfraz.material',ROOT/'Scripts/CRFuryRoster.lua']
shipped+=[ROOT/'ODF'/f'{n}.odf' for n in ('crfraz','crfpuls','crfp0','crfarc','crfa0')]
for p in shipped:check(members.get(p.relative_to(ROOT).as_posix())==p.name,'shipping admission: '+p.name)
print(f'Fury fighter assets: {checks} checks passed')
