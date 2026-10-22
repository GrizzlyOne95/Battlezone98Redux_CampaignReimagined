"""Geometry, UV isolation, native behavior and faction armory-routing contracts."""
from pathlib import Path
import hashlib,importlib.util,json,re,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TextureRevamp/nav-pickups';SRC=REF/'original'
spec=importlib.util.spec_from_file_location('faction_pickups',ROOT/'Tools/Build-FactionNavPickups.py')
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
receipt=json.loads((REF/'build.json').read_text());source=json.loads((REF/'sources.json').read_text())
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
count=0
def check(ok,why):
    global count
    assert ok,why
    count+=1
def shipped(path):check(members.get(path.relative_to(ROOT).as_posix())==path.name,'shipping membership: '+path.name)
def settings(text):
    section='';result={}
    for line in text.splitlines():
        line=line.split('//')[0].strip()
        if line.startswith('['):section=line.lower()
        elif '=' in line:
            key,value=line.split('=',1);result[(section,key.strip().lower())]=value.strip().strip('"')
    return result
for name,digest in source['files'].items():check(hashlib.sha256((SRC/name).read_bytes()).hexdigest()==digest,'stock/source pin: '+name)
for name,digest in receipt['masters'].items():check(hashlib.sha256((REF/name).read_bytes()).hexdigest()==digest,'art master receipt: '+name)
check(len(receipt['models'])==28,'four factions times seven source mesh families')
for name,record in receipt['models'].items():
    family=record['source'];path=ROOT/'Assets/Models'/(name+'.mesh');mesh=build.read(path);original=build.read(SRC/(family+'.mesh'))
    check(hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],'model receipt: '+name)
    check(build.geometry(mesh)==build.geometry(original)==record['geometry'],'exact oriented corner geometry, attributes, weights and bounds: '+name)
    check(mesh.skeleton_name==name+'.skeleton','separate rig resource: '+name)
    if family=='apcamr':
        check(len(mesh.submesh_list)==1 and mesh.submesh_list[0].material_name==name,'beacon own material, no new batch')
        check(build.geometry(mesh)==build.geometry(original),'beacon geometry unchanged')
        a=build.values(mesh.submesh_list[0].vertex_data,build.om.VES.TEXTURE_COORDINATES)
        b=build.values(original.submesh_list[0].vertex_data,build.om.VES.TEXTURE_COORDINATES)
        check(np.array_equal(a,b),'beacon original UVs preserved')
    else:
        check(2<=len(mesh.submesh_list)<=3,'at most two bounded additional casing batches')
        check(record['coverage']['badgePanels']<=1,'no per-facet repeated badge tiling')
        if family=='aprock':check(record['coverage']['badgePanels']==0,'triangular fins are plain, never clipped badges')
        for sub in mesh.submesh_list[1:]:
            uv=build.values(sub.vertex_data,build.om.VES.TEXTURE_COORDINATES)
            used=uv[np.unique(sub.index_array)]
            check(np.isfinite(used).all() and used.min()>=.035 and used.max()<=.965,'body UVs remain inside ONE isolated texture, no neighbor-cell bleed')
            check(sub.material_name in (name,name+'/plain') and len(np.unique(np.round(used,5),axis=0))>3,'new material has real texture-space allocation')
            if sub.material_name==name:
                check(build.emblem_fits(uv,sub.index_array.reshape(-1,3)),'entire emblem footprint lies inside mapped geometry, no clipped badge')
            else:check(sub.material_name.endswith('/plain'),'unmarked surfaces use their own quiet material, not cropped frame corners')
        a=build.values(mesh.submesh_list[0].vertex_data,build.om.VES.TEXTURE_COORDINATES)
        b=build.values(original.submesh_list[0].vertex_data,build.om.VES.TEXTURE_COORDINATES)
        check(np.array_equal(a,b),'detail remainder retains wrapped stock UVs')
    shipped(path)
    for ext in ('vdf','skeleton'):
        path=ROOT/'Assets/Models'/(name+'.'+ext)
        check(path.read_bytes()==(SRC/(family+'.'+ext)).read_bytes(),'native moving parts/collision/rig unchanged: '+name)
        shipped(path)
