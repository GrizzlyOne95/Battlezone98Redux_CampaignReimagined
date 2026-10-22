"""Texture/UV/rig/package contracts for the reviewed art-pass prototype."""
from pathlib import Path
import importlib.util,io,json,hashlib,re,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'References/TextureRevamp'
count=0
def check(ok,message):
    global count
    assert ok,message
    count+=1
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'Tools'/file)
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
bind=module('texture_bind','Bind-TextureRevamp.py')
build=module('texture_build','Build-TextureRevamp.py')
building=module('building_patches','Build-BuildingTexturePatches.py')
compiled=json.loads((REF/'build.json').read_text())['files']
imported=json.loads((REF/'local-model-import.json').read_text())
baseline=json.loads((REF/'mesh-invariants.json').read_text())
members={x['source'].replace('\\','/'):x['runtime'] for x in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
ship=[]
building_receipt=json.loads((REF/'building-build.json').read_text())
source=REF/'building-sources/sblpad.mesh';target=ROOT/'Assets/Models/sblpad.mesh'
check(hashlib.sha256(source.read_bytes()).hexdigest()==building_receipt['sourceSha256'],'stock building source is hash-pinned')
check(hashlib.sha256(target.read_bytes()).hexdigest()==building_receipt['modelSha256'],'building output hash')
source_mesh=building.read_mesh(source);target_mesh=building.read_mesh(target)
check(building.triangle_contract(source_mesh)==building.triangle_contract(target_mesh)==building_receipt['geometry'],'building oriented triangles, full non-UV attributes, weights and bounds unchanged')
recipe=json.loads((REF/'building-patches.json').read_text())
sub=source_mesh.submesh_list[0];indices=sub.index_array.reshape(-1,3)
uv=building.values(sub.vertex_data,om.VES.TEXTURE_COORDINATES)
claimed=np.zeros(len(indices),dtype=bool)
for patch in recipe['patches']:
    mask=building.patch_mask(uv,indices,patch['bounds'],recipe['atlasSize']);claimed|=mask
    selected=next(s for s in target_mesh.submesh_list if s.material_name=='CRV/Building/'+patch['id'])
    check(selected.index_count//3==int(mask.sum())==patch['expectedTriangles'],'dedicated building patch coverage: '+patch['id'])
    out_uv=building.values(selected.vertex_data,om.VES.TEXTURE_COORDINATES)
    box=patch['bounds'];restored=(out_uv*np.array([box[2]-box[0],box[3]-box[1]])+np.array(box[:2]))/np.array(recipe['atlasSize'])
    referenced=np.unique(selected.index_array)
    check(np.allclose(restored[referenced],uv[referenced],atol=2e-7),'positive affine crop preserves original atlas correspondence: '+patch['id'])
    check(np.isfinite(out_uv[referenced]).all() and out_uv[referenced].min()>-.002 and out_uv[referenced].max()<1.002,'patch referenced UV bounds: '+patch['id'])
    check(np.all(selected.index_array.reshape(-1,3)==indices[mask]),'exact original triangle indices in patch: '+patch['id'])
check(np.array_equal(target_mesh.submesh_list[0].index_array.reshape(-1,3),indices[~claimed]),'unmodified stock remainder: no lost or duplicated triangles')
check(np.array_equal(building.values(target_mesh.submesh_list[0].vertex_data,om.VES.TEXTURE_COORDINATES),uv),'remainder UVs byte-identical')
check(len(target_mesh.submesh_list)==4,'bounded three additional building material batches')
check(all(target_mesh.name_table.get(i)==name for i,name in source_mesh.name_table.items()),'stock submesh names retained')
for extension in ('.sdf','.skeleton'):
    check(not (ROOT/'Assets/Models'/('sblpad'+extension)).exists(),'native building files remain stock: '+extension)
building_material=(ROOT/'Materials/CR_building_patches.material').read_text()
check('import * from "sblpad.material"' in building_material,'building children retain stock CCA parent settings')
for patch in recipe['patches']:
    check(f"material CRV/Building/{patch['id']} : sblpad" in building_material,'active building patch material: '+patch['id'])
for resource in re.findall(r'set_texture_alias\s+\S+\s+(\S+)',building_material):
    check(resource in ('flat_N.dds','black.dds') or (ROOT/'Assets/Textures'/resource).exists(),'building texture resolves: '+resource)
for filename,record in building_receipt['files'].items():
    path=ROOT/'Assets/Textures'/filename
    check(hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],'building texture receipt: '+filename)
    check(bc_dds_problem(path.read_bytes(),*record['size']) is None,'building full legacy-header mip chain: '+filename)
    ship.append(path)
with Image.open(ROOT/'Assets/Textures/crvcca_door_e.dds') as im:a=np.array(im.convert('RGB'))
green=((a[:,:,1]>a[:,:,0]*1.8)&(a[:,:,1]>a[:,:,2]*1.8)&(a[:,:,1]>100)).any(axis=1)
starts=np.flatnonzero(green&~np.r_[False,green[:-1]])
check(len(starts)==4,'door has four matched prominent green emissive indicators')
ship.extend([target,ROOT/'Materials/CR_building_patches.material'])
bdog=json.loads((REF/'bdog-building-build.json').read_text())
source=REF/'building-sources/bblpad.mesh';target=ROOT/'Assets/Models/bblpad.mesh'
source_mesh=building.read_mesh(source);target_mesh=building.read_mesh(target)
check(hashlib.sha256(source.read_bytes()).hexdigest()==bdog['sourceSha256'],'Black Dog stock mesh source pin')
check(hashlib.sha256(target.read_bytes()).hexdigest()==bdog['modelSha256'],'Black Dog mesh build pin')
check(building.triangle_contract(source_mesh)==building.triangle_contract(target_mesh)==bdog['geometry'],'Black Dog positions, normals, all drawn corner attributes and skinning unchanged')
recipe=json.loads((REF/'bdog-pad-patch.json').read_text());patch=recipe['patches'][0]
sub=source_mesh.submesh_list[0];uv=building.values(sub.vertex_data,om.VES.TEXTURE_COORDINATES);indices=sub.index_array.reshape(-1,3)
mask=building.patch_mask(uv,indices,patch['bounds'],recipe['atlasSize'])
check(int(mask.sum())==88 and len(target_mesh.submesh_list)==2,'Black Dog pilot is one bounded 88-triangle additional batch')
check(np.array_equal(target_mesh.submesh_list[0].index_array.reshape(-1,3),indices[~mask]),'Black Dog original remainder triangle indices')
check(np.array_equal(building.values(target_mesh.submesh_list[0].vertex_data,om.VES.TEXTURE_COORDINATES),uv),'Black Dog insignia/exterior remainder UVs untouched')
part=target_mesh.submesh_list[1];out_uv=building.values(part.vertex_data,om.VES.TEXTURE_COORDINATES);box=patch['bounds']
restored=(out_uv*np.array([box[2]-box[0],box[3]-box[1]])+np.array(box[:2]))/np.array(recipe['atlasSize'])
check(np.allclose(restored[np.unique(part.index_array)],uv[np.unique(part.index_array)],atol=2e-7),'Black Dog positive crop mapping corresponds to original source')
check(part.material_name=='CRV/Building/bdog_walkway','Black Dog mesh selects dedicated material')
mat=ROOT/'Materials/CR_bdog_pad_patch.material';text=mat.read_text()
check('import * from "bblpad.material"' in text and ' : bblpad' in text,'Black Dog retains its faction material parent')
for resource in re.findall(r'set_texture_alias\s+\S+\s+(\S+)',text):
    check(resource in ('flat_N.dds','black.dds') or (ROOT/'Assets/Textures'/resource).exists(),'Black Dog patch map resolves')
for filename,record in bdog['files'].items():
    path=ROOT/'Assets/Textures'/filename
    check(hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],'Black Dog map build receipt')
    check(bc_dds_problem(path.read_bytes(),*record['size']) is None,'Black Dog complete mip chain')
    ship.append(path)
