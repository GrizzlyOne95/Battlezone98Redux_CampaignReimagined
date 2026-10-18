"""Copy the owner's standalone cut hvraz port, changing resource names only.

Original geometry, UVs, animation, collision and hardpoint transforms are retained.
The namespaced GEO companions are required by the legacy destruction path.
"""
from pathlib import Path
import argparse
import re
import struct
from PIL import Image
from ogrebin import Mesh, M_SUBMESH, M_MESH_SKELETON_LINK

ROOT = Path(__file__).resolve().parents[1]

def namespace(data):
    return re.sub(b'hra11', b'cfr11', data, flags=re.I)

def build(source):
    files = {p.name.lower(): p for p in source.iterdir() if p.is_file()}
    dest = ROOT/'Assets/ModelFixes'
    dest.mkdir(parents=True, exist_ok=True)
    for key, p in files.items():
        if key == 'hvraz.vdf':
            (dest/'crfraz.vdf').write_bytes(namespace(p.read_bytes()))
        elif key == 'hvraz.skeleton':
            (dest/'crfraz.skeleton').write_bytes(namespace(p.read_bytes()))
        elif key.startswith('hra11') and p.suffix.lower() == '.geo':
            (dest/('cfr11'+key[5:])).write_bytes(namespace(p.read_bytes()))
    mesh = Mesh(files['hvraz.mesh'])
    body = bytearray(mesh.data[mesh.mesh_start+6:mesh.children[0][1]])
    for cid, start, end in mesh.children:
        chunk = mesh.data[start:end]
        if cid in (M_SUBMESH, M_MESH_SKELETON_LINK):
            old_end = chunk.index(b'\n', 6)
            name = b'crfraz' if cid == M_SUBMESH else b'crfraz.skeleton'
            chunk = struct.pack('<HI',cid,len(chunk)-(old_end-6)+len(name))+name+chunk[old_end:]
        body.extend(chunk)
    # Only same-length bone-name substitutions outside the material/link fields.
    data = mesh.data[:mesh.mesh_start]+struct.pack('<HI',0x3000,len(body)+6)+body+mesh.tail
    (dest/'crfraz.mesh').write_bytes(namespace(data))
    image=Image.open(ROOT/'References/FuryFighter/fury-diffuse.png').convert('RGBA')
    image.resize((1024,1024),Image.Resampling.LANCZOS).save(ROOT/'Assets/Textures/crfraz_d.dds')
    print('Copied crfraz VDF/mesh/skeleton + 12 GEO companions; DDS 1024x1024 RGBA8.')

if __name__ == '__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source-dir',type=Path,default=ROOT/'References/FuryFighter/original')
    build(ap.parse_args().source_dir)
