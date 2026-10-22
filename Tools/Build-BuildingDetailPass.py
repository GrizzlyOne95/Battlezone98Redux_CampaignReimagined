"""Compile bounded building ImageGen patches, retaining animated shadow meshes."""
from pathlib import Path
import hashlib,importlib.util,json,sys
import numpy as np
from PIL import Image,ImageFilter
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/BuildingDetailPass'
spec=importlib.util.spec_from_file_location('building_patches',ROOT/'Tools/Build-BuildingTexturePatches.py')
patches=importlib.util.module_from_spec(spec);spec.loader.exec_module(patches)
def recipes():
    for row in json.loads((REF/'recipe.json').read_text())['models']:
        row.update(sourceDirectory='original',sourceMaterialFile=row['model']+'.material',materialFile='CR_detail_'+row['model']+'.material',receipt=row['model']+'-build.json',recordMasters=True)
        for patch in row['patches']:
            # Even non-glowing patches get black source E; do not infer glow
            # from white stars, hazard paint or brighter generated metal.
            patch.update(emissionSource='original/'+patch['id']+'_e.png',diffuseLampSource='original/'+patch['id']+'_d.png')
        if row.get('mode')=='atlas-overlay':row['materialFile']=row['sourceMaterialFile']
        yield row
def atlas_image(row):
    """Overlay authored charts, preserving untouched pixels and shadow topology."""
    size=tuple(row['atlasOutputSize']);scale=np.array(size)/row['atlasSize']
    with Image.open(REF/'original'/(row['model']+'_d.png')) as im:
        result=im.convert('RGB').resize(size,Image.Resampling.LANCZOS)
    for patch in row['patches']:
        box=np.array(patch['bounds'])*np.tile(scale,2)
        assert np.array_equal(box,box.astype(int)),'overlay bounds must land on texels'
        box=box.astype(int);part_size=tuple(box[2:]-box[:2])
        with Image.open(REF/(patch['id']+'.png')) as im:art=im.convert('RGB').resize(part_size,Image.Resampling.LANCZOS)
        with Image.open(REF/patch['emissionSource']) as im:emission=im.convert('RGB').resize(part_size,Image.Resampling.LANCZOS)
        with Image.open(REF/patch['diffuseLampSource']) as im:lamps=im.convert('RGB').resize(part_size,Image.Resampling.LANCZOS)
        mask=Image.fromarray((np.array(emission).max(2)>10).astype('uint8')*255).filter(ImageFilter.MaxFilter(5))
        art.paste(lamps,(0,0),mask);result.paste(art,tuple(box[:2]))
    return result

def overlay_material(row,source_text):
    old='set_texture_alias DiffuseMap '+row['diffuseAlias']
    assert source_text.count(old)==1,'one exact baseline diffuse alias required'
    return source_text.replace(old,'set_texture_alias DiffuseMap '+row['diffuseOutput'])

def build_atlas_overlay(row):
    name=row['model'];source=REF/'original'/(name+'.mesh')
    target=ROOT/row['outputDirectory']/(name+'.mesh')
    assert target.read_bytes()==source.read_bytes(),'animated/shadow mesh must stay byte-identical'
    baseline=json.loads((REF/'original'/(name+'-material.json')).read_text())['text']
    material=ROOT/'Materials'/row['materialFile'];expected=overlay_material(row,baseline)
    assert material.read_text() in (baseline,expected),'refuse unrelated material edits'
    mesh=patches.read_mesh(source);assert mesh.edge_lists,'overlay fallback must retain shadow data'
    sub=mesh.submesh_list[0];uv=patches.values(sub.vertex_data,patches.om.VES.TEXTURE_COORDINATES);indices=sub.index_array.reshape(-1,3)
    coverage={};claimed=np.zeros(len(indices),bool)
    for p in row['patches']:
        selected=patches.patch_mask(uv,indices,p['bounds'],row['atlasSize'])
        assert not (selected&claimed).any();claimed|=selected
        coverage[p['id']]=int(selected.sum());assert coverage[p['id']]==p['expectedTriangles']
    image=atlas_image(row);output=ROOT/'Assets/Textures'/row['diffuseOutput'];patches.save_bc(image,output)
    material.write_text(expected,newline='\n')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    receipt=dict(schema=1,mode='atlas-overlay',sourceSha256=sha(source),modelSha256=sha(target),geometry=patches.triangle_contract(mesh),coverage=coverage,
        materialSha256=hashlib.sha256(expected.encode()).hexdigest(),
        masters={p['id']+'.png':sha(REF/(p['id']+'.png')) for p in row['patches']},
        files={output.name:dict(size=list(image.size),format='BC1_UNORM',sha256=sha(output))})
    (REF/row['receipt']).write_text(json.dumps(receipt,indent=2)+'\n')
    print(name+': authored atlas regions',coverage,'with mesh/door rig/shadow data byte-identical')

def build():
    for row in recipes():
        if row.get('mode')=='atlas-overlay':build_atlas_overlay(row)
        else:patches.build_one(row,REF)
if __name__=='__main__':build()
