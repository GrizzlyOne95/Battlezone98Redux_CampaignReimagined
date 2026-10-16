"""Native map, ownership, listing, ODF and Lua-authority invariants for the shared solo/co-op misn14 rework."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn14.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('latin-1').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn and 'TerrainName = misn14\n' in bzn
assert '[AiMission]' in bzn, 'the native AiMission block must stay: the CCA AIP needs it'
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks)
teams, seqs, enemies, spawns, labels = [], [], 0, {}, {}
for block in blocks:
    odf = re.search(r'PrjID \[1\] =\n([^\n]+)', block)[1]
    team = int(re.search(r'team \[1\] =\n(\d+)', block)[1])
    seqs.append(int(re.search(r'seqno \[1\] =\n(\d+)', block)[1]))
    label = re.search(r'^label = (.*)$', block, re.M)
    if label:
        labels.setdefault(label[1], []).append((odf, team))
    if odf == 'pspwn_1':
        teams.append(team)
        assert f'label = coop_spawn{team}\n' in block
        positions = re.findall(r'pos \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', block)
        spawns[team] = tuple(map(float, positions[0]))
        for field in ('v', 'omega', 'Accel'):
            motion = re.search(r' ' + field + r' \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', block)
            assert tuple(map(float, motion.groups())) == (0, 0, 0), 'Spawn buoys must not carry copied motion'
    else:
        assert team not in (2, 3, 4, 6, 7), 'Authored object occupies a guest/Fury/support team: ' + odf
    if team == 5:
        enemies += 1
        assert re.search(r'perceivedTeam \[1\] =\n5\n', block), 'CCA objects must be perceived as team 5'
assert sorted(teams) == [1, 2, 3, 4] and enemies == 13, 'the 13 authored CCA objects are team 5'
EXPECTED = {'avrecy-1_recycler': ('avrecy', 1), 'svrecy-1_recycler': ('svrecy', 5),
            'sbbarr0_i76building': ('sbbarr', 5), 'svmuf0_factory': ('svmuf', 5),
            'sblpow1_powerplant': ('sblpow', 5), 'sblpow55_powerplant': ('sblpow', 5),
            'sbtowe0_turret': ('sbtowe', 5), 'sbtowe1_turret': ('sbtowe', 5), 'sbtowe55_turret': ('sbtowe', 5),
            'sbtowe56_turret': ('sbtowe', 5), 'player0_wingman': ('player', 1)}
for n in range(4):
    EXPECTED[f'apcamr{n}_camerapod'] = ('apcamr', 1)
for name, (odf, team) in EXPECTED.items():
    assert labels.get(name) == [(odf, team)], 'authored label wrong or not unique: ' + name
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert 15 < math.hypot(b[0] - a[0], b[2] - a[2]) < 30, 'Human starts must be a short step apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
path_names = set(re.findall(r'\[AiPath\]\n(?:[^\n]*\n){0,4}?label = (\S+)\n', bzn))
for name in ['alien%d' % n for n in range(1, 7)] + ['rescue1', 'rescue2', 'rescue3', 'escape', 'cam_path1',
             'cam_path2', 'camera_path'] + ['help%d' % n for n in range(1, 10)]:
    assert name in path_names, 'script path missing from the map: ' + name

for suffix in ('hg2', 'lgt', 'trn', 'mat', 'vxt'):
    assert (root / f'Missions/misn14.{suffix}').is_file(), 'missing companion: misn14.' + suffix
trn = (root / 'Missions/misn14.trn').read_text(encoding='latin-1')
assert 'titan.map' in trn.lower() and 'ti_detail_atlas' in trn, "Redux's own Titan terrain description"
assert len((root / 'Missions/misn14.mat').read_bytes()) == 131072
assert (root / 'Missions/misn14.vxt').read_text(encoding='utf-8').splitlines() == ['avtank ,', 'avfimp ,', 'avltnk ,', 'avrckt ,', 'avhraz ,', 'avwalk ,']

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn14.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Assets/Graphics/misn14.bmp').read_bytes()[:2] == b'BM'
des = (root / 'misn14.des').read_text()
assert len(des.strip()) <= 300 and 'Texas' in des and 'Utah' not in des, 'the briefing names the Recycler Texas'
campaign = (root / 'Config/crcampgn.ini').read_text().replace('\r\n', '\n')
section = re.search(r'\[MISSION13\]\n((?:[^\[\n][^\n]*\n)+)', campaign)[1]
assert 'missionBZN = "misn14.bzn"' in section and 'planet = "titan"' in section
assert 'voice = "misn1422.wav"' in section, 'the Grizzly One retrospective (exe-hardcoded misn1422)'

# The commandable NSDF Fury: a full ODF (Redux has no ODF inheritance) on the stock avsav mesh.
odf = (root / 'ODF/avsav14.odf').read_text()
for key in ('baseName = "avsav"', 'classLabel = "wingman"', 'aiName = "TankFriend"', 'aiName2 = "TankEnemy"',
            'maxHealth = 3500', 'weaponName1 = "gbolt"', '[CraftClass]', '[HoverCraftClass]', 'velocForward = 25.0'):
    assert key in odf, 'avsav14.odf: ' + key
assert 'SAVFriend' not in re.sub(r'//[^\n]*', '', odf), 'SAVFriend is not a registered Redux AI process'

raw_lua = (root / 'Scripts/misn14.lua').read_text().replace('\r\n', '\n')
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
lua = re.sub(r'--[^\n]*', '', lua)
assert 'local LEADER_TEAM, ENEMY_TEAM, FURY_TEAM, SURVIVOR_TEAM = 1, 5, 6, 7' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'spawns use team constants'
assert not re.search(r'\b(SetScrap|AddPilot|SetPilot|AddScrap)\(\s*[234]\s*[,)]', lua)
assert len(re.findall(r'\bSetAIControl\(', lua)) == 1 and re.search(r'(?m)^SetAIControl\(ENEMY_TEAM, true\)$', lua)
assert lua.index('SetAIControl(ENEMY_TEAM, true)') < lua.index('function Start()')
assert re.findall(r'SetAIP\([^)]*\)', lua) == ['SetAIP("misn14.aip", ENEMY_TEAM)']
assert 'PlayerPilotMode' not in lua and 'aiCore' not in lua, 'neither Pilot Mode nor aiCore belongs in misn14'
assert not re.search(r'(?<![.\w])Formation\(', lua), 'stock Lua Formation() is broken; use SetCommand FORMATION'
assert 'exu.DisableStartingRecycler()' in lua and 'rallyPoints = { [0] = "avrecy-1_recycler" }' in lua
assert 'respawn.SetRallyPoints({})' in lua
update = lua.index('function Update(dt)')
assert lua.index('if not CRCoop.IsAuthority() then return end', update) < lua.index('M.player = GetPlayerHandle()', update)
body = lua[update:]
assert 'M.player' not in body.replace('M.player = GetPlayerHandle()', ''), 'nothing reads the host-only handle'
assert 'local FURY_SQUAD_ODF = "avsav14"' in lua and 'FURY_SQUAD_PER_HUMAN = 2' in lua
assert 'FURY_LIVE_CAP = 12' in lua and 'FURY_CLEAR_M = 400.0' in lua and 'FURY_TANK_FROM_WAVE = 4' in lua
assert 'SetTeamNum(entry.unit, FURY_TEAM)' in lua, 'loss of control re-teams the squad'
for line in ('misn1402.wav', 'misn1423.wav', 'misn1424.wav', 'misn1425.wav', 'misn1426.wav', 'misn1427.wav',
             'misn1420.wav'):
    assert f'"{line}"' in lua, 'restored line missing: ' + line
assert 'require, "CRTitanWeather"' in lua and 'pcall(TitanWeather.MissionHook' in lua, 'single guarded weather hook'
assert 'Environment.Init({ nativeBaseline = true })' in lua, 'Titan captures the native baseline'
assert 'Environment.BindWeatherSensors("Titan", TitanSensorDirector)' in lua, 'the shared sensor policy binds the Titan director'
for event, call in (('update', 'Environment.Update'), ('object', 'Environment.OnObjectCreated')):
    assert f'if event == "{event}" then {call}' in lua, 'Titan forwards the Environment lifecycle'
assert 'if IsAlive(guy) and IsOdfBase(guy, "aspilo") then' in lua, 'SetIndependence allowlisted to aspilo'
assert (root / 'Docs/MISN14_COOP.md').is_file()

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn14.ini', 'Missions/misn14.vxt', 'Assets/Graphics/misn14.bmp', 'misn14.des',
               'Missions/misn14.bzn', 'Missions/misn14.hg2', 'Missions/misn14.trn', 'Missions/misn14.mat',
               'Missions/misn14.lgt', 'Scripts/misn14.lua', 'ODF/avsav14.odf']:
    assert members.get(source) == Path(source).name, 'file must be admitted by the shipping manager: ' + source
assert lock['count'] == len(lock['files'])
print('misn14 co-op native map, team isolation, Fury ODF, authority and lobby contract passed')
