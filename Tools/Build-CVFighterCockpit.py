"""Reproduce cvfigh's separate cockpit, atlas and physically restricted emission."""
from pathlib import Path
import sys,json,hashlib,argparse
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import save_bc
import cvfighcockpit as cp
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/CVFighterCockpit'
def sha(p):
    data=p.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if p.suffix=='.material' else data).hexdigest()
def textures():
    with Image.open(REF/'atlas-master.png') as master:
        a=np.array(master.convert('RGB'));size=master.size
    assert size==(1254,1254),size
    r,g,b=[a[:,:,i].astype(float) for i in range(3)];instrument=np.zeros(r.shape,bool)
    for key in ('console','switch','engine'):
        x0,y0,x1,y1=cp.CHARTS[key];instrument[y0:y1,x0:x1]=True
    green=instrument&(g>55)&(g>r*1.10)&(g>b*1.5)
    amber_roi=np.zeros(r.shape,bool)
    for x0,y0,x1,y1 in [(106,90,145,115),(106,170,145,194),(158,290,184,315),(1111,89,1148,115),(1111,130,1148,157),(1111,170,1148,194),(482,137,510,164),(746,137,777,164),(535,238,571,266),(663,238,701,266),(280,486,326,510),(370,486,410,510),(1034,484,1069,512),(1034,542,1069,566),(1034,575,1069,602)]:amber_roi[y0:y1,x0:x1]=True
    amber=amber_roi&(r>150)&(g>80)&(b<100);mask=green|amber;e=np.zeros_like(a);e[mask]=a[mask]
    return Image.fromarray(a).resize((1024,1024),Image.Resampling.LANCZOS),Image.fromarray(e).resize((1024,1024),Image.Resampling.LANCZOS),Image.fromarray(mask.astype('uint8')*255)
def build(game):
    source=ROOT/'Assets/ModelFixes/cvfigh.mesh';skel=Path(game)/'BZ_ASSETS/common/models/TRO/cvfigh.skeleton'
    parts,s,world,eye,shell,meta=cp.geometry(source,skel);model,glass=cp.shared.mesh_bytes(parts,s,world,eye,shell,skeleton_name='cvfigh_cockpit.skeleton');outputs={}
    for path,content in [(ROOT/'Assets/Models/cvfigh_cockpit.mesh',model),(ROOT/'Assets/Models/cvfigh_cockpit.skeleton',skel.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    diffuse,emissive,mask=textures()
    for channel,image in [('d',diffuse),('e',emissive)]:
        path=ROOT/'Assets/Textures'/('crvcfcp_'+channel+'.dds');save_bc(image,path);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    mask.save(REF/'optical-mask.png')
    material='''import * from "CR_BZBase.material"

material CRV/CVFighterCockpit : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap crvcfcp_d.dds
    set_texture_alias NormalMap flat_N.dds
    set_texture_alias SpecularMap crvcca_patch_s.dds
    set_texture_alias EmissiveMap crvcfcp_e.dds
}

material CRV/CVFighterGuns : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap cvfigh_d.dds
    set_texture_alias NormalMap cvfigh_N.dds
    set_texture_alias SpecularMap cvfigh_S.dds
    set_texture_alias EmissiveMap cvfigh_e.dds
}
'''
    path=ROOT/'Materials/CR_cvfigh_cockpit.material';path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    receipt=dict(schema=1,masterSha256=sha(REF/'atlas-master.png'),sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={n:len(i)//3 for n,(d,i) in parts.items()})
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print('CV fighter cockpit',receipt['triangles'],meta['povPosition'],glass)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',default=r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux');build(parser.parse_args().game)
