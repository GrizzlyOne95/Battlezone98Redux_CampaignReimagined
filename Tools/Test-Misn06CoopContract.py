"""Native map, ownership, listing and Lua-authority invariants for shared solo/co-op misn06."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn06.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
assert 'TerrainName = misn06\n' in bzn
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks) == 169
teams, seqs, enemies, spawns = [], [], 0, {}
for block in blocks:
    odf = re.search(r'PrjID \[1\] =\n([^\n]+)', block)[1]
    team = int(re.search(r'team \[1\] =\n(\d+)', block)[1])
    seqs.append(int(re.search(r'seqno \[1\] =\n(\d+)', block)[1]))
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
assert sorted(teams) == [1, 2, 3, 4] and enemies == 26
rocket = [b for b in blocks if 'label = cr06_rocket\n' in b]
assert len(rocket) == 1 and 'PrjID [1] =\ncr06rok\n' in rocket[0]
assert 'team [1] =\n0\n' in rocket[0] and 'perceivedTeam [1] =\n0\n' in rocket[0]
assert 'maxHealth [1] =\n0\n' in rocket[0], 'Rocket fixture must not be a new combat target'
pad=next(b for b in blocks if 'label = sblpad0_i76building\n' in b)
def field(block,key):
    return float(re.search(r'^  '+key+r' \[1\] =\n([^\n]+)',block,re.M)[1])
# Measured stock Redux raised platform, converted from Ogre's mirrored X.
# The eight engine exits sit 25cm above its deck, directly over its centre.
for i,c in enumerate('xyz'):
    expected=field(pad,'posit_'+c)+sum(field(pad,a+'_'+c)*v for a,v in
        zip(('right','up','front'),(-19.407374,77.879,-42.536600)))
    assert abs(field(rocket[0],'posit_'+c)-expected)<.001,'Rocket must sit on the stock launch deck'
for axis in ('right','up','front'):
    for component in 'xyz':
        field=axis+'_'+component
        r=float(re.search(r'^  '+field+r' \[1\] =\n([^\n]+)',rocket[0],re.M)[1])
        p=float(re.search(r'^  '+field+r' \[1\] =\n([^\n]+)',pad,re.M)[1])
        assert abs(r-p)<.00001,'Rebuilt dorsal housing must face the clear approach corridor'
for field in ('v','omega','Accel'):
    motion = re.search(r' '+field+r' \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)',rocket[0])
    assert tuple(map(float,motion.groups())) == (0,0,0), 'Fixture must have zero copied physics'
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert abs(math.hypot(b[0] - a[0], b[2] - a[2]) - 25) < 0.1, 'Human starts must be 25 m apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn06.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Missions/misn06.vxt').read_text(encoding='utf-8').splitlines() == ['avtank ,', 'avfimp ,', 'avltnk ,']
assert (root / 'Assets/Graphics/misn06.bmp').read_bytes()[:2] == b'BM'
assert len((root / 'misn06.mpdes').read_text().strip()) <= 300

campaign = (root / 'Config/crcampgn.ini').read_text()
assert re.search(r'\[MISSION5\][^\[]*missionBZN = "misn06\.bzn"', campaign), 'Campaign must launch the shared BZN'

raw_lua = (root / 'Scripts/misn06.lua').read_text()
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
assert 'local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'Hostile/support spawns must use team constants'
assert len(re.findall(r'BuildObject\("\w+", ENEMY_TEAM,', lua)) == 37
assert len(re.findall(r'BuildObject\("\w+", SUPPORT_TEAM,', lua)) == 10
assert 'CRCoop.ApplyCoopAlliances(ENEMY_TEAM)' in lua
update = lua.index('function Update(dt)')
assert update < lua.index('if not CRCoop.IsAuthority() then return end', update), 'Authority gate must lead Update'
assert lua.index('if not CRCoop.IsAuthority() then return end', update) < lua.index('M.missionstart == true', update), \
    'Authority gate must precede the mission body'
assert 'AllPlayersWithin(M.dustoffcam, 100.0)' in lua and 'MissionDistance(M.avrec, M.dustoffcam) < 100.0' in lua
assert 'CRCoop.AnyPlayerSatisfies' in lua and 'CRCoop.ForEachPlayerHandle' in lua
assert 'Send(leaderId, "I", prefix)' in lua, 'Guests must relay IsInfo to the leader'

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn06.ini', 'Missions/misn06.vxt', 'Assets/Graphics/misn06.bmp', 'misn06.mpdes',
               'Missions/misn06.bzn', 'Missions/misn06.hg2', 'Missions/misn06.trn', 'Missions/misn06.mat',
               'Missions/misn06.lgt', 'Scripts/misn06.lua']:
    assert members.get(source) == Path(source).name, 'Map/lobby file must be admitted by the shipping manager: ' + source
print('misn06 co-op native map, team isolation, authority and lobby contract passed')
