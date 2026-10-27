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
for name,digest in receipt['podMasters'].items():check(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'selected full-atlas pod master: '+name)
for name,digest in receipt['navWeaponMasters'].items():check(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'new owner-requested nav/weapon master: '+name)
repack=json.loads((build.ARTREF/'master-repack.json').read_text())
check(len(repack['records'])==8,'four compact weapon and four compact badge masters replace full duplicate sheets')
for record in repack['records']:
    path=build.ARTREF/record['current']
    check(hashlib.sha256(path.read_bytes()).hexdigest()==record['currentSha256'],'lossless crop master hash: '+path.name)
    with Image.open(path) as image:
        x0,y0,x1,y1=record['crop'];check(image.size==(x1-x0,y1-y0),'compact master retains the exact selected source cell dimensions')
    check(not (build.ARTREF/record['source']).exists(),'unoptimized generation sheet is not duplicated in the current source folder')
hazard_art=json.loads((build.ARTREF/'hazard-repaint.json').read_text())
glow_art=json.loads((build.ARTREF/'glow-repaint.json').read_text())
glow_by_path={row['current']:row for row in glow_art['records']}
check(glow_art['factionDecor']=={'ns':'cyan','bd':'red','cc':'orange','cr':'lime'},'owner faction colour corrections')
for record in glow_art['records']:
    path=ROOT/record['current'];mask_path=ROOT/record['mask']
    check(hashlib.sha256(path.read_bytes()).hexdigest()==record['resultSha256'],'guarded ImageGen glass edit: '+path.name)
    check(hashlib.sha256(mask_path.read_bytes()).hexdigest()==record['maskSha256'],'glass mask pin: '+path.name)
    with Image.open(path) as image:a=np.array(image.convert('RGB'))
    with Image.open(mask_path) as image:mask=np.array(image.convert('L'))>0
    check(mask.shape==a.shape[:2] and hashlib.sha256(a[~mask].tobytes()).hexdigest()==record['unmodifiedRgbSha256'],'all unselected glass-edit RGB pixels remain exact: '+path.name)
check(len(hazard_art['records'])==4,'four faction hazard edits, no per-type duplicate atlases')
for record in hazard_art['records']:
    path=build.ARTREF/record['current']
    followup=glow_by_path[path.relative_to(ROOT).as_posix()]
    check(followup['baseSha256']==record['resultSha256'],'glass edit starts from exact reviewed hazard master: '+path.name)
    with Image.open(path) as image:a=np.array(image.convert('RGB'))
    h,w=a.shape[:2];mask=np.zeros((h,w),bool)
    for box in record['editedRegions']:
        x0,y0,x1,y1=[round(v*(w if i%2==0 else h)) for i,v in enumerate(box)];mask[y0:y1,x0:x1]=True
    with Image.open(ROOT/followup['mask']) as image:glass=np.array(image.convert('L'))>0
    check(not (mask&glass).any(),'subsequent glass edits cannot change hazard paint')
approved=json.loads((REF/'owner-selected-art.json').read_text())
for name,digest in approved['files'].items():
    # The owner explicitly requested a NEW nav paint/light pass after accepting
    # v2. Preserve the accepted v2 maps as historical byte-pinned baselines;
    # geometry/native/UV and the original NSDF masters remain live invariants.
    path=ROOT/name
    if name.startswith('Assets/Textures/crnv'):path=build.ARTREF/'previous-nav-v2'/path.name
    check(hashlib.sha256(path.read_bytes()).hexdigest()==digest,'accepted nav geometry / historical accepted paint remains preserved: '+name)