for name,record in receipt['files'].items():
    path=ROOT/'Assets/Textures'/name
    check(hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],'DDS build receipt: '+name)
    check(bc_dds_problem(path.read_bytes(),*record['size']) is None,'full legacy-header mips: '+name)
    if name.startswith('crpk'):check(record['size']==[512,512],'isolated pickup cell has its own full mip chain')
    shipped(path)
for code in build.FACTIONS:
    path=ROOT/'Materials'/('CR_pickups_'+code+'.material');text=path.read_text();shipped(path)
    check('import * from "CR_BZBase.material"' in text,'owned Enhanced/fallback base')
    for family,(stem,quad) in build.FAMILIES.items():
        name=stem+code;check(f'material {name} : CR_BZBase' in text,'all own materials declared')
        if quad is not None:
            check(f'crpk{code}{quad[0]+quad[1]*2}_d.dds' in text,'type-specific isolated panel selected')
    check('set $diffuse "0.45 1 0.4"' in text,'repair casing keeps its green type tint')
    with Image.open(ROOT/'Assets/Textures'/('crnv'+code+'_e.dds')) as image:
        e=np.array(image.convert('RGB'));x,y=np.meshgrid(np.linspace(0,1,1024),np.linspace(0,1,1024))
        allowed=(((x-.084)**2/(.049**2)+(y-.915)**2/(.052**2)<1)|((x-.205)**2/(.049**2)+(y-.915)**2/(.052**2)<1))
        check(e[~allowed].max()<20,'beacon paint/insignia never leaks emissive light')
        check(e[890:980,50:125].max()>100 and e[890:980,170:245].max()>100,'both original lower beacon lamps emit')
for name,record in receipt['odfs'].items():
    path=ROOT/'ODF'/(name+'.odf');original=settings((SRC/record['source']).read_text());active=settings(path.read_text())
    check(len(name)<=8,'legacy ODF ID length')
    check(active.pop(('[gameobjectclass]','basename'))==record['model'],'own model actually selected: '+name)
    original.pop(('[gameobjectclass]','basename'))
    check(active==original,'ALL gameplay, weapon payload, sounds, pickup amounts and costs preserved: '+name)
    check(record['model'] in receipt['models'],'ODF model resolves')
    shipped(path)
routes=json.loads((REF/'routes.json').read_text())
for route in routes:
    path=ROOT/route['path'];baseline=REF/'menus'/path.name
    check(hashlib.sha256(baseline.read_bytes()).hexdigest()==route['sha256'],'armory baseline pin: '+path.name)
    old=settings(baseline.read_text());new=settings(path.read_text());check(old.keys()==new.keys(),'no build slots added/removed')
    for key,value in old.items():
        if re.fullmatch(r'(?:builditem|cannonitem|rocketitem|mortaritem|specialitem)\d+',key[1]) and value in route['sources']:
            record=receipt['odfs'].get(new[key])
            check(record is not None and record['source']==value+'.odf' and record['faction']==build.FACTIONS[route['faction']][0],'faction menu preserves original payload source: '+path.name+' '+key[1])
        else:check(new[key]==value,'unrelated vehicle/armory setting unchanged: '+path.name+' '+key[1])
# Concrete semantic traps from the source audit.
check(settings((ROOT/'ODF/sspammo.odf').read_text())[('[ammopowerupclass]','ammoup')]=='700','CCA ammo keeps 700, not NSDF 500')
check(settings((ROOT/'ODF/sspmini.odf').read_text())[('[weaponpowerupclass]','weaponname')]=='gminisov','CCA minigun stays Soviet, never NSDF weapon')
check(settings((ROOT/'ODF/napmini.odf').read_text())[('[weaponpowerupclass]','weaponname')]=='gminigun','NSDF minigun stays NSDF')
check(receipt['menuRoutes']==len(routes)==40,'all forty source recycler/armory menu variants routed')
# Negative proof: a shifted/tiny triangle cannot hold an intact emblem.
check(not build.emblem_fits(np.array([[0,0],[.1,0],[0,.1]]),np.array([[0,1,2]])),'clipped-emblem fixture is rejected')
print(f'Faction nav/pickups: {count} checks passed')
