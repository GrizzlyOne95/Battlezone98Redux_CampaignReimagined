"""Native map and ownership invariants for the shared solo/co-op mission."""
from pathlib import Path
import configparser
import json
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn05.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks) == 43
teams, seqs, enemies = [], [], 0
for block in blocks:
    odf = re.search(r'PrjID \[1\] =\n([^\n]+)', block)[1]
    team = int(re.search(r'team \[1\] =\n(\d+)', block)[1])
    seqs.append(int(re.search(r'seqno \[1\] =\n(\d+)', block)[1]))
    if odf == 'pspwn_1':
        teams.append(team)
        positions = re.findall(r'pos \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', block)
        expected = (1538.26 + (team - 1) * 25, 26.358, 99778.9)
        assert len(positions) == 2 and all(tuple(map(float, pos)) == expected for pos in positions), 'Human starts must share the authored start area'
        for axis, value in zip('xyz', expected):
            assert float(re.search(r'  posit_' + axis + r' \[1\] =\n([^\n]+)', block)[1]) == value
        for field in ('v', 'omega', 'Accel'):
            motion = re.search(r' ' + field + r' \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', block)
            assert tuple(map(float, motion.groups())) == (0, 0, 0), 'Spawn buoys must not carry copied motion'
    else:
        assert team not in (2, 3, 4), 'Authored object occupies a guest team'
    if team == 5:
        enemies += 1
        assert re.search(r'perceivedTeam \[1\] =\n5\n', block)
assert sorted(teams) == [1, 2, 3, 4] and enemies == 4
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
assert 'player_path' not in bzn, 'Native multiplayer would create a stray player craft'

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn05.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Missions/misn05.vxt').read_text(encoding='utf-8').splitlines() == ['avtank ,', 'avfimp ,', 'avltnk ,']
assert (root / 'Assets/Graphics/misn05.bmp').read_bytes()[:2] == b'BM'
assert len((root / 'misn05.des').read_text().strip()) <= 300

lua = (root / 'Scripts/misn05.lua').read_text()
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', lua, flags=re.S)
assert 'local LEADER_TEAM, ENEMY_TEAM, MINE_TEAM, SUPPORT_TEAM = 1, 5, 6, 7' in lua
assert 'pcall(BuildObject, odf, ENEMY_TEAM, spawn)' in lua
assert 'BuildObject("cromine", MINE_TEAM, pathName)' in lua
assert 'BuildObject("avtank", SUPPORT_TEAM, spawnPos)' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua)
assert 'aiCore.SetStrategyFromAip("misn05.aip", ENEMY_TEAM)' in lua
# misn05 keeps the aiCore Lua brain for team 5 (custom strategy, maintain list, perimeter), so the
# engine's native AI must not be attached: no SetAIControl anywhere, and no native SetAIP call.
_ai_src = (root / 'Scripts/misn05.lua').read_text()
_ai_active = re.sub(r'--[^\n]*', '', re.sub(r'--\[(=*)\[.*?\]\1\]', '', _ai_src, flags=re.S))
assert not re.search(r'SetAIControl\(', _ai_active), 'misn05 uses the Lua brain: no SetAIControl'
assert not re.search(r'(?<![\w.])SetAIP\(', _ai_active), 'misn05 must not call the native SetAIP'
assert 'aiCore.SetStrategyFromAip' in _ai_active
assert lua.index('if not CRCoop.IsAuthority() then return end', lua.index('function Update()')) < lua.index('-- Game Start / Initial Setup')
assert 'CRCoop.AnyPlayerSatisfies' in lua

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn05.ini', 'Missions/misn05.vxt', 'Assets/Graphics/misn05.bmp', 'misn05.des']:
    assert members.get(source) == Path(source).name, 'New lobby asset must be admitted by the shipping manager: ' + source
print('misn05 co-op native map, team isolation, authority and lobby contract passed')