for code,definition in approved['navMaterials'].items():
    text=(ROOT/'Materials'/('CR_pickups_'+code+'.material')).read_text()
    match=re.search(r'(?ms)^material crnv'+code+r' :[^\n]*\n\{.*?^\}',text)
    # Owner decision 2026-10-27: #355's diffuse-derived normals are accepted on the
    # nav materials. The pin is the owner-approved definition with flat_N.dds
    # replaced by the derived <diffuse stem>_N.dds map; everything else is unchanged.
    derived=re.search(r'DiffuseMap (\S+)_d\.dds',definition)[1]+'_N.dds'
    check(match is not None and match[0]==definition.replace('NormalMap flat_N.dds','NormalMap '+derived) and (ROOT/'Assets/Textures'/derived).exists(),'owner-approved nav material stays unchanged except the accepted derived normal map: '+code)
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
    elif family in ('apammo','aprepa'):
        check(record['coverage'].get('fullUnwrap') is True,'owner-selected complete pod unwrap, no stock-UV remainder')
        check(len(mesh.submesh_list)==1 and mesh.submesh_list[0].material_name==name,'one material / one atlas per stock pod')
        sub=mesh.submesh_list[0];old=original.submesh_list[0]
        uv=build.values(sub.vertex_data,build.om.VES.TEXTURE_COORDINATES)[sub.index_array].reshape(-1,3,2)
        prior=build.values(old.vertex_data,build.om.VES.TEXTURE_COORDINATES)[old.index_array].reshape(-1,3,2)
        expected,metadata=build.full_uv(old,family)
        check(np.isfinite(uv).all() and uv.min()>.005 and uv.max()<.995,'full atlas has finite bounded UVs')
        check(np.allclose(uv,expected,atol=1e-7),'all factions use the selected no-overlap UV charts')
        check(np.all(np.any(abs(uv-prior)>1e-5,axis=(1,2))),'every original pod triangle receives new UVs')
        check(len(uv)==record['coverage']['triangles']==record['coverage']['totalTriangles'],'100 percent triangle coverage')
        check(record['coverage']['charts']==metadata['charts'],'continuous side / top / underside chart membership retained')
    else:
        check(2<=len(mesh.submesh_list)<=3,'at most two bounded additional casing batches')
        check(mesh.submesh_list[0].material_name==name+'/detail','weapon remainder uses faction original-layout art, not stock human material')
        check(record['coverage']['badgePanels']<=1,'no per-facet repeated badge tiling')
        if family=='aprock':check(record['coverage']['badgePanels']==0,'triangular fins are plain, never clipped badges')
        for sub in mesh.submesh_list[1:]:
            uv=build.values(sub.vertex_data,build.om.VES.TEXTURE_COORDINATES)
            used=uv[np.unique(sub.index_array)]
            check(np.isfinite(used).all() and used.min()>=.005 and used.max()<=.995,'body UVs remain bounded inside ONE texture, no neighbor-cell bleed')
            check(sub.material_name in (name,name+'/plain',name+'/rim') and len(np.unique(np.round(used,5),axis=0))>3,'new material has real texture-space allocation')
            if sub.material_name==name:
                check(build.emblem_fits(uv,sub.index_array.reshape(-1,3)),'entire emblem footprint lies inside mapped geometry, no clipped badge')
            elif family=='apspec':
                box=build.weapon_lamp_box(family,name[-2:])
                check(sub.material_name==name+'/rim' and (used>=box[:2]).all() and (used<=box[2:]).all(),'special rim sectors use visible service-port optics, no clipped emblem')
            else:check(sub.material_name.endswith('/plain'),'unmarked surfaces use their own quiet material, not cropped frame corners')
        reconstructed=build.read(SRC/(family+'.mesh'))
        build.reuv_body(reconstructed,family,name,build.FAMILIES[family][1])
        expected,selected,metadata=build.weapon_lamp_uv(reconstructed.submesh_list[0],family,name[-2:])
        prior_xyz=build.values(reconstructed.submesh_list[0].vertex_data,build.om.VES.POSITION)[reconstructed.submesh_list[0].index_array].reshape(-1,3,3)
        expected,hazard,hazard_metadata,warning=build.weapon_hazard_uv(expected,family,prior_xyz)
        sub=mesh.submesh_list[0]
        actual=build.values(sub.vertex_data,build.om.VES.TEXTURE_COORDINATES)[sub.index_array].reshape(-1,3,2)
        prior_sub=reconstructed.submesh_list[0]
        prior=build.values(prior_sub.vertex_data,build.om.VES.TEXTURE_COORDINATES)[prior_sub.index_array].reshape(-1,3,2)
        check(np.array_equal(actual,expected),'weapon lamp faces receive deterministic physical planar UVs')
        check(np.array_equal(actual[~(selected|hazard)],prior[~(selected|hazard)]),'all unselected detail corner UVs remain byte-identical')
        check(metadata['lampUvTriangles']>0 and all(record['coverage'][key]==value for key,value in metadata.items()),'lamp chart coverage receipt')
        box=metadata['lampUvBounds']
        core=np.zeros(len(selected),bool);core[metadata['coreUvRows']]=True
        check((actual[selected&~core]>=box[:2]).all() and (actual[selected&~core]<=box[2:]).all(),'decorative charts stay inside type-specific non-insignia optics')
        box=metadata['coreUvBounds']
        check(core.any() and (actual[core]>=box[:2]).all() and (actual[core]<=box[2:]).all(),'every weapon family has a standard amber core on existing faces')
        u=actual[selected];a=u[:,1]-u[:,0];b=u[:,2]-u[:,0]
        check((abs(a[:,0]*b[:,1]-a[:,1]*b[:,0])>1e-10).all(),'new lamp UV triangles never collapse')
        check(hazard_metadata['hazardUvTriangles']+record['coverage']['casingHazardTriangles']>0 and all(record['coverage'][key]==value for key,value in hazard_metadata.items()),'each weapon type has its own hazard chart receipt')
        low,high=hazard_metadata['hazardUvBand']
        check((actual[warning,: ,0]>=.835-1e-6).all() and (actual[warning,:,0]<=.99+1e-6).all() and (actual[warning,:,1]>low).all() and (actual[warning,:,1]<high).all(),'warning UVs stay inside one padded type-specific swatch')
        u=actual[hazard];a=u[:,1]-u[:,0];b=u[:,2]-u[:,0]
        check((abs(a[:,0]*b[:,1]-a[:,1]*b[:,0])>1e-10).all(),'hazard chart remapping never collapses a triangle')
    shipped(path)
    for ext in ('vdf','skeleton'):
        path=ROOT/'Assets/Models'/(name+'.'+ext)
        check(path.read_bytes()==(SRC/(family+'.'+ext)).read_bytes(),'native moving parts/collision/rig unchanged: '+name)
        shipped(path)
