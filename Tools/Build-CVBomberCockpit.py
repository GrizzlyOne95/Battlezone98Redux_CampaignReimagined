"""Rebuild the POV-fitted CRA bomber cockpit and its saved optical atlas."""
from pathlib import Path
import argparse,hashlib,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import save_bc
import cvhrazcockpit as cp
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/CVBomberCockpit'
def sha(path):
    data=path.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if path.suffix=='.material' else data).hexdigest()
LIME_LENSES=[(71,97,591,337),(615,108,705,204),(632,229,687,285),
             (774,90,925,228),(55,476,216,628),(268,493,390,621),
             (436,493,580,623),(85,674,129,777),(499,674,539,777),
             (672,505,974,564),(1026,504,1211,556)]
AMBER_LENSES=[(1030,614,1074,660),(1090,614,1134,660),(1150,614,1196,660)]
AMBER_LENSES += [(x0,y0,x1,y1) for x0,x1 in [(965,1011),(1028,1075),(1092,1138),(1156,1202)] for y0,y1 in [(94,141),(170,217)]]
def textures():
    with Image.open(REF/'atlas-master.png') as im:a=np.array(im.convert('RGB'));size=im.size
    assert size==(1254,1254),size
    r,g,b=[a[:,:,i].astype(float) for i in range(3)];lime_roi=np.zeros(r.shape,bool);amber_roi=np.zeros(r.shape,bool)
    for x0,y0,x1,y1 in LIME_LENSES:lime_roi[y0:y1,x0:x1]=True
    for x0,y0,x1,y1 in AMBER_LENSES:amber_roi[y0:y1,x0:x1]=True
    lime=lime_roi&(g>85)&(g>r*1.10)&(g>b*1.5)
    amber=amber_roi&(r>150)&(g>80)&(b<110)&(r>g*1.15);mask=lime|amber;e=np.zeros_like(a);e[mask]=a[mask]
    return Image.fromarray(a).resize((1024,1024),Image.Resampling.LANCZOS),Image.fromarray(e).resize((1024,1024),Image.Resampling.LANCZOS),Image.fromarray(mask.astype('uint8')*255)
def build(game):
    source=ROOT/'Assets/ModelFixes/cvhraz.mesh';skel=Path(game)/'BZ_ASSETS/common/models/TRO/cvhraz.skeleton'
    parts,s,world,eye,shell,meta=cp.geometry(source,skel)
    model,glass=cp.shared.mesh_bytes(parts,s,world,eye,shell,skeleton_name='cvhraz_cockpit.skeleton');outputs={}
    for path,content in [(ROOT/'Assets/Models/cvhraz_cockpit.mesh',model),(ROOT/'Assets/Models/cvhraz_cockpit.skeleton',skel.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    d,e,mask=textures()
    for channel,im in [('d',d),('e',e)]:
        path=ROOT/'Assets/Textures'/('crvchcp_'+channel+'.dds');save_bc(im,path);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    mask.save(REF/'optical-mask.png')
    material='''import * from "CR_BZBase.material"

material CRV/CVBomberCockpit : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap crvchcp_d.dds
    set_texture_alias NormalMap flat_N.dds
    set_texture_alias SpecularMap crvcca_patch_s.dds
    set_texture_alias EmissiveMap crvchcp_e.dds
}

material CRV/CVBomberShoulders : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap cvhraz_d.dds
    set_texture_alias NormalMap cvhraz_N.dds
    set_texture_alias SpecularMap cvhraz_S.dds
    set_texture_alias EmissiveMap cvhraz_e.dds
}
'''
    path=ROOT/'Materials/CR_cvhraz_cockpit.material';path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    old=cp.shared.read_mesh(source).submesh_list[1];p=cp.shared.values(old.vertex_data,cp.shared.om.VES.POSITION);before=p[old.index_array.reshape(-1,3)]
    after=np.concatenate([d[:,:3][i.reshape(-1,3)] for d,i in parts.values()]);origin,R=world[eye.handle]
    coverage=dict(method='97x55 one-sided perspective screen samples; vertical FOV 64, aspect 16/9, no weather/HUD',before=cp.view_coverage(before,origin,R),after=cp.view_coverage(after,origin,R))
    with Image.open(REF/'atlas-master.png') as im:size=list(im.size)
    receipt=dict(schema=1,masterSha256=sha(REF/'atlas-master.png'),masterSize=size,runtimeSize=[1024,1024],sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={n:len(i)//3 for n,(v,i) in parts.items()},screenObstruction=coverage)
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print('CV bomber cockpit',receipt['triangles'],meta['povPosition'],glass,coverage)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',default=r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux');build(parser.parse_args().game)
