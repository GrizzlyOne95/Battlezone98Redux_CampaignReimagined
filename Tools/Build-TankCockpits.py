"""Build four stock-grounded tank cockpit review prototypes (never deploys)."""
from pathlib import Path
import argparse,hashlib,json,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import tankcockpits as cp
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TankCockpits'
def sha(p):
    b=p.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if p.suffix=='.material' else b).hexdigest()
def build(game):
    for faction,cfg in cp.CONFIG.items():
        base=cfg['base'];source=ROOT/'Assets/ModelFixes'/(base+'.mesh');skel=next((game/'BZ_ASSETS/common/models').rglob(base+'.skeleton'));ref=REF/faction;ref.mkdir(parents=True,exist_ok=True)
        parts,s,w,eye,shell,meta=cp.geometry(source,skel,faction,game,ROOT);mesh,glass=cp.compile_mesh(parts,s,w,eye,shell,base,meta);outputs={}
        for path,content in [(ROOT/'Assets/Models'/(base+'_cockpit.mesh'),mesh),(ROOT/'Assets/Models'/(base+'_cockpit.skeleton'),skel.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        original=(ROOT/'Materials'/(base+'.material')).read_text();import re
        block=re.search(r'material '+re.escape(cfg['exterior'])+r'\s*:[^{]+\{(.*?)\}',original,re.S)[1];aliases=re.findall(r'set_texture_alias\s+(\S+)\s+(\S+)',block)
        material='import * from "CR_BZBase.material"\n\n'
        for role in ('Guns','Hull'):
            material+='material CRV/'+base+'Tank'+role+' : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in aliases)+'}\n\n'
        if faction=='cca':
            material+='material CRV/SharedCockpitLiner : CR_BZBaseCockpit\n{\n    set_texture_alias DiffuseMap crvascp_d.dds\n    set_texture_alias NormalMap flat_N.dds\n    set_texture_alias SpecularMap crvcca_patch_s.dds\n    set_texture_alias EmissiveMap crvascp_e.dds\n}\n'
        path=ROOT/'Materials'/('CR_'+base+'_cockpit.material');path.write_text(material.rstrip()+'\n',newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        meta['gunWeightSha256']=hashlib.sha256(json.dumps(meta.pop('gunWeights'),separators=(',',':')).encode()).hexdigest()
        receipt=dict(schema=1,sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={name:len(ix)//3 for name,(v,ix) in parts.items()},atlasPolicy='Reuse original and accepted faction atlases; no duplicate DDS')
        (ref/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print(faction,receipt['triangles'],meta['povPosition'],glass,flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path(r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux'));build(parser.parse_args().game)
