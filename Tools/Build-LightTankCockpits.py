"""Build NSDF and Black Dog light-tank cockpit prototypes; no install mutation."""
from pathlib import Path
import argparse,hashlib,json,re
import lighttankcockpits as cp
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/LightTankCockpits'

def sha(path):
    data=path.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if path.suffix=='.material' else data).hexdigest()

def build(game):
    for base,cfg in cp.CONFIG.items():
        source=REF/'source'/(base+'.mesh');skel=next((game/'BZ_ASSETS/common/models').rglob(base+'.skeleton'))
        parts,s,w,eye,shell,meta=cp.geometry(source,skel,base,game,ROOT);model,glass=cp.shared.mesh_bytes(parts,s,w,eye,shell,skeleton_name=base+'_cockpit.skeleton');outputs={}
        for path,data in [(ROOT/'Assets/Models'/(base+'_cockpit.mesh'),model),(ROOT/'Assets/Models'/(base+'_cockpit.skeleton'),skel.read_bytes())]:
            path.write_bytes(data);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        original=(ROOT/'Materials'/(base+'.material')).read_text();block=re.search(r'material '+re.escape(cfg['stock'])+r'\s*:[^{]+\{(.*?)\}',original,re.S)[1];aliases=re.findall(r'set_texture_alias\s+(\S+)\s+(\S+)',block)
        material='import * from "CR_BZBase.material"\n\nmaterial CRV/'+base+'OriginalFrame : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in aliases)+'}\n'
        stem=cp.scout.CONFIG[cfg['faction']]['stem']
        material+='\nmaterial CRV/'+base+'HullPaint : CR_BZBase\n{\n    set_texture_alias DiffuseMap '+stem+'_d.dds\n    set_texture_alias NormalMap flat_N.dds\n    set_texture_alias SpecularMap crvcca_patch_s.dds\n    set_texture_alias EmissiveMap '+stem+'_e.dds\n}\n'
        path=ROOT/'Materials'/('CR_'+base+'_cockpit.material');path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        ref=REF/base;ref.mkdir(parents=True,exist_ok=True)
        original_mesh=cp.shared.read_mesh(source);paint,paint_indices,handles,provenance=cp.markings.geometry(original_mesh.submesh_list[0],w[eye.handle][0],[cfg['bodyBone'],shell.handle],cfg['faction'])
        path=ROOT/'Assets/ModelFixes'/(base+'.mesh');path.write_bytes(cp.markings.model_bytes(original_mesh,paint,paint_indices,handles,'CRV/'+base+'HullPaint'));outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        receipt=dict(schema=1,sources=dict(baseline=source.relative_to(ROOT).as_posix(),exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={name:len(i)//3 for name,(v,i) in parts.items()},thirdPersonPaint=provenance)
        (ref/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print(base,receipt['triangles'],meta['povPosition'],flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path(r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux'));build(parser.parse_args().game)
