"""Build NSDF/Black Dog scout interiors from grounded saved atlas masters."""
from pathlib import Path
import argparse,hashlib,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import save_bc
import scoutcockpits as cp
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/ScoutCockpits'
def sha(p):
    data=p.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if p.suffix=='.material' else data).hexdigest()
SOURCE_CHARTS={
 'nsdf':{'console':(18,12,1236,308),'switch':(18,330,613,715),'service':(648,330,1236,715),'armor':(90,780,570,1195),'frame':(700,778,1180,865),'trim':(700,960,1180,1188)},
 'bdog':{'console':(18,12,1236,291),'switch':(18,330,614,806),'service':(648,330,1236,806),'armor':(70,880,570,1190),'frame':(700,860,1195,970),'trim':(700,1040,1190,1190)}}
# Physical source lens boxes, not whole-panel red/cyan hue extraction. Red
# cables, enamel guards and faction paint must never leak into emission.
LENSES={
 'nsdf':dict(primary=[(102,61,217,87),(102,124,253,269),(916,99,1041,237),
                       (380,557,428,659),(446,557,488,597),(1102,509,1139,591)],
             amber=[(218,61,243,87),(278,123,315,269),(1006,148,1041,238),
                    (449,617,485,656),(1153,510,1186,541)]),
 'bdog':dict(primary=[(77,153,117,177),(180,72,319,216),(918,87,1051,233),
                       (491,378,529,481),(1130,528,1164,608)],
             amber=[(75,96,118,124),(235,75,270,111),(180,184,216,217),
                    (971,144,1005,180),(540,380,579,479),(1170,528,1207,608)])}
def textures(faction):
    with Image.open(REF/faction/'atlas-master.png') as im:a=np.array(im.convert('RGB'));size=im.size
    assert size==(1254,1254),size
    r,g,b=[a[:,:,i].astype(float) for i in range(3)];roi=np.zeros(r.shape,bool);amber_roi=np.zeros(r.shape,bool)
    for x0,y0,x1,y1 in LENSES[faction]['primary']:roi[y0:y1,x0:x1]=True
    for x0,y0,x1,y1 in LENSES[faction]['amber']:amber_roi[y0:y1,x0:x1]=True
    primary=roi&((g>95)&(b>95)&(g>r*1.35)&(b>r*1.35) if faction=='nsdf' else (r>110)&(r>g*1.8)&(r>b*1.8))
    amber=amber_roi&(r>150)&(g>85)&(b<115)&(r>g*1.15);mask=primary|amber;e=np.zeros_like(a);e[mask]=a[mask]
    # Repack the returned master (its layout differs per faction) to shared
    # deliberate UV allocations. Do not remap triangles over atlas-wide art.
    diffuse=Image.new('RGB',(1024,1024),(12,12,14));emissive=Image.new('RGB',(1024,1024));srcd=Image.fromarray(a);srce=Image.fromarray(e)
    for key,rect in SOURCE_CHARTS[faction].items():
        x0,y0,x1,y1=[round(v*1024) for v in cp.CHARTS[key]];size=(x1-x0,y1-y0)
        diffuse.paste(srcd.crop(rect).resize(size,Image.Resampling.LANCZOS),(x0,y0));emissive.paste(srce.crop(rect).resize(size,Image.Resampling.LANCZOS),(x0,y0))
    return diffuse,emissive,Image.fromarray(mask.astype('uint8')*255)
def build(game):
    receipts={}
    for faction,cfg in cp.CONFIG.items():
        base=cfg['base'];ref=REF/faction;source=ROOT/'Assets/ModelFixes'/(base+'.mesh');skel=Path(game)/'BZ_ASSETS/common/models'/(base+'.skeleton')
        parts,s,world,eye,shell,meta=cp.geometry(source,skel,faction)
        model,glass=cp.shared.mesh_bytes(parts,s,world,eye,shell,skeleton_name=base+'_cockpit.skeleton');outputs={}
        for path,content in [(ROOT/'Assets/Models'/(base+'_cockpit.mesh'),model),(ROOT/'Assets/Models'/(base+'_cockpit.skeleton'),skel.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        d,e,mask=textures(faction)
        for channel,im in [('d',d),('e',e)]:
            path=ROOT/'Assets/Textures'/(cfg['stem']+'_'+channel+'.dds');save_bc(im,path);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        mask.save(ref/'optical-mask.png')
        # Reuse exact active exterior aliases; do not guess case from the model.
        material=f'''import * from "CR_BZBase.material"

material {cfg['material']} : CR_BZBaseCockpit
{{
    set_texture_alias DiffuseMap {cfg['stem']}_d.dds
    set_texture_alias NormalMap flat_N.dds
    set_texture_alias SpecularMap crvcca_patch_s.dds
    set_texture_alias EmissiveMap {cfg['stem']}_e.dds
}}

material {cfg['nose']} : CR_BZBaseCockpit
{{
    set_texture_alias DiffuseMap {base}_D.dds
    set_texture_alias NormalMap {base}_N.dds
    set_texture_alias SpecularMap {base}_S.dds
    set_texture_alias EmissiveMap {base}_E.dds
}}
'''
        path=ROOT/'Materials'/('CR_'+base+'_cockpit.material');path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        with Image.open(ref/'atlas-master.png') as im:size=list(im.size)
        receipt=dict(schema=1,masterSha256=sha(ref/'atlas-master.png'),masterSize=size,runtimeSize=[1024,1024],sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={n:len(i)//3 for n,(v,i) in parts.items()})
        (ref/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');receipts[faction]=receipt
        print(faction,receipt['triangles'],meta['povPosition'],glass)
    return receipts
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',default=r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux');build(parser.parse_args().game)
