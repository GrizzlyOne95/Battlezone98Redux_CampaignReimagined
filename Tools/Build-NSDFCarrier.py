"""Build the editable carrier, static Ogre/native meshes and RGBA8 atlases.

python Tools/Build-NSDFCarrier.py --blender <blender.exe> --render
Requires Blender 4.5+ and Pillow. --textures-only reconverts existing bakes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def build(blender,render,textures_only):
    if not textures_only:
        command=[blender,'-b','--factory-startup','-t','4','--python-exit-code','1',
                 '--python',str(ROOT/'Tools/Author-NSDFCarrier.py'),'--']
        if render:command.append('--render')
        subprocess.run(command,check=True)
    paths=[]
    for suffix in ('d','e','s','n'):
        source=ROOT/'References/NSDFCarrier/Textures'/('crncarr_'+suffix+'.png')
        target=ROOT/'Assets/Textures'/('crncarr_'+suffix+'.dds')
        Image.open(source).convert('RGBA').save(target);paths.append(target)
    paths += [ROOT/'Assets/ModelFixes'/('crncarr.'+s) for s in ('mesh','geo','sdf')]
    stats=json.loads((ROOT/'References/NSDFCarrier/geometry.json').read_text())
    stats['sha256']={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    (ROOT/'References/NSDFCarrier/build.json').write_text(json.dumps(stats,indent=2)+'\n')
    print('NSDF carrier:',stats['triangles'],'rendered triangles,',stats['native_triangles'],'native triangles')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--blender',default=shutil.which('blender'))
    p.add_argument('--render',action='store_true');p.add_argument('--textures-only',action='store_true');a=p.parse_args()
    if not a.blender and not a.textures_only:p.error('--blender is required')
    build(a.blender,a.render,a.textures_only)
