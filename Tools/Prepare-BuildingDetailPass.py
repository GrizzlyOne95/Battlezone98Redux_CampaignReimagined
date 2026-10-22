"""Capture stock building inputs for a bounded offline art pass (one-time)."""
from pathlib import Path
import hashlib,io,json,sys
import numpy as np
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/BuildingDetailPass'
ASSETS=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\BZ_ASSETS')
def main():
    assert not (REF/'sources.json').exists(),'Source capture already exists'
    (REF/'original').mkdir(parents=True,exist_ok=True);sources={}
    textures={p.name.lower():p for p in ASSETS.rglob('*.dds')}
    for name in ('ablpad','sbsupp'):
        model=ROOT/'Assets/ModelFixes'/(name+'.mesh')
        if not model.exists():model=ASSETS/'common/models'/(name+'.mesh')
        target=REF/'original'/model.name;target.write_bytes(model.read_bytes())
        sources[target.relative_to(REF).as_posix()]=dict(sha256=hashlib.sha256(target.read_bytes()).hexdigest(),source='CR ModelFixes' if model.is_relative_to(ROOT) else 'Redux stock common/models')
        for channel in ('d','e'):
            path=textures[name+'_'+channel+'.dds'];target=REF/'original'/(name+'_'+channel+'.png')
            with Image.open(path) as image:image.convert('RGB').save(target)
            sources[target.relative_to(REF).as_posix()]=dict(sha256=hashlib.sha256(target.read_bytes()).hexdigest(),source=path.relative_to(ASSETS).as_posix(),ddsSha256=hashlib.sha256(path.read_bytes()).hexdigest())
        model=oms.MeshSerializer(io.BytesIO(model.read_bytes())).read()
        image=Image.open(REF/'original'/(name+'_d.png')).convert('RGB');draw=ImageDraw.Draw(image)
        for sub in model.submesh_list:
            vd=sub.vertex_data;el=vd.vertex_declaration.find_by_semantic(om.VES.TEXTURE_COORDINATES);vb=vd.get_vertex_buffer(el.source)
            uv=np.ndarray((vd.vertex_count,2),'<f4',buffer=vb.buffer,offset=el.offset,strides=(vb.vertex_size,4))
            for ids in sub.index_array.reshape(-1,3):
                points=[tuple(uv[i]*np.array(image.size)) for i in ids];draw.line(points+[points[0]],fill=(30,255,180),width=1)
        out=ROOT/'Local/BuildingDetailPass';out.mkdir(parents=True,exist_ok=True);image.save(out/(name+'-uv.png'))
    # Store source-UV crops using diffuse-space coordinates; stock emission may
    # have different dimensions. The checked-in recipe defines exact regions.
    recipe=json.loads((REF/'recipe.json').read_text())
    for row in recipe['models']:
        for patch in row['patches']:
            for channel in ('d','e'):
                with Image.open(REF/'original'/(row['model']+'_'+channel+'.png')) as image:
                    image.convert('RGB').resize(tuple(row['atlasSize']),Image.Resampling.LANCZOS).crop(patch['bounds']).save(REF/'original'/(patch['id']+'_'+channel+'.png'))
    (REF/'sources.json').write_text(json.dumps(sources,indent=2)+'\n')
if __name__=='__main__':main()
