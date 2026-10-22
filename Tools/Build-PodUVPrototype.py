"""Full, unique pod unwrap prototype; outputs stay outside shipping pending art review.

All source triangles get fresh UVs in one atlas/material. Continuous perimeter
bands replace per-facet panel stamping. Uses CR's shared native model codecs.
"""
from pathlib import Path
import argparse,hashlib,importlib.util,io,json,sys
import numpy as np
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Tools'))
spec=importlib.util.spec_from_file_location('pickups',ROOT/'Tools/Build-FactionNavPickups.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
REF=ROOT/'References/TextureRevamp/pod-uv-v3'
SOURCES={'cramns3':'apammo','crhpns3':'aprepa'}

from poduv import full_uv,remesh,atlas_image

def guide(name,uv,metadata):
    # Technical UV diagram only, never used as final artwork.
    size=1254;im=Image.new('RGB',(size,size),(35,38,43));draw=ImageDraw.Draw(im)
    colours=[(110,135,155),(170,155,120),(110,155,135),(145,120,150),(155,150,110)]
    for (label,record),colour in zip(metadata['charts'].items(),colours):
        for row in uv[record['triangles']]:draw.polygon([tuple(q*size) for q in row],fill=colour)
        for row in uv[record['triangles']]:draw.line([tuple(q*size) for q in np.r_[row,row[:1]]],fill=(190,200,205),width=1)
        a,b,c,d=record['box'];draw.text((a*size+4,b*size+4),label.upper(),fill='white')
    im.save(REF/(name+'-uv-guide.png'))

def build():
    parser=argparse.ArgumentParser();parser.add_argument('--textures',action='store_true');args=parser.parse_args()
    REF.mkdir(parents=True,exist_ok=True);receipt={}
    for name,family in SOURCES.items():
        mesh=p.read(p.SRC/(family+'.mesh'));before=p.geometry(mesh);source=mesh.submesh_list[0]
        uv,metadata=full_uv(source,family);remesh(mesh,uv,name)
        assert p.geometry(mesh)==before,'Full unwrap altered drawn geometry or skin'
        stream=io.BytesIO();p.oms.MeshSerializer(stream).write(mesh);(REF/(name+'.mesh')).write_bytes(stream.getvalue())
        assert p.geometry(p.read(REF/(name+'.mesh')))==before,'Shared-codec roundtrip altered geometry'
        guide(name,uv,metadata)
        record={'source':family,'sourceMeshSha256':hashlib.sha256((p.SRC/(family+'.mesh')).read_bytes()).hexdigest(),
                'triangles':len(uv),'geometry':before,'uv':uv.tolist(),**metadata}
        if args.textures:
            from bcdds import save_bc
            master=REF/(name+'-master.png')
            save_bc(atlas_image(master,uv),REF/(name+'_d.dds'))
            record['masterSha256']=hashlib.sha256(master.read_bytes()).hexdigest()
            material='\n'.join(['import * from "CR_BZBase.material"',f'material {name} : CR_BZBase','{',
                f'    set_texture_alias DiffuseMap {name}_d.dds','    set_texture_alias NormalMap flat_N.dds',
                '    set_texture_alias SpecularMap crvcca_patch_s.dds','    set_texture_alias EmissiveMap black.dds',
                '    set $diffuse "1 1 1"','    set $ambient "1 1 1"','    set $specular ".15 .15 .15"','    set $shininess "32"','}',''])
            (REF/(name+'.material')).write_text(material,newline='\n')
        receipt[name]=record
        print(name,'fully unwrapped:',len(uv),'triangles in',len(metadata['charts']),'charts, one material; perimeter',round(metadata['perimeter'],3),'front U',round(metadata['frontBandU'],3))
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n')

if __name__=='__main__':build()
