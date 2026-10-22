"""Build independent Olympian/Fury mine assets from the stock mesh and SDF.

Only Ogre material/skeleton resource names change. Native collision, geometry,
UVs, skinning and skeleton remain stock. Fresh diffuse atlases are retained in
References/BoltMines; the builder only performs DDS format conversion.
"""
from pathlib import Path
import io,shutil,sys
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bzmodellibs import ogremesh_serializer
from bcdds import save_bc
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'References/BoltMines'

# BC1 with a full offline mip chain (Tools/bcdds.py): compressed DDS without
# mips render black in native DX11. cr_marc stays RGBA8 (small, alpha).
def build():
    original=SOURCE/'original'
    source=(original/'boltmine.mesh').read_bytes()
    dest=ROOT/'Assets/ModelFixes'
    for name in ('cromine','crfmine'):
        model=ogremesh_serializer.MeshSerializer(io.BytesIO(source)).read()
        for sub in model.submesh_list:sub.material_name=name
        model.skeleton_name=name+'.skeleton'
        out=io.BytesIO();ogremesh_serializer.MeshSerializer(out).write(model)
        (dest/(name+'.mesh')).write_bytes(out.getvalue())
        for ext in ('sdf','skeleton'):shutil.copyfile(original/('boltmine.'+ext),dest/(name+'.'+ext))
        for suffix,kind in (('_d','diffuse'),('_e','emission')):
            image=Image.open(SOURCE/(name+'-'+kind+'.png')).convert('RGBA').resize((1024,1024),Image.Resampling.LANCZOS)
            save_bc(image,ROOT/'Assets/Textures'/(name+suffix+'.dds'))
    Image.open(SOURCE/'arc-filament.png').convert('RGBA').resize((512,128),Image.Resampling.LANCZOS).save(ROOT/'Assets/Textures/cr_marc.dds')
    print('Built Olympian and Fury SDF/mesh/skeleton copies, BC1 mipped diffuse/emission atlases and neutral arc filament.')

if __name__=='__main__':build()
