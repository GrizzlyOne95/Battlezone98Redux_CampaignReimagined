"""Export the Achilles (misn17) water mask into Scripts/CRJungle17Sites.lua.

Build-Misn17Jungle.py needs the ISDF Chronicles checkout to regenerate everything.
This exporter does not: it executes only the water model slice of that builder (the text
between its WATER-MODEL BEGIN/END markers, so there is one copy of the pool and stream
code), on the original heightmap, and writes only `watermask=` into the generated sites
module. No mesh, heightmap, material or other generated asset is touched.

    python Tools/Export-Misn17WaterMask.py            # write
    python Tools/Export-Misn17WaterMask.py --check    # fail if the file is stale

The slice is checked against References/Misn17Jungle/source-assets.json (pool cells,
stream paths and points) so a drifted model is refused rather than exported.
"""
from pathlib import Path
import argparse
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SITES = ROOT / 'Scripts' / 'CRJungle17Sites.lua'


def lua(v):
    if isinstance(v, dict):
        return '{' + ','.join(k + '=' + lua(x) for k, x in v.items()) + '}'
    if isinstance(v, (list, tuple)):
        return '{' + ','.join(lua(x) for x in v) + '}'
    return json.dumps(v)


def compute(toolbox):
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.bz1 import read_bzn
    from battlezone.terrain.hg2 import read_hg2
    from battlezone.terrain.mat import read_mat
    source = (ROOT / 'Tools' / 'Build-Misn17Jungle.py').read_text(encoding='utf-8').replace('\r\n', '\n')
    begin = source.index('    # WATER-MODEL BEGIN')
    end = source.index('    # WATER-MODEL END')
    model = textwrap.dedent(source[begin:end])
    # The builder's own namespace for this slice (its module-level helpers included).
    spec_ns = {'__name__': 'water_model', '__file__': str(ROOT / 'Tools' / 'Build-Misn17Jungle.py')}
    helpers = source[:source.index('def build(src,toolbox):')]
    exec(compile(helpers, 'Build-Misn17Jungle.py', 'exec'), spec_ns)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / 'Missions').mkdir()
        original = subprocess.check_output(['git', 'show', 'ce18e89:Missions/misn17.hg2'], cwd=ROOT)
        (root / 'Missions' / 'misn17.hg2').write_bytes(original)
        for name in ('misn17.mat', 'misn17cr.bzn'):
            shutil.copyfile(ROOT / 'Missions' / name, root / 'Missions' / name)
        spec_ns.update(ROOT=root, np=np, math=math, read_hg2=read_hg2, read_mat=read_mat, read_bzn=read_bzn)
        exec(compile(model, 'water-model', 'exec'), spec_ns)
    return spec_ns


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--toolbox', type=Path, default=ROOT.parent / 'Battlezone98_Modding_Toolbox')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()

    ns = compute(a.toolbox)
    reference = json.loads((ROOT / 'References/Misn17Jungle/source-assets.json').read_text(encoding='utf-8'))
    got = {'pool_cells': int(ns['pool_cells'].sum()), 'stream_paths': len(ns['paths']),
           'stream_points': len(ns['stream_points'])}
    for key, value in got.items():
        if reference[key] != value:
            sys.exit(f'water model drifted from the baked meshes: {key} {value} != {reference[key]}')
    mask = ns['water_mask'](ns['pool_cells'], ns['stream_points'], ns['r0'], ns['c0'], ns['ground'].shape)
    block = 'watermask=' + lua(mask)

    text = SITES.read_text(encoding='utf-8')
    if 'watermask=' in text:
        new = re.sub(r'watermask=\{.*?\}(?=,cascade=)', lambda m: block, text, count=1, flags=re.S)
    else:
        assert text.count(',cascade=') == 1
        new = text.replace(',cascade=', ',' + block + ',cascade=', 1)
    if a.check:
        if new != text:
            sys.exit('Scripts/CRJungle17Sites.lua watermask is stale; run Tools/Export-Misn17WaterMask.py')
        print('watermask up to date')
        return
    SITES.write_text(new, encoding='utf-8', newline='')
    print(f'watermask: {mask["cells"]} cells, {len(mask["rows"])} rows, {len(block)} bytes ({got})')


if __name__ == '__main__':
    main()
