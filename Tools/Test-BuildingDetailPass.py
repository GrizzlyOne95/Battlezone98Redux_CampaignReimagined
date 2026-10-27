"""Bounded patch geometry, UV, source-emission, material and package contracts."""
from pathlib import Path
import hashlib,importlib.util,json,re,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import bc_dds_problem
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/BuildingDetailPass'
spec=importlib.util.spec_from_file_location('details',ROOT/'Tools/Build-BuildingDetailPass.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
b=build.patches;count=0
def check(ok,why):
    global count
    assert ok,why
    count+=1
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
members={r['source'].replace('\\','/'):r['runtime'] for r in json.loads((ROOT/'Shipping/shipping.lock.json').read_text())['files']}
def shipped(path):check(members.get(path.relative_to(ROOT).as_posix())==path.name,'shipped resource: '+path.name)
for path,record in json.loads((REF/'sources.json').read_text()).items():
    captured=(ROOT if record.get('externalToReference') else REF)/path
    digest=hashlib.sha256(captured.read_text().encode()).hexdigest() if record.get('normalizedText') else sha(captured)
    check(digest==record['sha256'],'captured source / retained native input: '+path)

def test_overlay(row,source,model_path,old,new,receipt):
    check(model_path.read_bytes()==source.read_bytes(),'animated mesh, every UV, edge list and rig byte stays identical')
    check(bool(new.edge_lists) and len(new.submesh_list)==1,'existing shadow topology and one original batch preserved')
    baseline=json.loads((REF/'original'/(row['model']+'-material.json')).read_text())['text']
    material=ROOT/'Materials'/row['materialFile'];text=material.read_text();shipped(material)
    # Owner decision 2026-10-27: #355's diffuse-derived <stem>_N.dds normal replaces
    # the stock flat normal on these materials. Only that one alias may differ from
    # the baseline; the diffuse alias is still the sole intentional detail-pass edit.
    flatn=re.compile(r'set_texture_alias NormalMap \S+')
    derived=flatn.search(text)
    expected=build.overlay_material(row,baseline)
    check(derived is not None and derived[0].lower().endswith('_n.dds') and 'flat' not in derived[0].lower() and (ROOT/'Assets/Textures'/derived[0].split()[-1]).exists(),'owner-accepted diffuse-derived normal map (2026-10-27)')
    check(flatn.sub('set_texture_alias NormalMap N',text)==flatn.sub('set_texture_alias NormalMap N',expected),'only diffuse alias (and the accepted derived normal) changes; E/S and material constants preserved')
    check(hashlib.sha256(text.encode()).hexdigest()==receipt['materialSha256'],'normalized material hash (repinned with the accepted derived normal, 2026-10-27)')
    sub=old.submesh_list[0];uv=b.values(sub.vertex_data,b.om.VES.TEXTURE_COORDINATES);indices=sub.index_array.reshape(-1,3)
    size=tuple(row['atlasOutputSize']);scale=np.array(size)/row['atlasSize'];changed=np.zeros(size[::-1],bool);claimed=np.zeros(len(indices),bool)
    path=ROOT/'Assets/Textures'/row['diffuseOutput']
    with Image.open(path) as im:actual=np.array(im.convert('RGB')).astype(float)
    for patch in row['patches']:
        key=patch['id'];selected=b.patch_mask(uv,indices,patch['bounds'],row['atlasSize'])
        check(not (selected&claimed).any(),'overlay charts select disjoint triangle sets');claimed|=selected
        check(int(selected.sum())==patch['expectedTriangles']==receipt['coverage'][key]>0,'exact overlay coverage: '+key)
        check(sha(REF/(key+'.png'))==receipt['masters'][key+'.png'],'overlay source art hash')
        box=(np.array(patch['bounds'])*np.tile(scale,2)).astype(int);x0,y0,x1,y1=box;changed[y0:y1,x0:x1]=True
        with Image.open(REF/(key+'.png')) as im:
            check(max((x1-x0)/im.width,(y1-y0)/im.height)<1.15,'overlay stays near authored resolution')
        with Image.open(REF/'original'/(row['model']+'_e.png')) as im:
            normalized=im.convert('RGB').resize(tuple(row['atlasSize']),Image.Resampling.LANCZOS).crop(patch['bounds'])
        with Image.open(REF/patch['emissionSource']) as im:crop_e=im.convert('RGB')
        check(np.array_equal(np.array(normalized),np.array(crop_e)),'original E registration for overlay lamp preservation')
    with Image.open(REF/'original'/(row['model']+'_d.png')) as im:base=np.array(im.convert('RGB').resize(size,Image.Resampling.LANCZOS)).astype(float)
    from scipy.ndimage import binary_dilation
    untouched=~binary_dilation(changed,iterations=4)
    check(np.abs(actual[untouched]-base[untouched]).mean()<3,'unselected atlas charts preserved within BC1 tolerance')
    expected=np.array(build.atlas_image(row)).astype(float)
    check(np.abs(actual-expected).mean()<3,'compiled overlay reproduces authored regions and source lamps')
    check(list(receipt['files'])==[row['diffuseOutput']],'only one atlas D; no duplicate E/N/S or patch atlases')
    record=receipt['files'][path.name]
    check(sha(path)==record['sha256'],'overlay DDS hash')
    check(bc_dds_problem(path.read_bytes(),*size) is None,'overlay BC1 legacy header and all mip levels');shipped(path)

for row in build.recipes():
    name=row['model'];source=REF/'original'/(name+'.mesh');model_path=ROOT/row.get('outputDirectory','Assets/Models')/(name+'.mesh');path=model_path
    old=b.read_mesh(source);new=b.read_mesh(path);receipt=json.loads((REF/row['receipt']).read_text())
    check(sha(source)==receipt['sourceSha256'],'pinned source mesh')
    check(sha(path)==receipt['modelSha256'],'current mesh hash')
    check(b.triangle_contract(old)==b.triangle_contract(new)==receipt['geometry'],'exact oriented geometry/non-UV attributes/weights/bounds/skeleton')
    if row.get('mode')=='atlas-overlay':
        test_overlay(row,source,model_path,old,new,receipt)
        continue
    check(not new.edge_lists and len(new.submesh_list)==3,'two additional batches only; no stale shadow topology')
    shipped(path)
    sub=old.submesh_list[0];uv=b.values(sub.vertex_data,b.om.VES.TEXTURE_COORDINATES);ids=sub.index_array.reshape(-1,3)
    claimed=np.zeros(len(ids),bool);matpath=ROOT/'Materials'/row['materialFile'];text=matpath.read_text();shipped(matpath)
    check('import * from "'+row['sourceMaterialFile']+'"' in text and (ROOT/'Materials'/row['sourceMaterialFile']).exists(),'import names real material script, not merely a material identifier')
    for index,patch in enumerate(row['patches'],1):
        key=patch['id'];box=np.array(patch['bounds']);selected=b.patch_mask(uv,ids,box,row['atlasSize'])
        check(not (selected&claimed).any(),'patches select disjoint original triangles');claimed|=selected
        check(int(selected.sum())==patch['expectedTriangles']==receipt['coverage'][key]>0,'nonzero exact patch coverage: '+key)
        part=new.submesh_list[index]
        check(np.array_equal(part.index_array.reshape(-1,3),ids[selected]),'original triangle order/winding in patch')
        expected=(uv*np.array(row['atlasSize'])-box[:2])/(box[2:]-box[:2])
        actual=b.values(part.vertex_data,b.om.VES.TEXTURE_COORDINATES)
        check(np.allclose(actual,expected,atol=2e-7),'positive affine UV crop preserves tangent orientation')
        used=actual[np.unique(part.index_array)]
        check(np.isfinite(used).all() and used.min()>=0 and used.max()<=1,'drawn UVs remain inside dedicated map')
        check(part.material_name=='CRV/Building/'+key,'patch owns the correct material')
        check(sha(REF/(key+'.png'))==receipt['masters'][key+'.png'],'selected ImageGen master hash')
        with Image.open(REF/(key+'.png')) as im:
            # Minor format resampling only; no claim of invented 4K detail.
            check(max(patch['size'][0]/im.width,patch['size'][1]/im.height)<1.15,'shipping size remains near authored source budget')
        with Image.open(REF/'original'/(key+'_e.png')) as im:source_e=im.convert('RGB').resize(tuple(patch['size']),Image.Resampling.LANCZOS)
        with Image.open(REF/'original'/(name+'_e.png')) as im:
            normalized=im.convert('RGB').resize(tuple(row['atlasSize']),Image.Resampling.LANCZOS).crop(patch['bounds'])
        check(np.array_equal(np.array(normalized),np.array(Image.open(REF/'original'/(key+'_e.png')).convert('RGB'))),'stock E crop uses normalized UVs despite different source D/E dimensions')
        if np.array(source_e).max()>0:
            with Image.open(ROOT/'Assets/Textures'/('crv'+key+'_e.dds')) as im:e=np.array(im.convert('RGB')).astype(float)
            expected_e=np.array(source_e).astype(float)
            check(np.abs(e-expected_e).mean()<3,'source emission retained within BC1 tolerance')
            allowed=np.array(source_e).max(2)>0
            # Compression blocks can extend a lamp by up to three texels.
            from scipy.ndimage import binary_dilation
            check(e[~binary_dilation(allowed,iterations=5)].max()<15,'no invented emitting metal, star or hazard paint')
        else:check('crv'+key+'_e.dds' not in receipt['files'] and 'EmissiveMap black.dds' in text,'dark patch reuses black utility, no duplicate blank map')
        # Owner decision 2026-10-27: diffuse-derived normals (#355) are accepted for
        # these patches, so the material must use its own derived crv<id>_N.dds map.
        check('set_texture_alias NormalMap crv'+key+'_N.dds' in text and (ROOT/'Assets/Textures'/('crv'+key+'_N.dds')).exists(),'owner-accepted diffuse-derived normal map (2026-10-27)')
        area_ratio=np.prod(patch['size'])/np.prod(box[2:]-box[:2]);check(area_ratio>3,'selected close-up surface gains genuine dedicated texture space')
    remainder=new.submesh_list[0]
    check(remainder.material_name==sub.material_name,'untouched remainder keeps original material')
    check(np.array_equal(remainder.index_array.reshape(-1,3),ids[~claimed]),'all other original triangles retained once')
    check(np.array_equal(b.values(remainder.vertex_data,b.om.VES.TEXTURE_COORDINATES),uv),'stock remainder UV bytes unchanged')
    for filename,record in receipt['files'].items():
        path=ROOT/'Assets/Textures'/filename
        check(sha(path)==record['sha256'],'compiled map hash: '+filename)
        check(bc_dds_problem(path.read_bytes(),*record['size']) is None,'legacy BC1 header and complete offline mips')
        shipped(path)
    # Negative proof: the geometry contract rejects an accidental moved vertex.
    bad=b.read_mesh(model_path);part=bad.submesh_list[0];vd=part.vertex_data
    element=vd.vertex_declaration.find_by_semantic(b.om.VES.POSITION);vb=vd.get_vertex_buffer(element.source);vb.set_buffer(bytearray(vb.buffer))
    v=b.values(vd,b.om.VES.POSITION);v[int(part.index_array[0]),0]+=.1
    check(b.triangle_contract(bad)!=b.triangle_contract(old),'negative moved-vertex fixture is rejected')
print(f'Building detail pass: {count} checks passed')
