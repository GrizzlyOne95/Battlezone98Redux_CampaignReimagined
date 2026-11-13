"""Build four stock-grounded tank cockpit review prototypes (never deploys)."""
from pathlib import Path
import argparse,hashlib,json,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import tankcockpits as cp, tankpanelatlas, eyeoverrides
from bcdds import save_bc
from weaponrigs import base_asset_path
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/TankCockpits'
def sha(p):
    b=p.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if p.suffix=='.material' else b).hexdigest()
def build(game,factions=()):
    for faction,cfg in cp.CONFIG.items():
        if factions and faction not in factions:continue
        # The weapon-rig stage rewrites the exterior in place; build from its pinned pre-rig input.
        base=cfg['base'];source=base_asset_path(ROOT/'Assets/ModelFixes'/(base+'.mesh'));skel=next((game/'BZ_ASSETS/common/models').rglob(base+'.skeleton'));ref=REF/faction;ref.mkdir(parents=True,exist_ok=True)
        # The cabin is built round the CR eye (eyeoverrides), the one the camera uses in game.
        rig=ROOT/'Assets/Models'/(base+'_cockpit.skeleton');rig.write_bytes(eyeoverrides.patch_skeleton(base,skel.read_bytes()))
        parts,s,w,eye,shell,meta=cp.geometry(source,rig,faction,game,ROOT);mesh,glass=cp.compile_mesh(parts,s,w,eye,shell,base,meta);outputs={}
        for path,content in [(ROOT/'Assets/Models'/(base+'_cockpit.mesh'),mesh),(rig,rig.read_bytes())]:path.write_bytes(content);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        original=(ROOT/'Materials'/(base+'.material')).read_text();import re
        block=re.search(r'material '+re.escape(cfg['exterior'])+r'\s*:[^{]+\{(.*?)\}',original,re.S)[1];aliases=re.findall(r'set_texture_alias\s+(\S+)\s+(\S+)',block)
        material='import * from "CR_BZBase.material"\n\n'
        for role in ('Guns','Hull'):
            material+='material CRV/'+base+'Tank'+role+' : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in aliases)+'}\n\n'
        if 'atlas' in cfg:
            # Per-unit generated panel atlas (tread plate, armour, hazard sills, pod scopes).
            for channel,im in zip(('d','e','N'),tankpanelatlas.images(faction)):
                path=ROOT/'Assets/Textures'/(cfg['atlas']+'_'+channel+'.dds');save_bc(im,path);outputs[path.relative_to(ROOT).as_posix()]=sha(path)
            material+=cfg['material'].join(['material ',' : CR_BZBaseCockpit\n{\n'])+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in (('DiffuseMap',cfg['atlas']+'_d.dds'),('NormalMap',cfg['atlas']+'_N.dds'),('SpecularMap','crvcca_patch_s.dds'),('EmissiveMap',cfg['atlas']+'_e.dds')))+'}\n'
        path=ROOT/'Materials'/('CR_'+base+'_cockpit.material');path.write_text(material.rstrip()+'\n',newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        meta['gunWeightSha256']=hashlib.sha256(json.dumps(meta.pop('gunWeights'),separators=(',',':')).encode()).hexdigest()
        receipt=dict(schema=1,sources=dict(exteriorSha256=sha(source),skeletonSha256=sha(skel)),outputs=outputs,alignment=meta,glass=glass,triangles={name:len(ix)//3 for name,(v,ix) in parts.items()},atlasPolicy=('Generated per-unit panel atlas '+cfg['atlas']+'; exterior atlas reused for hull and guns') if 'atlas' in cfg else 'Reuse original and accepted faction atlases; no duplicate DDS')
        (ref/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print(faction,receipt['triangles'],meta['povPosition'],glass,flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path(r'C:/Program Files (x86)/GOG Galaxy/Games/Battlezone 98 Redux'));parser.add_argument('--factions',nargs='*',default=());a=parser.parse_args();build(a.game,a.factions)
