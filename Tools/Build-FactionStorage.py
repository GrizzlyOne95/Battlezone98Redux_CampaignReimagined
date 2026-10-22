"""Build independent faction storage crates from the stock abstor geometry.

ImageGen supplies UV-compatible faction PNGs. The build only compresses/maps
them and changes render resource names through the shared model serializer.
All native SDF/collision/rig data and render vertex/index streams stay stock.
"""
from pathlib import Path
import hashlib,io,json,sys,shutil,re
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh_serializer as oms
from bcdds import save_bc
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'References/TextureRevamp/crates'
FACTIONS={'crstns':'NSDF','crstbd':'Black Dog','crstcc':'CCA','crstcr':'CRA'}

def build():
    files={};stock={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in REF.glob('abstor.*')}
    masters={name+'.png':hashlib.sha256((REF/(name+'.png')).read_bytes()).hexdigest() for name in FACTIONS}
    for name,faction in FACTIONS.items():
        mesh=oms.MeshSerializer(io.BytesIO((REF/'abstor.mesh').read_bytes())).read()
        mesh.skeleton_name=name+'.skeleton'
        for sub in mesh.submesh_list:sub.material_name=name
        stream=io.BytesIO();oms.MeshSerializer(stream).write(mesh)
        (ROOT/'Assets/Models'/(name+'.mesh')).write_bytes(stream.getvalue())
        for ext in ('sdf','skeleton'):shutil.copyfile(REF/('abstor.'+ext),ROOT/'Assets/Models'/(name+'.'+ext))
        with Image.open(REF/(name+'.png')) as im:image=im.convert('RGB').resize((1280,1280),Image.Resampling.LANCZOS)
        a=np.array(image);r,g,b=[a[:,:,i].astype(float) for i in range(3)]
        x,y=np.meshgrid(np.linspace(0,1,1280),np.linspace(0,1,1280))
        # Only the retained source status lamp emits, never painted faction art.
        mask=(x>.65)&(x<.79)&(y>.60)&(y<.68)&(r>100)&(r>g*2)&(r>b*2)
        emission=np.zeros_like(a);emission[mask]=a[mask]
        for suffix,im in (('d',image),('e',Image.fromarray(emission))):
            file=name+'_'+suffix+'.dds';path=ROOT/'Assets/Textures'/file;save_bc(im,path)
            files[file]=dict(size=[1280,1280],sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        material='\n'.join(['import * from "CR_BZBase.material"','',f'material {name} : CR_BZBase','{',
          f'    set_texture_alias DiffuseMap {name}_d.dds','    set_texture_alias NormalMap crvstor_n.dds',
          '    set_texture_alias SpecularMap crvcca_patch_s.dds',f'    set_texture_alias EmissiveMap {name}_e.dds',
          '    set $diffuse "1 1 1"','    set $ambient "1 1 1"','    set $specular ".25 .25 .25"','    set $shininess "48"','}',''])
        (ROOT/'Materials'/(name+'.material')).write_text(material,newline='\n')
    # Existing NSDF/Black Dog placements receive their proper identity too.
    # Independently placeable CCA/CRA ODFs do not replace mission objects.
    for old,new in (('abstor','crstns'),('bbstor','crstbd')):
        path=ROOT/'Materials'/(old+'.material');text=path.read_text()
        for alias,resource in [('DiffuseMap',new+'_d.dds'),('NormalMap','crvstor_n.dds'),('SpecularMap','crvcca_patch_s.dds'),('EmissiveMap',new+'_e.dds')]:
            text,n=re.subn(r'(set_texture_alias\s+'+alias+r'\s+)\S+',lambda m:m[1]+resource,text);assert n==1
        path.write_text(text,newline='\n')
    (REF/'build.json').write_text(json.dumps(dict(schema=1,source='Stock abstor render/native geometry; faction variants are independent render/ODF resources',stock=stock,masters=masters,files=files,factions=FACTIONS),indent=2)+'\n')
    print('Built four independent faction crate mesh/SDF/skeleton/material/map sets; existing NSDF/Black Dog selectors branded.')

if __name__=='__main__':build()
