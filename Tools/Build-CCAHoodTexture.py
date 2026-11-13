"""Build svtank's first-person hood texture (crcca_svhood_d/n/s/e.dds).

The cockpit's deck nose (CRV/svtankTankHull) used to sample the exterior svtank_d
livery at ~140 px/m and read blurry from the hatch. It now has its own owner-generated
livery (red nose, blue band with yellow pinstripes, cream plates with a red star nearest
the pilot) mapped top-down by Tools/tankcockpits.py (CONFIG['cca']['hood']), image top =
nose. Normal and specular are derived from the diffuse; emissive is black.

python Tools/Build-CCAHoodTexture.py
Source and provenance: References/TankCockpits/cca/hood-src/.
"""
from pathlib import Path
import importlib.util, json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'References/TankCockpits/cca/hood-src'
OUT = ROOT / 'Assets/Textures'
SIZE = (2048, 1024)

spec = importlib.util.spec_from_file_location('ccaatlas', ROOT / 'Tools/Build-CCACockpitAtlas.py')
atlas = importlib.util.module_from_spec(spec); spec.loader.exec_module(atlas)


def main():
    src = SRC / json.loads((SRC / 'provenance.json').read_text())['file']
    d = np.asarray(Image.open(src).convert('RGB').resize(SIZE, Image.LANCZOS), np.float32) / 255
    none = np.zeros(d.shape[:2], bool)
    normal, spec_, _ = atlas.derive(d, none, np.zeros(d.shape[:2], np.float32))
    maps = {'d': atlas.img(d), 'n': atlas.img(normal), 's': atlas.img(spec_), 'e': Image.new('RGB', (64, 32))}
    for k, v in maps.items():
        (OUT / f'crcca_svhood_{k}.dds').write_bytes(atlas.dxt1_dds(v))
        print('wrote', OUT / f'crcca_svhood_{k}.dds', v.size)


if __name__ == '__main__':
    main()
