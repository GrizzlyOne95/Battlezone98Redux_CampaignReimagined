"""Keep the lore-separated mine models, weapons, placements and package complete."""
from pathlib import Path
from hashlib import sha256
import io,json,re,struct,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh_serializer
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'References/BoltMines'
count=0
def check(ok,why):
    global count
    assert ok,why
    count+=1
def odf(name):
    return {m[1].lower():m[2].strip().strip('"') for m in re.finditer(r'(?m)^(\w+)\s*=\s*([^/\n]*)',(ROOT/'ODF'/f'{name}.odf').read_text())}
def section(name,heading):
    text=(ROOT/'ODF'/f'{name}.odf').read_text()
    body=re.search(r'(?m)^\['+heading+r'\]\s*\n([^\[]*)',text)[1]
    return {m[1].lower():m[2].strip().strip('"') for m in re.finditer(r'(?m)^(\w+)\s*=\s*([^/\n]*)',body)}
def read_mesh(data):return ogremesh_serializer.MeshSerializer(io.BytesIO(data)).read()
manifest=json.loads((REF/'provenance.json').read_text())
for name,digest in manifest['stock_sha256'].items():
    check(sha256((REF/'original'/name).read_bytes()).hexdigest()==digest,'byte-pinned stock asset: '+name)
original=read_mesh((REF/'original/boltmine.mesh').read_bytes())
lock=json.loads((ROOT/'Shipping/shipping.lock.json').read_text())
members={r['source'].replace('\\','/'):r['runtime'] for r in lock['files']}
ship=[]
for name,weapon,ordnance in [('cromine','cromarc','crom0'),('crfmine','crfmarc','crfm0')]:
    mine=odf(name);gun=odf(weapon);shot=odf(ordnance)
    check(mine['basename']==name and mine['classlabel']=='weaponmine','own model, static native mine process')
    check(mine['weaponname']==weapon and gun['ordname']==ordnance,'own complete weapon chain')
    check(float(mine['searchradius'])==100 and float(shot['shotspeed'])*float(shot['lifespan'])==100,'both mines retain 100 m detection and firing range')
    check(mine['maxhealth']=='1000' and mine['scrapvalue']=='0' and shot['ammocost']=='0','clearable persistent defensive mine')
    for ext in ['sdf','skeleton']:
        p=ROOT/'Assets/ModelFixes'/f'{name}.{ext}'
        check(p.read_bytes()==(REF/'original'/f'boltmine.{ext}').read_bytes(),'stock native geometry/animation unchanged')
        ship.append(p)
    mesh=ROOT/'Assets/ModelFixes'/f'{name}.mesh';ship.append(mesh)
    copy=read_mesh(mesh.read_bytes())
    check((copy.skeleton_name is None)==(original.skeleton_name is None),'skeletal flag preserved')
    check(len(copy.submesh_list)==len(original.submesh_list),'same submesh count')
    check(copy.skeleton_name==name+'.skeleton','namespaced skeleton')
    for src,dst in zip(original.submesh_list,copy.submesh_list):
        check(dst.material_name==name,'namespaced material')
        check(src.index_count==dst.index_count and bytes(src.get_index_buffer())==bytes(dst.get_index_buffer()),'indices preserved')
        check([vars(e) for e in src.vertex_data.vertex_declaration.vertex_element_list]==[vars(e) for e in dst.vertex_data.vertex_declaration.vertex_element_list],'vertex layout preserved')
        check(all(bytes(vb.buffer)==bytes(dst.vertex_data.get_vertex_buffer(i).buffer) for i,vb in src.vertex_data.vertex_buffer_map.items()),'UV, normals and vertices preserved')
        weights=lambda sub:[(v.vertex_index,v.bone_index,v.weight) for v in sub.bone_assignments()]
        check(weights(src)==weights(dst),'bone weights preserved')
    check(vars(original.aabb)==vars(copy.aabb) and original.bound_radius==copy.bound_radius and original.name_table==copy.name_table,'all other metadata/bounds preserved')
    material=ROOT/'Materials'/f'{name}.material';ship.append(material)
    text=material.read_text()
    for suffix in ['d','e']:
        texture=ROOT/'Assets/Textures'/f'{name}_{suffix}.dds';ship.append(texture)
        raw=texture.read_bytes()
        check(bc_dds_problem(raw,1024) is None,'own diffuse/emission BC1 atlas with full mips')
        check(texture.name in text,'own atlas is actually selected')
    ship.extend(ROOT/'ODF'/f'{n}.odf' for n in (name,weapon,ordnance))
    ship.append(ROOT/'ODF'/f'{name}.inf')
    hit='cromhit' if name=='cromine' else 'crfmhit'
    check(all(shot[key]==hit for key in ('xplground','xplvehicle','xplbuilding')),'separate faction contact effects for every target type')
    impact=section(hit,'ExplosionClass')
    check(all(float(impact[key])==0 for key in ('damageradius','damageballistic','damageconcussion','damageflame','damageimpact')),'contact effect cannot add hidden area damage')
    check(section(hit,'Core')['startcolor']==section(ordnance,'Render' if name=='cromine' else 'Core')['startcolor'],'contact matches faction arc color')
    ship.append(ROOT/'ODF'/f'{hit}.odf')
check(float(odf('crfm0')['damageballistic'])==100 and float(odf('crom0')['damageballistic'])==40,'Fury damage coefficient is 2.5x Olympian')
check(section('crom0','Render')['renderbase']=='draw_bolt' and section('crfm0','Render')['renderbase']=='draw_multi','focused Olympian arc and forked Fury arc use distinct renderers')
check(section('crom0','Render')['startcolor'].startswith('255 195') and section('crfm0','Core')['startcolor'].startswith('125 225'),'amber versus cyan-blue discharge colors')
check(float(odf('crfm0')['segmentvariance'].split()[0])>float(odf('crom0')['segmentvariance'].split()[0]),'Fury discharge visibly more jagged')
for name in ('crom0','crfm0'):
    check('textureName = "cr_marc.dds"' in (ROOT/'ODF'/f'{name}.odf').read_text(),'both effects use the fresh neutral filament')
ship.append(ROOT/'Assets/Textures/cr_marc.dds')
sprite=ROOT/'Materials/cr_marc.material';ship.append(sprite)
check('material cr_marc.dds : BZSprite/Additive' in sprite.read_text() and 'set_texture_alias DiffuseMap cr_marc.dds' in sprite.read_text(),'native arc/impact renderer can resolve its additive sprite material')
for p in ship:check(members.get(p.relative_to(ROOT).as_posix())==p.name,'shipping admission: '+p.name)
lua=(ROOT/'Scripts/misn05.lua').read_text()
check('BuildObject("cromine", MINE_TEAM, pathName)' in lua and 'BuildObject("boltmine", MINE_TEAM' not in lua,'Mars uses Olympian mines')
check('BuildObject("crfmine",FURY_TEAM,position)' in (ROOT/'Scripts/CRMisn15.lua').read_text(),'Tartarus uses Fury mines')
bzn=(ROOT/'Missions/misn16.bzn').read_bytes()
check(bzn.count(b'PrjID [1] =\r\ncrfmine\r\n')==6 and b'PrjID [1] =\r\nboltmine\r\n' not in bzn,'all six Mission 16 map mines explicitly swapped')
check('cromine' not in (ROOT/'Scripts/CRFuryRoster.lua').read_text(),'later Fury adapter never selects Olympian mines')
print(f'Bolt mine variants: {count} checks passed')
