"""Build two offline cockpit prototypes without changing original units or art."""
from pathlib import Path
import argparse,hashlib,json,re
import bomberrocketcockpits as cp
import cockpitglass as cg
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/BomberRocketCockpits'


def sha(path):
    b=path.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if path.suffix=='.material' else b).hexdigest()


def build(game):
    src=cg.Sources(game=str(game),cr=str(ROOT))
    for base,cfg in cp.CONFIG.items():
        ref=REF/base;ref.mkdir(parents=True,exist_ok=True);source=Path(src.model(base+'.mesh')[0]);mesh=cp.shared.read_mesh(source);skel=Path(src.model(mesh.skeleton_name)[0]);parts,s,w,eye,shell,meta,native=cp.geometry(source,skel,base,game,ROOT);raw,glass=cp.compile_mesh(parts,s,w,eye,shell,meta,base);outputs={}
        for path,content in [(ROOT/'Assets/Models'/(base+'_cockpit.mesh'),raw),(ROOT/'Assets/Models'/(base+'_cockpit.skeleton'),skel.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        original=(ROOT/'Materials'/(base+'.material')).read_text();block=re.search(r'material '+re.escape(cfg['exterior'])+r'\s*:[^{]+\{(.*?)\}',original,re.S)[1];aliases=re.findall(r'set_texture_alias\s+(\S+)\s+(\S+)',block)
        material='import * from "CR_BZBase.material"\n\nmaterial CRV/'+base+'Exterior : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in aliases)+'}\n'
        if base=='svhraz':material+='\nmaterial '+cp.SV_STRUCTURE+' : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+('capblack_E.dds' if a=='EmissiveMap' else b)+'\n' for a,b in aliases)+'}\n'
        path=ROOT/'Materials'/('CR_'+base+'_cockpit.material');path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        receipt=dict(schema=1,base=base,sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel),nativeSha256=hashlib.sha256(native).hexdigest()),outputs=outputs,alignment=meta,glass=glass,triangles={key:len(ix)//3 for key,(d,ix) in parts.items()},atlasPolicy='Existing accepted faction hardware and original exterior maps only; no new textures')
        (ref/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print('BOMBER_ROCKET_BUILD',base,receipt['triangles'],meta['povPosition'],flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path(cg.GAME));build(parser.parse_args().game)
