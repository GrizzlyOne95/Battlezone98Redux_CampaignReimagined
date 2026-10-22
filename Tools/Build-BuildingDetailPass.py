"""Compile the bounded NSDF pad / CCA supply ImageGen patch masters offline."""
from pathlib import Path
import importlib.util,json,sys
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/BuildingDetailPass'
spec=importlib.util.spec_from_file_location('building_patches',ROOT/'Tools/Build-BuildingTexturePatches.py')
patches=importlib.util.module_from_spec(spec);spec.loader.exec_module(patches)
def recipes():
    for row in json.loads((REF/'recipe.json').read_text())['models']:
        row.update(sourceDirectory='original',sourceMaterialFile=row['model']+'.material',materialFile='CR_detail_'+row['model']+'.material',receipt=row['model']+'-build.json',recordMasters=True)
        for patch in row['patches']:
            # Even non-glowing patches get black source E; do not infer glow
            # from white stars, hazard paint or brighter generated metal.
            patch.update(emissionSource='original/'+patch['id']+'_e.png',diffuseLampSource='original/'+patch['id']+'_d.png')
        yield row
def build():
    for row in recipes():patches.build_one(row,REF)
if __name__=='__main__':build()
