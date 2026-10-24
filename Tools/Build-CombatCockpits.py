"""Reproducible offline art build for five combat cockpit replacements."""
from pathlib import Path
import argparse,hashlib,json,re,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
import combatcockpits as cp
from bcdds import save_bc
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/CombatCockpits'
SOURCE_CHARTS={'console':(18,16,1237,322),'switch':(18,359,584,820),'service':(619,359,1237,820),'armor':(40,870,565,1210),'frame':(670,895,1200,978),'trim':(680,1040,1200,1205)}
# Only actual physical lenses; red paint, toggles, fuse carriers and cables are
# deliberately excluded. Source and runtime mask are saved for optical review.
LENSES=[(57,81,105,134),(57,205,104,258),(755,104,782,125),(755,148,782,169),(755,192,782,213),(1157,82,1202,133),(1157,204,1202,258),(121,428,161,464),(182,428,221,464),(943,445,978,480),(986,445,1021,480),(1030,445,1064,480),(1073,445,1110,480)]
def sha(p):
    b=p.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if p.suffix=='.material' else b).hexdigest()
def textures():
    a=np.array(Image.open(REF/'cca/atlas-master.png').convert('RGB'));assert a.shape==(1254,1254,3);r,g,b=[a[:,:,i].astype(float) for i in range(3)];roi=np.zeros(r.shape,bool)
    for x0,y0,x1,y1 in LENSES:roi[y0:y1,x0:x1]=True
    mask=roi&(r>130)&(g>65)&(r>g*1.12)&(g>b*1.8);e=np.zeros_like(a);e[mask]=a[mask]
    d=Image.new('RGB',(1024,1024),(12,12,14));em=Image.new('RGB',(1024,1024));sd=Image.fromarray(a);se=Image.fromarray(e)
    for key,rect in SOURCE_CHARTS.items():
        x0,y0,x1,y1=[round(x*1024) for x in cp.CCA_CHARTS[key]];size=(x1-x0,y1-y0)
        d.paste(sd.crop(rect).resize(size,Image.Resampling.LANCZOS),(x0,y0));em.paste(se.crop(rect).resize(size,Image.Resampling.LANCZOS),(x0,y0))
    return d,em,Image.fromarray(mask.astype('uint8')*255)
def build(game):
    d,e,mask=textures();texture_outputs={}
    for channel,im in [('d',d),('e',e)]:
        path=ROOT/'Assets/Textures'/('crvsmcp_'+channel+'.dds');save_bc(im,path);texture_outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    mask.save(REF/'cca/optical-mask.png')
    shared='''import * from "CR_BZBase.material"

material CRV/CCAMechanicalCockpit : CR_BZBaseCockpit
{
    set_texture_alias DiffuseMap crvsmcp_d.dds
    set_texture_alias NormalMap flat_N.dds
    set_texture_alias SpecularMap crvcca_patch_s.dds
    set_texture_alias EmissiveMap crvsmcp_e.dds
}
'''
    path=ROOT/'Materials/CR_cca_mechanical_cockpit.material';path.write_text(shared,newline='\n');texture_outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    receipt=dict(masterSha256=sha(REF/'cca/atlas-master.png'),masterSize=[1254,1254],runtimeSize=[1024,1024],outputs=texture_outputs)
    (REF/'cca/build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n')
    for base,cfg in cp.CONFIG.items():
        source=ROOT/'Assets/ModelFixes'/(base+'.mesh');skel=next((game/'BZ_ASSETS/common/models').rglob(base+'.skeleton'));ref=REF/base;ref.mkdir(exist_ok=True)
        parts,s,w,eye,shell,meta=cp.geometry(source,skel,base,game,ROOT);model,glass=cp.shared.mesh_bytes(parts,s,w,eye,shell,skeleton_name=base+'_cockpit.skeleton');outputs={}
        for path,content in [(ROOT/'Assets/Models'/(base+'_cockpit.mesh'),model),(ROOT/'Assets/Models'/(base+'_cockpit.skeleton'),skel.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        original=(ROOT/'Materials'/(base+'.material')).read_text();block=re.search(r'material '+re.escape(cfg['exterior'])+r'\s*:[^{]+\{(.*?)\}',original,re.S)[1];aliases=re.findall(r'set_texture_alias\s+(\S+)\s+(\S+)',block)
        material='import * from "CR_BZBase.material"\n\nmaterial CRV/'+base+'CombatExterior : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in aliases)+'}\n'
        path=ROOT/'Materials'/('CR_'+base+'_cockpit.material');path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        receipt=dict(schema=1,sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={n:len(i)//3 for n,(v,i) in parts.items()})
        (ref/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print(base,receipt['triangles'],meta['povPosition'],glass,flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path(r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux'));build(parser.parse_args().game)
