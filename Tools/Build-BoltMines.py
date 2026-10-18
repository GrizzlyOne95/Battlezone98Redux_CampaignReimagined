"""Build independent Olympian/Fury mine assets from the stock mesh and SDF.

Only Ogre material/skeleton resource names change. Native collision, geometry,
UVs, skinning and skeleton remain stock. Fresh diffuse atlases are retained in
References/BoltMines; the builder only performs DDS format conversion.
"""
from pathlib import Path
import shutil,struct
from PIL import Image
from ogrebin import Mesh,M_SUBMESH,M_MESH_SKELETON_LINK
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'References/BoltMines'

# Keep RGBA8 DDS: the prototype BC3 files loaded without errors but rendered
# gray in native DX11; the same pixels as PNG/RGBA8 DDS display correctly.
def build():
    original=SOURCE/'original'
    model=Mesh(original/'boltmine.mesh')
    dest=ROOT/'Assets/ModelFixes'
    for name in ('cromine','crfmine'):
        body=bytearray(model.data[model.mesh_start+6:model.children[0][1]])
        for kind,start,end in model.children:
            chunk=model.data[start:end]
            if kind in (M_SUBMESH,M_MESH_SKELETON_LINK):
                split=chunk.index(b'\n',6)
                value=(name if kind==M_SUBMESH else name+'.skeleton').encode()
                chunk=struct.pack('<HI',kind,len(chunk)-(split-6)+len(value))+value+chunk[split:]
            body.extend(chunk)
        data=model.data[:model.mesh_start]+struct.pack('<HI',0x3000,len(body)+6)+body+model.tail
        (dest/(name+'.mesh')).write_bytes(data)
        for ext in ('sdf','skeleton'):shutil.copyfile(original/('boltmine.'+ext),dest/(name+'.'+ext))
        Image.open(SOURCE/(name+'-diffuse.png')).convert('RGBA').resize((1024,1024),Image.Resampling.LANCZOS).save(ROOT/'Assets/Textures'/(name+'_d.dds'))
        Image.open(SOURCE/(name+'-emission.png')).convert('RGBA').resize((1024,1024),Image.Resampling.LANCZOS).save(ROOT/'Assets/Textures'/(name+'_e.dds'))
    Image.open(SOURCE/'arc-filament.png').convert('RGBA').resize((512,128),Image.Resampling.LANCZOS).save(ROOT/'Assets/Textures/cr_marc.dds')
    print('Built Olympian and Fury SDF/mesh/skeleton copies, RGBA8 diffuse/emission atlases and neutral arc filament.')

if __name__=='__main__':build()