for name,record in receipt['files'].items():
    path=ROOT/'Assets/Textures'/name
    check(hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],'DDS build receipt: '+name)
    check(bc_dds_problem(path.read_bytes(),*record['size']) is None,'full legacy-header mips: '+name)
    if name.startswith(('crpk','crw')):
        full=bool(re.fullmatch(r'(?:crpk(?:ns|bd|cc|cr)[01]|crwp(?:ns|bd|cc|cr))_[de].dds',name))
        check(record['size']==([1024,1024] if full else [512,512]),'full pod atlas or isolated weapon cell dimensions')
    shipped(path)
glow_masks={};glow_colours={}
integration=json.loads((ROOT/'References/TextureRevamp/integration/manifest.json').read_text())
for code in build.FACTIONS:
    path=ROOT/'Materials'/('CR_pickups_'+code+'.material');text=path.read_text();shipped(path)
    check('import * from "CR_BZBase.material"' in text,'owned Enhanced/fallback base')
    for family,(stem,quad) in build.FAMILIES.items():
        name=stem+code;check(f'material {name} : CR_BZBase' in text,'all own materials declared')
        if quad is not None:
            check(f'crpk{code}{quad[0]+quad[1]*2}_d.dds' in text,'type-specific isolated panel selected')
    for type_id in (0,1):
        check(f'crpk{code}{type_id}_surf.dds' not in text,'superseded vent utility maps are no longer selected')
    check('material cram'+code+'/plain' not in text and 'material crhp'+code+'/plain' not in text,'pods have no per-facet overlay material')
    check('set $diffuse "0.45 1 0.4"' not in text,'repair ivory/green art is not flattened by a whole-casing green tint')
    if code=='ns':
        with Image.open(ROOT/'Assets/Textures/crpkns0_d.dds') as image:
            shell=np.array(image.convert('RGB'))[420:520,350:650].mean((0,1))
            check(shell[1]>shell[0]*1.08 and shell[2]>shell[0]*1.08,'NSDF shell is actual-reference petrol blue-green, not olive/brown')
    for type_id in (0,1):
        check(f'EmissiveMap crpk{code}{type_id}_e.dds' in text,'faction-specific pod glow map is bound')
        with Image.open(ROOT/'Assets/Textures'/f'crpk{code}{type_id}_e.dds') as image:
            e=np.array(image.convert('RGB'));lit=e.max(2)>35
            check(lit.sum()>500 and lit.mean()<.28,'authored lamps are visible but not the entire casing')
            glow_masks[(code,type_id)]=lit
            mean=e[lit].mean(0);glow_colours[(code,type_id)]=mean/mean.max()
            decor=e[165:230] if type_id==0 else e[820:940]
            pixels=decor[decor.max(2)>80];check(len(pixels)>30,'visible faction decorative rails')
            median=np.median(pixels,axis=0);expected=np.array(build.DECOR[code],float);expected/=expected.max()
            check(np.linalg.norm(median/median.max()-expected)<.16,'one decorative colour per faction, including retained NSDF cyan rails: '+code)
            r,g,b=e.astype(float).transpose(2,0,1)
            functional=(b>100)&(b>r*2)&(b>g*1.4) if type_id==0 else (g>100)&(g>r*2)&(g>b*2)
            check(functional.sum()>40,'blue ammo / green repair functional core independent of faction: '+code)
            if type_id==0:
                check(e[70:158,500:590].max()<20,'ammo faction badge is not an emitter')
            else:
                check(e[300:425,300:425].max()<20,'repair central faction cap is not an emitter')
                check(e[793:807].max()<20,'repair hazard trim remains nonemitting')
            if type_id==0:check(e[120:145].max()<20,'ammo hazard trim remains nonemitting')
    for family in ('apcann','aprock','apmort','apspec'):
        stem,quad=build.FAMILIES[family];name=stem+code;type_id=quad[0]+2*quad[1]
        check(f'material {name}/detail : {name}' in text,'faction original-layout weapon material exists')
        check(f'DiffuseMap crwp{code}_d.dds' in text and f'EmissiveMap crwp{code}_e.dds' in text,'all weapon types select the same faction detail D/E')
        with Image.open(ROOT/'Assets/Textures'/f'crwp{code}_e.dds') as image:
            e=np.array(image.convert('RGB'));lit=e.max(2)>35
            check(lit.sum()>60 and lit.mean()<.18,'weapon authored optics emit but broad casing/hazard paint stays dark: '+name)
            check(e[:,845:].max()<20,'all four hazard swatches remain nonemitting paint')
        with Image.open(ROOT/'Assets/Textures'/f'crpk{code}{type_id}_e.dds') as image:
            e=np.array(image.convert('RGB'));check(e[135:375,135:375].max()<20,'weapon centered faction badge is paint, not emitter')
    with Image.open(ROOT/'Assets/Textures'/('crnv'+code+'_e.dds')) as image:
        e=np.array(image.convert('RGB'));x,y=np.meshgrid(np.linspace(0,1,1024),np.linspace(0,1,1024))
        allowed=(((x-.084)**2/(.049**2)+(y-.915)**2/(.052**2)<1)|((x-.205)**2/(.049**2)+(y-.915)**2/(.052**2)<1))
        check(e[~allowed].max()<20,'beacon paint/insignia never leaks emissive light')
        check(e[890:980,50:125].max()>100 and e[890:980,170:245].max()>100,'both original lower beacon lamps emit with new faction pattern')
        check(e[125:255,430:550].max()<20,'nav centered badge does not emit')
    boxes=[build.weapon_lamp_box(family,code) for family in ('apcann','aprock','apmort','apspec')]
    check(len({tuple(box) for box in boxes})==4,'all four weapon types use different authored light motifs without duplicate atlases')
    motif_masks=[]
    with Image.open(ROOT/'Assets/Textures'/f'crwp{code}_e.dds') as image:
        e=np.array(image.convert('RGB'))
        for box in boxes:
            x0,y0,x1,y1=[round(v*1024) for v in box]
            lit=e[y0:y1,x0:x1].max(2)>35
            check(lit.any() and lit.mean()<.7,'each weapon type has visible inset optics, never a flat all-glowing chart: '+code+' '+str(box))
            motif_masks.append(np.array(Image.fromarray(lit).resize((64,64),Image.Resampling.NEAREST)))
    for i,a in enumerate(motif_masks):
        for b in motif_masks[i+1:]:
            check((a&b).sum()/max(1,(a|b).sum())<.85,'weapon type light silhouettes differ, not just atlas-region addresses')
    a,b=glow_masks[(code,0)],glow_masks[(code,1)]
    check((a&b).sum()/max(1,(a|b).sum())<.75,'ammo and repair each have distinct faction light footprints')
    with Image.open(build.ARTREF/f'weapon_{code}_master.png') as image:
        masks=[]
        for i in range(4):
            w,h=image.size
            patch=np.array(image.crop((round(w*.835),round(h*(i/4+.015)),round(w*.99),round(h*((i+1)/4-.015)))).resize((64,64),Image.Resampling.LANCZOS).convert('RGB')).astype(float)
            r,g,b=[patch[:,:,j] for j in range(3)]
            bright=(r>140)&(g>140)&(b>120) if code=='ns' else ((r>g*1.35)&(r>70) if code in ('bd','cc') else (r>140)&(g>110)&(b<r*.55))
            check(.03<bright.mean()<.97,'type hazard swatch has a readable two-tone warning pattern')
            masks.append(bright)
        for i,a in enumerate(masks):
            for b in masks[i+1:]:check((a&b).sum()/max(1,(a|b).sum())<.98,'weapon hazard variants are not four copies of the same stripe swatch')
