"""Build the three large CCA concept hulls. Stock comparison units are excluded."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
ASSETS=('crccarr','crcred1','crcred2')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--blender',default=shutil.which('blender'));p.add_argument('--render',action='store_true')
    p.add_argument('--only',choices=ASSETS);p.add_argument('--textures-only',action='store_true');a=p.parse_args()
    if not a.textures_only:
        if not a.blender:p.error('--blender required')
        cmd=[a.blender,'-b','--factory-startup','-t','4','--python-exit-code','1',
             '--python',str(ROOT/'Tools/Author-CCAFleet.py'),'--']
        if a.render:cmd.append('--render')
        if a.only:cmd+=['--only',a.only]
        subprocess.run(cmd,check=True)
    for asset in ASSETS:
        if a.only and a.only!=asset:continue
        source=ROOT/'References/CCAFleet'/asset
        files=[]
        for suffix in 'desn':
            target=ROOT/'Assets/Textures'/(asset+'_'+suffix+'.dds')
            Image.open(source/'Textures'/(asset+'_'+suffix+'.png')).convert('RGBA').save(target)
            files.append(target)
        files += [ROOT/'Assets/ModelFixes'/(asset+'.'+s) for s in ('mesh','geo','sdf')]
        stats=json.loads((source/'geometry.json').read_text())
        stats['sha256']={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
        (source/'build.json').write_text(json.dumps(stats,indent=2)+'\n')
        odf=ROOT/'ODF'/(asset+'.odf')
        odf.write_text('[GameObjectClass]\nbaseName = "'+asset+'"\nclassLabel = "i76building"\n'
            'scrapCost = 0\nscrapValue = 0\nmaxHealth = 0\nmaxAmmo = 0\nunitName = "'+stats['name']+'"\n'
            'heatSignature = 0\nimageSignature = 0\nradarSignature = 0\n')
        mat=(ROOT/'Materials/crncarr.material').read_text().replace('crncarr',asset)
        (ROOT/'Materials'/(asset+'.material')).write_text(mat)
        print(asset,stats['triangles'],'triangles; dimensions',
              [round(b-c,1) for c,b in zip(stats['bounds_min'],stats['bounds_max'])])


if __name__=='__main__':main()
