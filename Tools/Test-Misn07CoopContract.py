"""Native map, ownership, listing and Lua-authority invariants for shared solo/co-op misn07."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn07.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
assert 'TerrainName = misn07\n' in bzn
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks) == 320
teams, seqs, enemies, spawns, labels = [], [], 0, {}, set()
for block in blocks:
    odf = re.search(r'PrjID \[1\] =\n([^\n]+)', block)[1]
    team = int(re.search(r'team \[1\] =\n(\d+)', block)[1])
    seqs.append(int(re.search(r'seqno \[1\] =\n(\d+)', block)[1]))
    label = re.search(r'^label = (.*)$', block, re.M)
    if label:
        labels.add(label[1])
    if odf == 'pspwn_1':
        teams.append(team)
        assert f'label = coop_spawn{team}\n' in block, 'Spawn buoy label must match its team'
        positions = re.findall(r'pos \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', block)
        assert len(positions) == 2 and positions[0] == positions[1], 'Spawn position must be consistent'
        spawns[team] = tuple(map(float, positions[0]))
        for axis, value in zip('xyz', spawns[team]):
            assert float(re.search(r'  posit_' + axis + r' \[1\] =\n([^\n]+)', block)[1]) == value
        for field in ('v', 'omega', 'Accel'):
            motion = re.search(r' ' + field + r' \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', block)
            assert tuple(map(float, motion.groups())) == (0, 0, 0), 'Spawn buoys must not carry copied motion'
    else:
        assert team not in (2, 3, 4), 'Authored object occupies a guest team'
    if team == 5:
        enemies += 1
        assert re.search(r'perceivedTeam \[1\] =\n5\n', block), 'CCA objects must be perceived as team 5'
assert sorted(teams) == [1, 2, 3, 4] and enemies == 48
# The disguised rendezvous tanks sat on guest team 3: the map drops them, the Lua convoys replacements in.
assert 'avtank2' not in labels and 'avtank3' not in labels, 'team-3 rendezvous tanks must be removed from the map'
assert {'avtank1', 'avfigh1', 'cam3', 'camera_geyser', 'volcano_geyz1', 'parked1', 'parked2', 'parked3'} <= labels
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert abs(math.hypot(b[0] - a[0], b[2] - a[2]) - 25) < 0.1, 'Human starts must be 25 m apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
# Paths the restored arc and convoy read must exist (m000 is deliberately absent).
for path in ['cam_spawn1', 'cam_spawn2', 'cam_spawn3', 'cam_spawn4', 'cam_spawn5', 'cam_spawn6',
             'camera_path1', 'camera_path2', 'test_tank_spawn', 'm001', 'm110', 'edge_path', 'turret1_spot']:
    assert f'label = {path}\n' in bzn, 'path missing from the converted map: ' + path
assert 'label = m000\n' not in bzn

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn07.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Missions/misn07.vxt').read_text().splitlines() == ['avtank ,', 'avfimp ,']
assert (root / 'Assets/Graphics/misn07.bmp').read_bytes()[:2] == b'BM'
assert len((root / 'misn07.des').read_text().strip()) <= 300

campaign = (root / 'Config/crcampgn.ini').read_text()
assert re.search(r'\[MISSION6\][^\[]*missionBZN = "misn07\.bzn"', campaign), 'Campaign must launch the shared BZN'

raw_lua = (root / 'Scripts/misn07.lua').read_text()
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
lua = re.sub(r'--[^\n]*', '', lua)
assert 'local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'Hostile/support spawns must use team constants'
assert len(re.findall(r'BuildObject\("\w+",\s*ENEMY_TEAM,', lua)) == 26
assert len(re.findall(r'BuildObject\("\w+",\s*SUPPORT_TEAM,', lua)) == 2
assert re.search(r'AddScrap\(ENEMY_TEAM,\s*60\)|AddScrap\(ENEMY_TEAM,60\)', lua) and 'SetAIP("misn07.aip",ENEMY_TEAM)' in lua
assert 'CRCoop.ApplyCoopAlliances(ENEMY_TEAM)' in lua
update = lua.index('function Update(dt)')
gate = lua.index('if not CRCoop.IsAuthority() then return end', update)
assert gate < lua.index('M.user=GetPlayerHandle()', update), 'Authority gate must precede the mission body'
assert 'CRCoop.AnyPlayerSatisfies' in lua and 'CRCoop.ForEachPlayerHandle' in lua
assert 'IsInfo' not in lua, 'misn07 reads no IsInfo state'
# No raw player-handle tests survive in the mission body.
body = lua[update:]  # comments already stripped; everything after the authority gate
assert not re.search(r'Distance\(M\.user,', body), 'player-handle distance tests must use the any-player helpers'
assert not re.search(r'Attack\(M\.\w+,M\.user\)', body), 'Attack targets must be the nearest player'
assert 'GetHandle("avtank2")' in raw_lua and 'RENDEZVOUS_CONVOY' in raw_lua

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn07.ini', 'Missions/misn07.vxt', 'Assets/Graphics/misn07.bmp', 'misn07.des',
               'Missions/misn07.bzn', 'Missions/misn07.hg2', 'Missions/misn07.trn', 'Missions/misn07.mat',
               'Missions/misn07.lgt', 'Scripts/misn07.lua']:
    assert members.get(source) == Path(source).name, 'Map/lobby file must be admitted by the shipping manager: ' + source
print('misn07 co-op native map, team isolation, authority and lobby contract passed')
