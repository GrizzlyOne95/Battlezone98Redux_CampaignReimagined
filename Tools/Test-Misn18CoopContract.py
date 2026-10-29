"""Mission 18 co-op map, listing, campaign binding, storm-interface and restoration contract."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
bzn_raw = (ROOT / 'Missions/misn18cr.bzn').read_bytes()
text = bzn_raw.decode('latin-1').replace('\r\n', '\n')
assert b'\n' not in bzn_raw.replace(b'\r\n', b''), 'native BZN line endings'
assert 'TerrainName = misn18\n' in text and 'name = MultSTMission\n' in text
assert 'msn_filename = misn18cr.bzn' in text

# ---------------------------------------------------------------- objects and teams
blocks = text.split('[GameObject]\n')[1:]
assert len(blocks) == 26 and re.search(r'^size \[1\] =\n26$', text, re.M), '22 authored objects + 4 start buoys'
objects = {}
starts = []
for block in blocks:
    label = re.search(r'^label = (.*)$', block, re.M)[1]
    odf = re.search(r'^PrjID \[1\] =\n(.*)$', block, re.M)[1]
    team = int(re.search(r'^team \[1\] =\n(\d+)$', block, re.M)[1])
    perceived = int(re.search(r'^perceivedTeam \[1\] =\n(\d+)$', block, re.M)[1])
    assert label not in objects, 'unique object identity: ' + label
    objects[label] = (odf, team)
    if odf == 'pspwn_1':
        starts.append(team)
        assert re.search(r'^ v \[1\] =\n  x \[1\] =\n0\n  y \[1\] =\n0\n  z \[1\] =\n0$', block, re.M), 'start buoys are still'
    else:
        assert team in (0, 1, 6), 'guest and CCA slots stay clear: ' + label
        assert perceived == team, 'perceived team follows the move: ' + label
assert sorted(starts) == [1, 2, 3, 4]
assert objects['hbtran0038_i76building'] == ('hbtran00', 6)
for n in range(49, 53):
    assert objects[f'hbtrn200{n}_i76building'] == ('hbtrn200', 6), 'Fury thrusters'
assert not any(odf in ('hvsav', 'hvsat') for odf, _ in objects.values()), 'Furies are script-built'
assert objects['avrecy2_recycler'] == ('avrecy', 1)
assert objects['scrapcam'][0] == 'sscr_1' and objects['scrapcam2'][0] == 'sscr_1'
assert sum(1 for label in objects if label.startswith('cr18_scrap')) == 7, 'duplicate stock scrapfield labels renamed'
assert not re.search(r'^label = sfield0_scrapfield$', text, re.M)

# ---------------------------------------------------------------- paths
paths = text.split('[AiPath]\n')
path_names = []
for path in paths[1:]:
    size = int(re.search(r'^size \[1\] =\n(\d+)$', path, re.M)[1])
    name = re.search(r'^label = (.*)$', path.split('pointCount', 1)[0], re.M)
    assert name and size == len(name[1].encode('latin-1')), 'native path label allocation size'
    path_names.append(name[1])
assert len(path_names) == 46 and len(set(path_names)) == 46

# ---------------------------------------------------------------- the Lua only names real map content
lua_full = (ROOT / 'Scripts/misn18cr.lua').read_text(encoding='utf-8')
live = re.sub(r'(?ms)^-- CR [^\n]* >>\n.*?^-- CR [^\n]* <<\n?', '', lua_full)
live = re.sub(r'--\[==\[.*?\]==\]', '', live, flags=re.S)
used = set(re.findall(r'BuildObject\("\w+", 2, "(\w+)"\)', live))
used |= set(re.findall(r'Goto\([^,]+, "(\w+)"\)', live))
used |= set(re.findall(r'Distance\(M\.player, "(\w+)"\)', live))
used |= set(re.findall(r'CameraPath\("(\w+)"', live))
handles = set(re.findall(r'GetHandle\("(\w+)"\)', live))
assert handles <= set(objects), 'every GetHandle label is a map object: ' + str(handles - set(objects))
assert used - set(path_names) == {'spawn1'}, 'only the DLL\'s own phantom path is missing: ' + str(used - set(path_names))
runtime = (ROOT / 'Scripts/CRMisn18.lua').read_text(encoding='utf-8')
assert 'where=="spawn1" then where="spawn1b"' in runtime and 'spawn1b' in path_names
# What the script never touches is documented, not silently dropped (Docs/MISN18_COOP.md).
doc = (ROOT / 'Docs/MISN18_COOP.md').read_text(encoding='utf-8')
unreferenced_paths = set(path_names) - used - {'spawn1'}
assert unreferenced_paths == {'blastoffcam', 'edge_path', 'transdestroyedcam'}, unreferenced_paths
for name in sorted(unreferenced_paths | {'spawn1'}):
    assert '`' + name + '`' in doc, 'undocumented unused map content: ' + name
unreferenced_objects = set(objects) - handles
for label in ('avmuf2_factory', 'avtank0_wingman', 'avtank1_wingman', 'eggeizr11_geyser', 'eggeizr12_geyser', 'myCar_hover'):
    assert label in unreferenced_objects and label in doc, 'undocumented unreferenced object: ' + label

# ---------------------------------------------------------------- terrain and listing
for ext in ('trn', 'mat', 'lgt', 'hg2'):
    assert (ROOT / 'Missions' / f'misn18.{ext}').stat().st_size > 0, ext
assert (ROOT / 'Missions/misn18.hg2').stat().st_size == 1048588, 'unsmoothed 1.5 heightmap'
ini = (ROOT / 'Config/misn18cr.ini').read_text(encoding='utf-8')
assert 'missionName = "CR 17: The Ultimate Quake Coop"' in ini and 'mapType = "multiplayer"' in ini
assert 'minPlayers = "2"' in ini and 'maxPlayers = "4"' in ini and 'gameType = "S"' in ini
des = (ROOT / 'misn18cr.mpdes').read_bytes()
assert len(des) <= 300 and des.endswith(b'\r\n') and b'\n' not in des.replace(b'\r\n', b''), 'des: <= 300 bytes, CRLF'
assert b'thruster' in des and b'transport' in des, 'briefing matches the transport/thrusters mission'
assert '!misn18cr.mpdes' in (ROOT / '.gitignore').read_text(encoding='utf-8').splitlines()
assert (ROOT / 'Assets/Graphics/misn18cr.bmp').read_bytes()[:2] == b'BM'
vxt = (ROOT / 'Missions/misn18cr.vxt').read_bytes().decode('ascii').split('\r\n')
assert vxt == ['avtank ,', 'avfimp ,', 'avltnk ,', 'avrckt ,', 'avhraz ,', ''], 'Tank, Scout, Light Tank, Rocket Tank, Bomber'
for row in vxt[:-1]:
    assert (ROOT / 'ODF' / (row.split()[0] + '.odf')).is_file(), 'starting ship ODF ships: ' + row
campaign = (ROOT / 'Config/crcampgn.ini').read_text(encoding='utf-8')
assert re.search(r'\[MISSION17\]\n(?:;[^\n]*\n)?missionName = "The Ultimate Quake"\nmissionBZN = "misn18cr.bzn"\nplanet = "titan"\nvoice = "misn1800.wav"',
                 campaign.replace('\r\n', '\n')), 'campaign entry after MISSION16'
for line in ('misn1817', 'misn1818', 'misn1800'):
    assert (ROOT / 'Text' / (line + '.txt')).is_file(), 'subtitle: ' + line
workflow = (ROOT / '.github/workflows/campaign-validation.yml').read_text(encoding='utf-8')
for test in ('Test-Misn18.lua', 'Test-Misn18Coop.lua', 'Test-Misn18SourceParity.py', 'Test-Misn18CoopContract.py'):
    assert test in workflow, 'CI runs ' + test

# ---------------------------------------------------------------- restorations
assert 'AudioMessage("misn1817.wav")' in lua_full and 'misn1803.wav' not in lua_full + runtime
assert 'misn1704.wav' in live and '["misn1704.wav"] = "misn1818.wav"' in runtime
assert 'UpdateEarthQuake(math.min(M.quake_level * 3.0, QUAKE_CAP))' in lua_full
assert 'CameraPath("transdestroyedcam"' in runtime and 'transdestroyedcam' in path_names, 'restored transport shot'
assert 'M.sav2 = BuildObject("hvsat", 2, "spawnreturn")' in lua_full and 'M.sav3 = BuildObject("hvsav", 2, "spawnreturn")' in lua_full

# ---------------------------------------------------------------- storm interface contract
for phase in ('opening', 'search', 'found', 'core1', 'core2', 'core3', 'collapse', 'final', 'won', 'lost'):
    assert f'`{phase}`' in doc, 'storm phase documented: ' + phase
    assert f'"{phase}"' in runtime, 'storm phase emitted: ' + phase
assert '## Storm interface' in doc
assert 'pcall(require, "CRStorm18")' in runtime
assert not (ROOT / 'Scripts/CRStorm18.lua').exists() or 'SetPhase' in (ROOT / 'Scripts/CRStorm18.lua').read_text(encoding='utf-8'), \
    'when the storm module ships it must implement SetPhase'

# ---------------------------------------------------------------- shipping membership
members = {e['source'].replace('\\', '/'): e['runtime'] for e in json.loads((ROOT / 'Shipping/shipping.lock.json').read_text(encoding='utf-8'))['files']}
for path in ('Scripts/misn18cr.lua', 'Scripts/CRMisn18.lua', 'Missions/misn18cr.bzn', 'Missions/misn18.trn',
             'Missions/misn18.hg2', 'Missions/misn18.mat', 'Missions/misn18.lgt', 'Missions/misn18cr.vxt',
             'Config/misn18cr.ini', 'misn18cr.mpdes', 'Assets/Graphics/misn18cr.bmp'):
    assert members.get(path) == Path(path).name, 'shipping membership: ' + path
print('misn18 map, teams, paths, listing, campaign entry, restorations, storm contract and shipping passed')
