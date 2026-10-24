"""Build the CRA heavy-tank offline prototype; never installs or launches."""
from pathlib import Path
import argparse,hashlib,json,re
import cvheavycockpit as cp
import cockpitglass as cg
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/CVHeavyCockpit'

def sha(path):
    b=path.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if path.suffix=='.material' else b).hexdigest()

def build(game):
    REF.mkdir(parents=True,exist_ok=True);src=cg.Sources(game=str(game),cr=str(ROOT));source=Path(src.model('cvhtnk.mesh')[0]);mesh=cp.shared.read_mesh(source);skel=Path(src.model(mesh.skeleton_name)[0]);parts,s,w,eye,shell,meta=cp.geometry(source,skel,game,ROOT);raw,glass=cp.compile_mesh(parts,s,w,eye,shell,meta);outputs={}
    for path,content in [(ROOT/'Assets/Models/cvhtnk_cockpit.mesh',raw),(ROOT/'Assets/Models/cvhtnk_cockpit.skeleton',skel.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    original=(ROOT/'Materials/cvhtnk.material').read_text();block=re.search(r'material cvhtnk\s*:[^{]+\{(.*?)\}',original,re.S)[1];aliases=re.findall(r'set_texture_alias\s+(\S+)\s+(\S+)',block)
    material='import * from "CR_BZBase.material"\n\nmaterial '+cp.EXTERIOR+' : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in aliases)+'}\n\nmaterial '+cp.CAPS+' : CR_BZBaseCockpit\n{\n    set_texture_alias DiffuseMap crvchcp_d.dds\n    set_texture_alias NormalMap flat_N.dds\n    set_texture_alias SpecularMap crvcca_patch_s.dds\n    set_texture_alias EmissiveMap crvchcp_e.dds\n}\n'
    path=ROOT/'Materials/CR_cvhtnk_cockpit.material';path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
    for key in ('exteriorHandles','capHandles'):meta[key+'Sha256']=hashlib.sha256(json.dumps(meta.pop(key),separators=(',',':')).encode()).hexdigest()
    receipt=dict(schema=1,sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={key:len(ix)//3 for key,(d,ix) in parts.items()},atlasPolicy='Existing CRA hardware and original exterior maps only; no new textures')
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print('CV_HEAVY_BUILD',receipt['triangles'],meta['povPosition'],flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path(cg.GAME));build(parser.parse_args().game)
