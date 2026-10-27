"""Build CR misn15 from the shipped misn15b layout, with visible stranded units.

Terrain companions are copies of CR's misn15b companions under the runtime
misn15 stem. Templates come from already checked-in CR maps; no game objects
are invented by hand. Run with --source pointing to stock misn15b.bzn.
"""
from pathlib import Path
import argparse
import copy
import importlib.util
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def build(source, toolbox):
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.bz1 import read_bzn, write_bzn
    spec = importlib.util.spec_from_file_location('coop_map', ROOT/'Tools/Build-CoopMap.py')
    base = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(base)
    original = read_bzn(source)
    assert original.terrain_name == 'misn15b.bzn', 'Use the shipped misn15b map'
    base.RETEAM_LABELS['misn15'] = {label: (7, 7) for label in
        ('svtank0_wingman', 'svtank1_wingman', 'svapc0_apc')}
    base.CLEAR_COMMANDS.add('misn15')
    text = base.convert(source, toolbox).replace('TerrainName = misn15b.bzn\n', 'TerrainName = misn15.bzn\n')
    text = text.replace('msn_filename = misn15b.bzn\n', 'msn_filename = misn15.bzn\n')
    result = read_bzn(base.build(text, 'misn15').encode('latin-1'))
    templates = {}
    for name in ('misn09', 'misn14'):
        for obj in read_bzn(ROOT/'Missions'/f'{name}.bzn').objects:
            templates.setdefault(obj.prjid, obj)
    templates['avapc'] = next(o for o in original.objects if o.prjid == 'svapc')
    templates['avartl'] = templates['svartl']
    paths = {p['label'].value.decode(): p['points'].value for p in result.paths if 'label' in p}
    from battlezone.terrain.hg2 import read_hg2
    # The shared codec supplies a numpy array of canonical low-13-bit heights.
    heights = read_hg2(ROOT/'Missions/misn15b.hg2')
    if isinstance(heights, tuple):
        heights = heights[-1]
    trn = (ROOT/'Missions/misn15b.trn').read_text()
    min_x = float(re.search(r'(?im)^MinX\s*=\s*([^\r\n]+)', trn)[1])
    min_z = float(re.search(r'(?im)^MinZ\s*=\s*([^\r\n]+)', trn)[1])
    width = float(re.search(r'(?im)^Width\s*=\s*([^\r\n]+)', trn)[1])
    depth = float(re.search(r'(?im)^Depth\s*=\s*([^\r\n]+)', trn)[1])
    serial = result.header['seq_count'].value
    used = {o.fields['obj_addr'].value for o in result.objects if 'obj_addr' in o.fields}
    specs = [('avscav','scav3here','cr15_nw_scav'), ('avapc','mufhere','cr15_nw_apc'),
             ('avturr','turhere','cr15_nw_turret'), ('avscav','scav1here','cr15_ne_scav1'),
             ('avscav','scav2here','cr15_ne_scav2'), ('avartl','arthere','cr15_ne_artillery')]
    for odf, point, label in specs:
        obj = copy.deepcopy(templates[odf])
        x, z = paths[point][0]
        row = min(heights.shape[0]-1, max(0, round((z-min_z)/depth*heights.shape[0])))
        col = min(heights.shape[1]-1, max(0, round((x-min_x)/width*heights.shape[1])))
        y = float(heights[row, col])*0.1 + 1.0
        for key, value in [('PrjID',odf.encode()), ('label',label.encode()), ('team',7),
                           ('perceivedTeam',7), ('seqno',serial), ('seqNo',serial)]:
            if key in obj.fields: obj.fields[key].value = value
        obj.fields['pos'].value = [(x,y,z)]
        transform = list(obj.fields['transform'].value)
        transform[9:] = [x,y,z]
        obj.fields['transform'].value = tuple(transform)
        addr = 0x4000 + serial
        while addr in used: addr += 1
        obj.fields['obj_addr'].value = addr
        used.add(addr)
        for key, f in obj.fields.items():
            if key.endswith(('.what','.where','.who','.priority')) or key in ('what','where','who','priority'):
                f.value = bytes(4) if isinstance(f.value, bytes) else 0
            if key in ('v','omega','Accel'): f.value = [(0.0,0.0,0.0)]
            if key in ('curPilot',): f.value = b'aspilo'
        result.objects.append(obj)
        serial += 1
    result.header['seq_count'].value = serial
    result.header['#objects'].value = len(result.objects)
    # Unreferenced duplicate editor labels are unsuitable network identities.
    for i,p in enumerate(result.paths):
        if 'label' in p and p['label'].value == b'path_1':
            p['label'].value = f'cr15_unused_path_{i}'.encode()
            # The native loader allocates from this serialized byte count.
            p['label.size'].value = len(p['label'].value)
    data = write_bzn(result, 2016, binary=False, preserve_spelling=False)
    # A modified Field can still carry the source text spelling; reparse the
    # canonical serialization to catch template/class and count errors now.
    checked = read_bzn(data)
    assert len(checked.objects) == 60
    assert all(p['label.size'].value == len(p['label'].value) for p in checked.paths if 'label' in p)
    for _,_,label in specs:
        assert sum(o.label == label for o in checked.objects) == 1
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', type=Path, required=True)
    ap.add_argument('--toolbox', type=Path, default=ROOT.parent/'Battlezone98_Modding_Toolbox')
    args = ap.parse_args()
    data = build(args.source, args.toolbox)
    (ROOT/'Missions/misn15.bzn').write_bytes(data)
    for ext in ('trn','mat','hg2','lgt'):
        (ROOT/'Missions'/f'misn15.{ext}').write_bytes((ROOT/'Missions'/f'misn15b.{ext}').read_bytes())
    print('Built misn15 from misn15b: six preplaced rescue units and four human starts')


if __name__ == '__main__': main()
