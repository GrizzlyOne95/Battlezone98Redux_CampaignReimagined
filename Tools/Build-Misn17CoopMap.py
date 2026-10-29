"""Build Tapping the Core from the original 1.5 map, with preplaced defenses.

The stock minefield and towers exist from load, avoiding proximity pop-in.
Terrain is the unsmoothed CR heightmap plus Redux companion files.
"""
from pathlib import Path
import argparse
import copy
import importlib.util
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def build(source, game, toolbox):
    sys.path.insert(0, str(toolbox))
    from battlezone.bzn.bz1 import read_bzn, write_bzn
    from battlezone.archives.zfs import ZFSArchive
    from battlezone.terrain.hg2 import read_hg2
    spec = importlib.util.spec_from_file_location('coopmap', ROOT/'Tools/Build-CoopMap.py')
    base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
    base.ENEMY_TEAM = 6
    base.CLEAR_COMMANDS.add('misn17')
    base.STRIP_UNNAMED_PATHS.add('misn17')
    result = read_bzn(base.build(base.convert(source, toolbox), 'misn17').encode('latin-1'))
    arc = ZFSArchive(game/'bzone.zfs')
    for ext in ('trn', 'mat', 'lgt'):
        (ROOT/'Missions'/f'misn17.{ext}').write_bytes(arc.read(f'misn17.{ext}'))
    (ROOT/'Missions/misn17.hg2').write_bytes(subprocess.check_output(
        ['git', 'show', 'ce18e89:Missions/misn17.hg2'], cwd=ROOT))
    _, heights = read_hg2(ROOT/'Missions/misn17.hg2')
    paths = {p['label'].value.decode(): p for p in result.paths if 'label' in p}
    # DLL labels mine50/51 do not exist in the shipped map. 1.5 uses 55/56.
    for alias, original in (('mine50','mine55'), ('mine51','mine56')):
        p = copy.deepcopy(paths[original])
        p['label'].value = alias.encode(); p['label.size'].value = len(alias)
        result.paths.append(p); paths[alias] = p
    templates = {
        'hbptow': next(o for o in result.objects if o.prjid == 'hbfact'),
        'crfmine': next(o for o in read_bzn(arc.read('misn16.bzn')).objects if o.prjid == 'boltmine'),
    }
    seq = result.header['seq_count'].value
    used = {o.fields['obj_addr'].value for o in result.objects}
    for odf, path, label in ([('hbptow', f'geizer{i}', f'cr17_tower{i}') for i in range(1,8)] +
                             [('crfmine', f'mine{i}', f'cr17_mine{i}') for i in range(1,55)]):
        o = copy.deepcopy(templates[odf]); o.fields['PrjID'].value = odf.encode()
        x,z = paths[path]['points'].value[0]
        y = float(heights[round((z-97280)/5), round(x/5)])*.1
        addr = 0x9000+seq
        assert addr not in used
        used.add(addr)
        for k,v in [('seqno',seq),('seqNo',seq),('obj_addr',addr),('label',label.encode()),
                    ('team',6),('perceivedTeam',6),('isUser',0),('healthRatio',1.),
                    ('curHealth',7000 if odf=='hbptow' else 1000),
                    ('maxHealth',7000 if odf=='hbptow' else 1000)]:
            if k in o.fields: o.fields[k].value=v
        o.fields['transform'].value=(1.,0.,0.,0.,1.,0.,0.,0.,1.,x,y,z)
        for k in ('pos','pos2'):
            if k in o.fields: o.fields[k].value=[(x,y,z)]
        for k,f in o.fields.items():
            if k in ('v','omega','Accel'): f.value=[(0.,0.,0.)]
            if k in ('what','where','who','priority') or k.endswith(('.what','.where','.who','.priority')):
                f.value=bytes(4) if isinstance(f.value,bytes) else 0
        result.objects.append(o); seq+=1
    # Scrapfields reuse a stock label; label-based co-op resolution needs uniqueness.
    seen=set()
    for i,o in enumerate(result.objects):
        if o.label in seen and o.label:
            o.fields['label'].value=f'cr17_scrap{i}'.encode()
        seen.add(o.label)
    result.header['seq_count'].value=seq
    result.header['#objects'].value=len(result.objects)
    data=write_bzn(result,2016,binary=False,preserve_spelling=False)
    checked=read_bzn(data)
    assert len(checked.objects)==109
    assert all(o.prjid=='pspwn_1' or o.fields['team'].value not in (2,3,4) for o in checked.objects)
    (ROOT/'Missions/misn17cr.bzn').write_bytes(data)
    print('Built misn17: 109 objects, seven towers, 54 mines, four human starts')


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source',type=Path,required=True)
    ap.add_argument('--game',type=Path,required=True)
    ap.add_argument('--toolbox',type=Path,default=ROOT.parent/'Battlezone98_Modding_Toolbox')
    a=ap.parse_args(); build(a.source,a.game,a.toolbox)
