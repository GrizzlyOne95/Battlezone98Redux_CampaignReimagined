"""Bounded patch geometry, UV, source-emission, material and package contracts."""
from pathlib import Path
import hashlib,importlib.util,json,sys
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
for path,record in json.loads((REF/'sources.json').read_text()).items():check(sha(REF/path)==record['sha256'],'captured stock input: '+path)
for row in build.recipes():
    name=row['model'];source=REF/'original'/(name+'.mesh');path=ROOT/'Assets/Models'/(name+'.mesh')
    old=b.read_mesh(source);new=b.read_mesh(path);receipt=json.loads((REF/row['receipt']).read_text())
    check(sha(source)==receipt['sourceSha256'],'pinned source mesh')
    check(sha(path)==receipt['modelSha256'],'current mesh hash')
    check(b.triangle_contract(old)==b.triangle_contract(new)==receipt['geometry'],'exact oriented geometry/non-UV attributes/weights/bounds/skeleton')
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
        check('set_texture_alias NormalMap flat_N.dds' in text,'no false diffuse-derived relief')
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
    bad=b.read_mesh(ROOT/'Assets/Models'/(name+'.mesh'));part=bad.submesh_list[0];vd=part.vertex_data
    element=vd.vertex_declaration.find_by_semantic(b.om.VES.POSITION);vb=vd.get_vertex_buffer(element.source);vb.set_buffer(bytearray(vb.buffer))
    v=b.values(vd,b.om.VES.POSITION);v[int(part.index_array[0]),0]+=.1
    check(b.triangle_contract(bad)!=b.triangle_contract(old),'negative moved-vertex fixture is rejected')
print(f'Building detail pass: {count} checks passed')
