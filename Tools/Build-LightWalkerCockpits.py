"""Offline three-unit revamp; preserves original POV rigs and native VDFs."""
from pathlib import Path
import argparse,hashlib,json,re
import numpy as np
import lightwalkercockpits as cp
import cockpitglass as cg
from bzmodellibs import legacy_port
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/LightWalkerCockpits'


def sha(path):
    b=path.read_bytes();return hashlib.sha256(b.replace(b'\r\n',b'\n') if path.suffix=='.material' else b).hexdigest()


def build(game):
    src=cg.Sources(game=str(game),cr=str(ROOT));native_source=legacy_port.AssetSource(folders=[ROOT/'Assets/ModelFixes',ROOT/'Assets/Models'],archives=[game/'bzone.zfs',game/'tro_cam.zfs'])
    for base,cfg in cp.CONFIG.items():
        ref=REF/base;ref.mkdir(parents=True,exist_ok=True);source=Path(src.model(base+'.mesh')[0]);full=cp.shared.read_mesh(source);fullrig=Path(src.model(full.skeleton_name)[0]);rig=fullrig if base=='cvltnk' else Path(src.model(base+'_c.skeleton')[0]);native=native_source(base+'.vdf')
        # Keep immutable source cockpit/rig snapshots so rebuilds and tests do
        # not feed the generated _c output back into the source audit.
        if not (ref/'source-cockpit.mesh').exists():(ref/'source-cockpit.mesh').write_bytes(Path(cg.cockpit_mesh(src,base)[0]).read_bytes())
        (ref/'source-rig.skeleton').write_bytes(rig.read_bytes())
        (ref/'source-full-rig.skeleton').write_bytes(fullrig.read_bytes())
        parts,s,w,eye,shell,bind,posed,meta=cp.geometry(source,fullrig,rig,base,native);raw,glass=cp.compile_mesh(parts,s,w,eye,shell,bind,posed,meta,base);outputs={}
        modelpath=ROOT/('Assets/Models' if base=='cvltnk' else 'Assets/ModelFixes')/(cfg['resource']+'.mesh');modelpath.write_bytes(raw);outputs[modelpath.relative_to(ROOT).as_posix()]=sha(modelpath)
        if base=='cvltnk':
            path=ROOT/'Assets/Models'/(cfg['resource']+'.skeleton');path.write_bytes(rig.read_bytes());outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        original=(ROOT/'Materials'/(base+'.material')).read_text();block=re.search(r'material '+re.escape(cfg['exterior'])+r'\s*:[^{]+\{(.*?)\}',original,re.S)[1];aliases=re.findall(r'set_texture_alias\s+(\S+)\s+(\S+)',block)
        material='import * from "CR_BZBase.material"\n\nmaterial CRV/'+base+'HeadHull : CR_BZBaseCockpit\n{\n'+''.join('    set_texture_alias '+a+' '+b+'\n' for a,b in aliases)+'}\n';stem='crvchcp' if cfg['faction']=='cra' else 'crvsmcp'
        material+='\nmaterial CRV/'+base+'SectionBacks : CR_BZBaseCockpit\n{\n    set_texture_alias DiffuseMap '+stem+'_d.dds\n    set_texture_alias NormalMap flat_N.dds\n    set_texture_alias SpecularMap crvcca_patch_s.dds\n    set_texture_alias EmissiveMap capblack_E.dds\n}\n';path=ROOT/'Materials'/('CR_'+base+'_cockpit.material');path.write_text(material,newline='\n');outputs[path.relative_to(ROOT).as_posix()]=sha(path)
        fixtures=meta.pop('sourceFixtures');np.savez_compressed(ref/'source-sections.npz',**fixtures)
        for key in ('exteriorHandles','capHandles'):meta[key+'Sha256']=hashlib.sha256(json.dumps(meta.pop(key),separators=(',',':')).encode()).hexdigest()
        receipt=dict(schema=1,base=base,sources=dict(exteriorSha256=sha(source),fullRigSha256=sha(fullrig),cockpitRigSha256=sha(rig),sourceCockpitSha256=sha(ref/'source-cockpit.mesh'),sectionFixtureSha256=sha(ref/'source-sections.npz'),nativeVdfSha256=hashlib.sha256(native).hexdigest()),outputs=outputs,alignment=meta,glass=glass,triangles={key:len(ix)//3 for key,(d,ix) in parts.items()},atlasPolicy='Existing faction hardware and original unit exterior maps only; no new bitmaps')
        (ref/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n');print('LIGHT_WALKER_BUILD',base,receipt['triangles'],meta['povPosition'],flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path(cg.GAME));build(parser.parse_args().game)
