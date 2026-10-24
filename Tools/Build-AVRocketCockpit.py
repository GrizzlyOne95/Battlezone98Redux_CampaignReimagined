"""Build the independent avrckt cockpit prototype from its saved bitmap master."""
from pathlib import Path
import argparse,hashlib,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import save_bc
import avrcktcockpit as cp
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/AVRocketCockpit'
def sha(path):
    data=path.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if path.suffix=='.material' else data).hexdigest()
def textures():
    with Image.open(REF/'atlas-master.png') as im:a=np.array(im.convert('RGB'));size=im.size
    assert size==(1254,1254),size
    r,g,b=[a[:,:,i].astype(float) for i in range(3)];cyan_roi=np.zeros(r.shape,bool)
    for x0,y0,x1,y1 in CYAN_LENSES:cyan_roi[y0:y1,x0:x1]=True
    cyan=cyan_roi&(g>120)&(b>120)&(g>r*1.25)&(b>r*1.20)
    # Amber is restricted further to explicit physical lens rectangles, never
    # yellow switch guards or structural paint. Coordinates are normalized.
    amber_roi=np.zeros(r.shape,bool)
    for x0,y0,x1,y1 in AMBER_LENSES:amber_roi[y0:y1,x0:x1]=True
    amber=amber_roi&(r>150)&(g>80)&(b<110)&(r>g*1.15);mask=cyan|amber
    e=np.zeros_like(a);e[mask]=a[mask]
    return Image.fromarray(a).resize((1024,1024),Image.Resampling.LANCZOS),Image.fromarray(e).resize((1024,1024),Image.Resampling.LANCZOS),Image.fromarray(mask.astype('uint8')*255)
# Pixel bounds on the pinned 1254px physical master, not an atlas-wide hue mask.
CYAN_LENSES=[(109,101,356,344),(383,136,596,314),(1113,89,1201,250),
             (518,513,545,547),(785,519,1066,566),(785,595,1066,646)]
AMBER_LENSES=[(48,154,72,185),(85,318,102,345),(166,377,202,405),
              (383,334,415,358),(434,334,472,358),(65,543,88,576),
              (124,543,150,576),(519,565,547,592),(568,707,595,735),
              (699,571,736,611),(1107,386,1131,415)]
AMBER_LENSES += [(x0,y0,x1,y1) for x0,x1 in [(707,742),(784,818),(859,893),(938,973),(1013,1047)] for y0,y1 in [(115,189),(276,350)]]
def build(game):
    source=ROOT/'Assets/ModelFixes/avrckt.mesh';skel=Path(game)/'BZ_ASSETS/common/models/avrckt.skeleton'
    parts,s,world,eye,shell,meta=cp.geometry(source,skel)
    model,glass=cp.shared.mesh_bytes(parts,s,world,eye,shell,skeleton_name='avrckt_cockpit.skeleton');outputs={}
    for path,content in [(ROOT/'Assets/Models/avrckt_cockpit.mesh',model),(ROOT/'Assets/Models/avrckt_cockpit.skeleton',skel.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    d,e,mask=textures()
    for channel,im in [('d',d),('e',e)]:
        path=ROOT/'Assets/Textures'/('crvarcp_'+channel+'.dds');save_bc(im,path);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    mask.save(REF/'optical-mask.png')
    text='''import * from "CR_BZBase.material"

material CRV/AVRocketCockpit : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap crvarcp_d.dds
    set_texture_alias NormalMap flat_N.dds
    set_texture_alias SpecularMap crvcca_patch_s.dds
    set_texture_alias EmissiveMap crvarcp_e.dds
}

material CRV/AVRocketNoseFins : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap avrckt_D.dds
    set_texture_alias NormalMap avrckt_N.dds
    set_texture_alias SpecularMap avrckt_S.dds
    set_texture_alias EmissiveMap avrckt_E.dds
}
'''
    path=ROOT/'Materials/CR_avrckt_cockpit.material';path.write_text(text,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    with Image.open(REF/'atlas-master.png') as im:size=list(im.size)
    receipt=dict(schema=1,masterSha256=sha(REF/'atlas-master.png'),masterSize=size,runtimeSize=[1024,1024],sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={n:len(i)//3 for n,(v,i) in parts.items()})
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print('AV rocket cockpit',receipt['triangles'],meta['povPosition'],glass)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',default=r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux');build(parser.parse_args().game)
