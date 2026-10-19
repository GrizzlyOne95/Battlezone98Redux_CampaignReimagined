"""Build the Mission 18 (The Ultimate Quake) co-op map from the original 1.5 BZN.

The 1.5 map is small (22 objects, 46 named paths). Build-CoopMap.py does the shared work (convert to the
Redux 2016 ASCII form, MultSTMission, four pspwn_1 start buoys); this wrapper adds the Mission 18 specifics:

  * the Fury transport, its four thrusters and every other authored team 2 object move to team 6 (the
    Fury team; team 5 is CCA), with perceivedTeam;
  * the seven scrapfields that all carry the stock label sfield0_scrapfield get unique cr18_scrap<n>
    labels (label-based co-op resolution needs unique labels);
  * the stock paths are kept untouched. The DLL also names a path "spawn1" that the 1.5 map does not
    contain; Scripts/CRMisn18.lua maps it to spawn1b (Docs/MISN18_COOP.md).

Terrain companions come from Redux's bzone.zfs; the heightmap is the unsmoothed 1.5 one from history
(`git show ce18e89:Missions/misn18.hg2`).
"""
from pathlib import Path
import argparse
import importlib.util
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = Path(r"C:\Users\iestu\Documents\GIT\Battlezone_Source\BZ1\1.5\Battlezone_Install\stock\misn18.bzn")
DEFAULT_GAME = Path(r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux")


def build(source, game, toolbox):
    sys.path.insert(0, str(toolbox))
    from battlezone.archives.zfs import ZFSArchive
    spec = importlib.util.spec_from_file_location('coopmap', ROOT / 'Tools/Build-CoopMap.py')
    base = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(base)
    base.ENEMY_TEAM = 6
    text = base.build(base.convert(source, toolbox), 'misn18')
    head, *objects = text.split('[GameObject]\n')
    serial = 0
    for index, block in enumerate(objects):
        if re.search(r'^label = sfield0_scrapfield$', block, re.M):
            serial += 1
            objects[index] = re.sub(r'^label = sfield0_scrapfield$', f'label = cr18_scrap{serial}', block,
                                    count=1, flags=re.M)
    assert serial == 7, serial
    text = head + ''.join('[GameObject]\n' + block for block in objects)
    paths = text.split('[AiPath]\n')[1:]
    assert len(paths) == 46
    object_labels = [re.search(r'^label = (\S+)$', block, re.M)[1] for block in objects]
    assert len(set(object_labels)) == len(object_labels), 'object labels must be unique'
    assert 'name = MultSTMission' in text and 'TerrainName = misn18\n' in text
    for team in ('2', '3', '4'):
        # Only the pspwn_1 start buoys may sit on guest teams.
        for block in text.split('[GameObject]\n')[1:]:
            if re.search(rf'^team \[1\] =\n{team}$', block, re.M):
                assert re.search(r'^PrjID \[1\] =\npspwn_1$', block, re.M), 'authored object on guest team ' + team
    (ROOT / 'Missions/misn18.bzn').write_bytes(text.replace('\n', '\r\n').encode('latin-1'))
    arc = ZFSArchive(game / 'bzone.zfs')
    for ext in ('trn', 'mat', 'lgt'):
        (ROOT / 'Missions' / f'misn18.{ext}').write_bytes(arc.read(f'misn18.{ext}'))
    (ROOT / 'Missions/misn18.hg2').write_bytes(subprocess.check_output(
        ['git', 'show', 'ce18e89:Missions/misn18.hg2'], cwd=ROOT))
    print('Built misn18: 26 objects (22 authored + 4 start buoys), 46 paths, Fury transport on team 6')


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    ap.add_argument('--game', type=Path, default=DEFAULT_GAME)
    ap.add_argument('--toolbox', type=Path, default=ROOT.parent / 'Battlezone98_Modding_Toolbox')
    a = ap.parse_args()
    build(a.source, a.game, a.toolbox)
