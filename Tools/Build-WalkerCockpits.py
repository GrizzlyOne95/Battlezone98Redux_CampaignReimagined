"""Build the NSDF/Black Dog walker pair for offline review; never installs."""
from pathlib import Path
import argparse,hashlib,json,re
import numpy as np
import walkercockpits as cp
import cockpitglass as cg
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/WalkerCockpits'
def sha(path):
    b=path.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if path.suffix=='.material' else b).hexdigest()
def build(game):
    sources=cg.Sources(game=str(game),cr=str(ROOT))
    for base,cfg in cp.CONFIG.items():
        source,_=sources.model(base+'.mesh');source=Path(source);full=cp.shared.read_mesh(source);fullskel=Path(sources.model(full.skeleton_name)[0])
        # The established _c rig is the camera/animation authority, even after
        # a namespaced prototype is already present from a previous build.
        skel=Path(sources.model(base+'_c.skeleton')[0]);ref=REF/base;ref.mkdir(parents=True,exist_ok=True)
        parts,s,w,eye,shell,meta=cp.geometry(source,fullskel,skel,base,game,ROOT);raw,glass=cp.compile_mesh(parts,s,w,eye,shell,base,meta);outputs={}
        path=ROOT/'Assets/ModelFixes'/(base+'_c.mesh');path.write_bytes(raw);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        (ref/'source-rig.skeleton').write_bytes(skel.read_bytes())
        original=(ROOT/'Materials'/(base+'.material')).read_text();block=re.search(r'material '+re.escape(cfg['exterior'])+r'\s*:[^{]+\{(.*?)\}',original,re.S)[1];aliases=re.findall(r'set_texture_alias\s+(\S+)\s+(\S+)',block)
        material='import * from "CR_BZBase.material"\n\nmaterial CRV/'+base+'GunArms : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in aliases)+'}\n';stem=cp.scout.CONFIG[cfg['faction']]['stem']
        material+='\nmaterial CRV/'+base+'JointBacks : CR_BZBaseCockpit\n{\n    set_texture_alias DiffuseMap '+stem+'_d.dds\n    set_texture_alias NormalMap flat_N.dds\n    set_texture_alias SpecularMap crvcca_patch_s.dds\n    set_texture_alias EmissiveMap '+stem+'_e.dds\n}\n'
        path=ROOT/'Materials'/('CR_'+base+'_cockpit.material');path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        fixture=meta.pop('sourceArmFixture');np.savez_compressed(ref/'source-arms.npz',**fixture)
        for key in ('armWeights','capWeights'):meta[key+'Sha256']=hashlib.sha256(json.dumps(meta.pop(key),separators=(',',':')).encode()).hexdigest()
        receipt=dict(schema=1,sources=dict(exteriorSha256=sha(source),fullRigSha256=sha(fullskel),cockpitRigSha256=sha(skel),armFixtureSha256=sha(ref/'source-arms.npz')),outputs=outputs,alignment=meta,glass=glass,triangles={name:len(ix)//3 for name,(v,ix) in parts.items()})
        (ref/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print(base,receipt['triangles'],meta['povPosition'],flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path(r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux'));build(parser.parse_args().game)
