"""Build a separate POV-aligned Red Devil cockpit and its authored atlas."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import save_bc
import reddevilcockpit as cockpit
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/RedDevilLegacy'

def textures(recipe):
    result=Image.new('RGB',tuple(recipe['size']),(12,12,14))
    with Image.open(REF/recipe['master']) as source:
        assert list(source.size)==recipe['masterSize']
        for chart in recipe['charts'].values():
            x0,y0,x1,y1=chart['target'];result.paste(source.crop(chart['source']).convert('RGB').resize((x1-x0,y1-y0),Image.Resampling.LANCZOS),(x0,y0))
    a=np.array(result);r,g,b=[a[:,:,i].astype(float) for i in range(3)];glass=np.zeros(r.shape,bool)
    for name in ('console','switch'):
        x0,y0,x1,y1=recipe['charts'][name]['target'];glass[y0:y1,x0:x1]=True
    cyan=glass&(g>70)&(b>70)&(g>r*1.7)&(b>r*1.7)
    amber_roi=np.zeros(r.shape,bool)
    for x0,y0,x1,y1 in recipe['amberGlassRegions']:amber_roi[y0:y1,x0:x1]=True
    amber=amber_roi&(r>145)&(g>85)&(b<70)&(g>r*.35)
    mask=cyan|amber;e=np.zeros_like(a);e[mask]=a[mask]
    return result,Image.fromarray(e),Image.fromarray(mask.astype('uint8')*255)

def build():
    recipe=json.loads((REF/'cockpit.json').read_text());parts,skel,world,eye,shell,meta=cockpit.geometry(REF/'original/bvrdev.mesh',REF/'original/bvrdev.skeleton')
    model,glass=cockpit.mesh_bytes(parts,skel,world,eye,shell)
    outputs={};sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    target=ROOT/'Assets/Models/bvrdev_cockpit.mesh';assert not target.exists() or (REF/'cockpit-build.json').exists(),'refuse unrelated cockpit resource';target.write_bytes(model);outputs[target.relative_to(ROOT).as_posix()]=sha(target)
    target=ROOT/'Assets/Models/bvrdev_cockpit.skeleton';target.write_bytes((REF/'original/bvrdev.skeleton').read_bytes());outputs[target.relative_to(ROOT).as_posix()]=sha(target)
    diffuse,emission,mask=textures(recipe)
    for channel,image in [('d',diffuse),('e',emission)]:
        target=ROOT/'Assets/Textures'/('crvrdcp_'+channel+'.dds');save_bc(image,target);outputs[target.relative_to(ROOT).as_posix()]=sha(target)
    mask.save(REF/'cockpit-glass-mask.png')
    material='''import * from "CR_BZBase.material"

material CRV/RedDevilCockpit : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap crvrdcp_d.dds
    set_texture_alias NormalMap flat_N.dds
    set_texture_alias SpecularMap crvcca_patch_s.dds
    set_texture_alias EmissiveMap crvrdcp_e.dds
}

material CRV/RedDevilForedeck : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap bvrdev_D.dds
    set_texture_alias NormalMap bvrdev_N.dds
    set_texture_alias SpecularMap bvrdev_S.dds
    set_texture_alias EmissiveMap bvrdev_E.dds
}
'''
    target=ROOT/'Materials/CR_reddevil_cockpit.material';target.write_text(material,newline='\n');outputs[target.relative_to(ROOT).as_posix()]=hashlib.sha256(material.encode()).hexdigest()
    receipt=dict(schema=1,masters={recipe['master']:sha(REF/recipe['master'])},outputs=outputs,alignment=meta,glass=glass,
        triangles={name:len(i)//3 for name,(d,i) in parts.items()},glassMaskSha256=sha(REF/'cockpit-glass-mask.png'))
    (REF/'cockpit-build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n')
    print('Red Devil cockpit:',receipt['triangles'],'at',meta['povPosition'],'glass',glass)
if __name__=='__main__':build()