ship.extend([target,mat])
for name,digest in json.loads((REF/'preserved-art.json').read_text()).items():
    check(hashlib.sha256((ROOT/'Assets/Textures'/name).read_bytes()).hexdigest()==digest,'approved captured-base colour art unchanged: '+name)
for name,record in compiled.items():
    path=ROOT/'Assets/Textures'/name;raw=path.read_bytes();w,h=record['size']
    check(hashlib.sha256(raw).hexdigest()==record['sha256'],'build receipt: '+name)
    cc=b'DXT5' if record['format']=='BC3_UNORM' else b'DXT1'
    check(bc_dds_problem(raw,w,h,cc) is None,'complete legacy-header mip chain: '+name)
    if name.endswith('_n.dds'):
        with Image.open(path) as image:n=np.asarray(image.convert('RGB'),dtype=np.float32)/127.5-1
        length=np.linalg.norm(n,axis=-1)
        check(np.isfinite(n).all() and (n[:,:,2]>.5).all(),'finite positive-Z normal: '+name)
        check(np.quantile(abs(length-1),.99)<.09,'RGB normal decode length: '+name)
    ship.append(path)
for name in ('cr16cmd','cr16hng','cr16pwr','cr16tow'):
    for ext in ('mesh','sdf','skeleton'):
        # The art pass does not touch any captured-base model or native data.
        check(not (ROOT/'Assets/Models'/(name+'.'+ext)).exists(),'captured-base geometry remains in ModelFixes')
    with Image.open(ROOT/'Assets/Textures'/(name+'_e.dds')) as image:e=np.asarray(image.convert('RGB'))
    check(e[:,:,2].max()>20 and e[:,:,0].mean()<e[:,:,2].mean(),'Fury cyan emission, not stock lamp map: '+name)
for item in imported['files']:
    if not item['path'].endswith(('.geo','.sdf','.skeleton')):continue
    path=ROOT/item['path']
    check(hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],'native geometry/rig unchanged: '+path.name)
    ship.append(path)
