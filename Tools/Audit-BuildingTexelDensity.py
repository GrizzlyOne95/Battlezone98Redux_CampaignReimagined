"""Audit active CR building diffuse aliases against installed stock meshes/art.

Read-only stock baseline: not a world-unit claim or a final camera-space score.
Area-weighted UV density includes repeated/overlapping islands. Inspect small
approachable surfaces separately. Ignores inactive legacy *00 texture guesses.
No game launch, deployment or source mutation. Re-run with --assets PATH when
the extracted stock asset tree is installed elsewhere.
"""
from pathlib import Path
import argparse,hashlib,io,json,re,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms
ROOT=Path(__file__).resolve().parents[1]

def audit(assets):
    textures={p.name.lower():p for p in assets.rglob('*.dds')}
    models={p.stem.lower():p for p in (assets/'common/models').rglob('*.mesh')}
    aliases={}
    scripts=sorted((ROOT/'Materials').glob('*.material'))
    for script in scripts:
        text=script.read_text(errors='replace')
        for match in re.finditer(r'(?ms)^\s*material\s+([^\s:{]+)[^\n]*\n(.*?)(?=^\s*material\s+|\Z)',text):
            found=re.search(r'set_texture_alias\s+DiffuseMap\s+(\S+)',match[2])
            if found:aliases[match[1]]=found[1].lower()
    result=[]
    for name in sorted(p.stem for p in scripts if re.fullmatch(r'[asb]b\w+',p.stem)):
        if name not in models:continue
        source=models[name];fixed=ROOT/'Assets/ModelFixes'/(name+'.mesh')
        if fixed.exists():source=fixed
        mesh=oms.MeshSerializer(io.BytesIO(source.read_bytes())).read();points=[];parts=[]
        for sub in mesh.submesh_list:
            vd=mesh.shared_vertex_data if sub.use_shared_vertices else sub.vertex_data
            def values(semantic):
                el=vd.vertex_declaration.find_by_semantic(semantic)
                if el is None:return None
                vb=vd.get_vertex_buffer(el.source)
                return np.ndarray((vd.vertex_count,el.get_type_count()),'<f4',buffer=vb.buffer,offset=el.offset,strides=(vb.vertex_size,4)).copy()
            xyz=values(om.VES.POSITION);uv=values(om.VES.TEXTURE_COORDINATES);points.extend(xyz.tolist())
            ix=sub.index_array.reshape(-1,3);tri=xyz[ix]
            area=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)*.5
            density=None;size=None;texture=textures.get(aliases.get(sub.material_name,''))
            if texture:
                with Image.open(texture) as image:size=list(image.size)
                if uv is not None:
                    t=uv[ix];d=t[:,1]-t[:,0];e=t[:,2]-t[:,0]
                    uvarea=abs(d[:,0]*e[:,1]-d[:,1]*e[:,0])*.5;valid=area>1e-6
                    density=float(np.sqrt((uvarea[valid]*size[0]*size[1]).sum()/area[valid].sum()))
            parts.append(dict(material=sub.material_name,vertices=vd.vertex_count,triangles=len(ix),surfaceArea=float(area.sum()),texture=texture.name if texture else None,size=size,effectiveTexelsPerModelUnit=density))
        a=np.array(points)
        result.append(dict(model=name,source=str(source.relative_to(ROOT) if source.is_relative_to(ROOT) else source.relative_to(assets)),sha256=hashlib.sha256(source.read_bytes()).hexdigest(),bounds=[a.min(0).tolist(),a.max(0).tolist()],extent=(a.max(0)-a.min(0)).tolist(),parts=parts))
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets',type=Path,default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\BZ_ASSETS'))
    parser.add_argument('--output',type=Path,default=ROOT/'Local/TextureRevamp/building-audit.json')
    args=parser.parse_args()
    if not args.assets.is_dir():parser.error('Supply an extracted stock BZ_ASSETS tree with --assets')
    rows=audit(args.assets);args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(rows,indent=2)+'\n')
    print(f'{len(rows)} building models audited; active material aliases, stock texture sizes and model-space UV density written to {args.output}')