for type_id in (0,1):
    codes=list(build.FACTIONS)
    for i,a in enumerate(codes):
        for b in codes[i+1:]:
            x,y=glow_masks[(a,type_id)],glow_masks[(b,type_id)]
            iou=(x&y).sum()/max(1,(x|y).sum())
            check(iou<.85,'factions have authored distinct lamp footprints, not just recolored generic wraps: '+a+'/'+b)
    check(np.linalg.norm(glow_colours[('ns',type_id)]-glow_colours[('bd',type_id)])>.5,'NSDF and Black Dog emission palettes visibly differ')
for name,record in receipt['odfs'].items():
    path=ROOT/'ODF'/(name+'.odf');original=settings((SRC/record['source']).read_text());active=settings(path.read_text())
    check(len(name)<=8,'legacy ODF ID length')
    check(active.pop(('[gameobjectclass]','basename'))==integration['odfs'][name+'.odf']['model'],'canonical faction model actually selected: '+name)
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
optimization=receipt['atlasOptimization']
check(len(receipt['files'])==optimization['currentMaps']==44,'44 distinct current maps, not 84 duplicated draft resources')
check(optimization['currentBytes']==sum((ROOT/'Assets/Textures'/name).stat().st_size for name in receipt['files']),'optimized runtime byte measurement')
check(optimization['currentBytes']<optimization['previousDraftBytes']*.6,'atlas consolidation saves over forty percent without downsizing surviving maps')
for name in optimization['retiredFiles']:
    check(not (ROOT/'Assets/Textures'/name).exists(),'redundant runtime map retired: '+name)
    check('Assets/Textures/'+name not in members,'retired duplicate is not shipped: '+name)
# Negative proof: a shifted/tiny triangle cannot hold an intact emblem.
check(not build.emblem_fits(np.array([[0,0],[.1,0],[0,.1]]),np.array([[0,1,2]])),'clipped-emblem fixture is rejected')
print(f'Faction nav/pickups: {count} checks passed')