coverage=set()
for model in imported['models']:
    name=model['stock'];path=ROOT/'Assets/Models'/(name+'.mesh')
    mesh=oms.MeshSerializer(io.BytesIO(path.read_bytes())).read()
    check(bind.invariant(mesh)==baseline[name],'positions/normals/indices/weights/skeleton unchanged: '+name)
    for sub in mesh.submesh_list:
        if not sub.material_name.startswith('CRV/Interior'):continue
        coverage.add(name)
        vd=sub.vertex_data;el=vd.vertex_declaration.get_texcoord_vertex_element();vb=vd.get_vertex_buffer(el.source)
        uv=np.ndarray((vd.vertex_count,2),dtype='<f4',buffer=vb.buffer,offset=el.offset,strides=(vb.vertex_size,4))
        check(np.isfinite(uv).all() and abs(uv).max()<1000,'finite meter-scale interior UV domain: '+name)
        if sub.material_name!='CRV/InteriorScreen':
            t_el=vd.vertex_declaration.find_by_semantic(om.VES.TANGENT);n_el=vd.vertex_declaration.find_by_semantic(om.VES.NORMAL)
            tvb=vd.get_vertex_buffer(t_el.source);nvb=vd.get_vertex_buffer(n_el.source)
            t=np.ndarray((vd.vertex_count,3),dtype='<f4',buffer=tvb.buffer,offset=t_el.offset,strides=(tvb.vertex_size,4))
            n=np.ndarray((vd.vertex_count,3),dtype='<f4',buffer=nvb.buffer,offset=n_el.offset,strides=(nvb.vertex_size,4))
            check(np.max(abs(np.sum(t*n,axis=1)))<1e-4 and np.max(abs(np.linalg.norm(t,axis=1)-1))<1e-4,'reprojected tangent basis: '+name)
    ship.append(path)
# Negative proof: changing a real vertex must invalidate the geometry guard.
probe=oms.MeshSerializer(io.BytesIO((ROOT/'Assets/Models/obstp1.mesh').read_bytes())).read()
original=bind.invariant(probe);vd=probe.submesh_list[0].vertex_data
el=vd.vertex_declaration.get_position_vertex_element();vb=vd.get_vertex_buffer(el.source)
raw=bytearray(vb.buffer)
position=np.ndarray((vd.vertex_count,3),dtype='<f4',buffer=raw,offset=el.offset,strides=(vb.vertex_size,4))
position[0,0]+=.125;vb.set_buffer(raw)
check(bind.invariant(probe)!=original,'negative regression: geometry mutation is detected')
check(coverage=={'obstp1','obstp2','obstp3','oblema','obheph','obher100','obher200','obher300'},'all eight imported models with interior surfaces are covered')
tart=oms.MeshSerializer(io.BytesIO((ROOT/'Assets/Models/ubtart.mesh').read_bytes())).read()
check([s.material_name for s in tart.submesh_list]==['trld00'],'Tartarus selects its own eye material')
eye=next(x for x in json.loads((REF/'imported-textures.json').read_text()) if x['file']=='trld_d.dds')
check(hashlib.sha256((ROOT/'Assets/Textures/trld_d.dds').read_bytes()).hexdigest()==eye['sourceSha256'],'original eye DDS stays byte-identical')
check(not (REF/'tartarus.png').exists(),'rejected Tartarus redraw is not a deliverable')
ship.append(ROOT/'Assets/Textures/trld_d.dds')
for name,bindings in bind.SELECTORS.items():
    path=ROOT/'Materials'/(name+'.material');text=path.read_text()
    for alias,resource in bindings.items():
        check(re.search(r'set_texture_alias\s+'+alias+r'\s+'+re.escape(resource)+r'\b',text),'active alias: '+name+' '+alias)
    ship.append(path)
for name in ('osp_shared','lme_shared','oth_shared','ovheph','trld','CR_texture_revamp'):
    path=ROOT/'Materials'/(name+'.material');text=path.read_text()
    check('"CR_BZBase.material"' in text,'owned Enhanced/fallback base: '+name)
    for resource in re.findall(r'set_texture_alias\s+\S+\s+(\S+)',text):
        if resource in ('flat.dds','flat_N.dds','black.dds','white.png','black.png'):continue
        check((ROOT/'Assets/Textures'/resource).exists(),'resolved imported texture: '+resource)
    ship.append(path)
# A planar ramp verifies polarity independently of the compiled art.
ramp=np.tile(np.linspace(64,192,128,dtype=np.uint8),(128,1))
n=np.asarray(build.normal_from_height(Image.fromarray(ramp),2))
check(n[64,64,0]<128 and n[64,64,2]>250,'height +U slope produces DirectX negative-X normal')
n=np.asarray(build.normal_from_height(Image.fromarray(ramp.T),2))
check(n[64,64,1]<128,'height +V slope produces DirectX negative-Y normal')
for path in set(ship):
    check(members.get(path.relative_to(ROOT).as_posix())==path.name,'shipping membership: '+path.name)
print(f'Texture revamp: {count} checks passed')
