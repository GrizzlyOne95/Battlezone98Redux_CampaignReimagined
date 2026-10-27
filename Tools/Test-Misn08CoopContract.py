"""Native map, ownership, listing and Lua-authority invariants for shared solo/co-op misn08."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn08.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
assert 'TerrainName = misn08\n' in bzn
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks) == 244
teams, seqs, enemies, spawns, labels = [], [], 0, {}, {}
for block in blocks:
    odf = re.search(r'PrjID \[1\] =\n([^\n]+)', block)[1]
    team = int(re.search(r'team \[1\] =\n(\d+)', block)[1])
    seqs.append(int(re.search(r'seqno \[1\] =\n(\d+)', block)[1]))
    label = re.search(r'^label = (.*)$', block, re.M)
    if label:
        labels[label[1]] = (odf, team, int(re.search(r'perceivedTeam \[1\] =\n(\d+)', block)[1]))
    if odf == 'pspwn_1':
        teams.append(team)
        assert f'label = coop_spawn{team}\n' in block, 'Spawn buoy label must match its team'
        positions = re.findall(r'pos \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', block)
        assert len(positions) == 2 and positions[0] == positions[1], 'Spawn position must be consistent'
        spawns[team] = tuple(map(float, positions[0]))
        for field in ('v', 'omega', 'Accel'):
            motion = re.search(r' ' + field + r' \[1\] =\n  x \[1\] =\n([^\n]+)\n  y \[1\] =\n([^\n]+)\n  z \[1\] =\n([^\n]+)', block)
            assert tuple(map(float, motion.groups())) == (0, 0, 0), 'Spawn buoys must not carry copied motion'
    else:
        assert team not in (2, 3, 4), 'Authored object occupies a guest team'
    if team == 5:
        enemies += 1
        assert re.search(r'perceivedTeam \[1\] =\n5\n', block), 'CCA objects must be perceived as team 5'
assert sorted(teams) == [1, 2, 3, 4] and enemies == 16
# The Colorado is the support team (allied with every human), perceived as NSDF; the Utah is the leader's.
assert labels['colorado'] == ('avrecy', 7, 1), labels['colorado']
assert labels['avrecycle'] == ('avrec8', 1, 1)
assert labels['sovgech1'][1:] == (5, 5) and labels['sovgech2'][1:] == (5, 5) and labels['svrecycle'][1:] == (5, 5)
assert {'cam1', 'cam2', 'cam5', 'svmuf', 'hbblde1_i76building', 'hbbldf1_i76building', 'hbcerb1_i76building',
        'giez_spawn2', 'giez_spawn3', 'stop_geyser2', 'stop_geyser3', 'attack_geyser', 'player0_hover'} <= set(labels)
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert abs(math.hypot(b[0] - a[0], b[2] - a[2]) - 25) < 0.1, 'Human starts must be 25 m apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
for path in ['gech_path1', 'gech_path2', 'gech_spawn', 'cam2_spawn', 'cam3_spawn']:
    assert f'label = {path}\n' in bzn, 'path missing from the converted map: ' + path

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn08.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Assets/Graphics/misn08.bmp').read_bytes()[:2] == b'BM'
assert (root / 'Missions/misn08.vxt').read_text(encoding='utf-8').splitlines() == ['avtank ,', 'avfimp ,', 'avltnk ,', 'avrckt ,', 'avhraz ,']
assert len((root / 'misn08.mpdes').read_text().strip()) <= 300
campaign = (root / 'Config/crcampgn.ini').read_text()
assert re.search(r'missionBZN = "misn08\.bzn"', campaign), 'Campaign must launch the shared BZN'

raw_lua = (root / 'Scripts/misn08.lua').read_text()
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
lua = re.sub(r'--[^\n]*', '', lua)
assert 'local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'Hostile spawns must use team constants'
assert len(re.findall(r'BuildObject\("\w+",\s*ENEMY_TEAM,', lua)) == 7
# The Colorado's base is Lua-built on the support team (no AIP/AI control for team 7), charged to team-7 scrap.
assert 'BuildObject(odf, SUPPORT_TEAM, where)' in lua and 'AddScrap(SUPPORT_TEAM, -cost)' in lua
assert not re.search(r'SetAIP\([^)]*SUPPORT_TEAM', lua) and not re.search(r'SetAIControl\(SUPPORT_TEAM', lua)
assert 'BuildObject("svwalk", ENEMY_TEAM, M.ccamuf)' in lua and 'AddScrap(ENEMY_TEAM, -WALKER_SCRAP_COST)' in lua
assert 'SetAIControl(ENEMY_TEAM, true)' in lua
# Chunk-root only: Start runs after the engine's DR_AI_Init, and a late SetAIControl flags team 5 without an
# AI team record, so the first team-5 AI_UnitRemove dereferences null (host crash at load, live 4-client run).
assert len(re.findall(r'SetAIControl\(', lua)) == 1 and re.search(r'^SetAIControl\(ENEMY_TEAM, true\)$', raw_lua, flags=re.M), \
    'SetAIControl must be a single chunk-root call, never inside Start/Update'
assert len(re.findall(r'SetAIP\("misn08\w?\.aip",\s*ENEMY_TEAM\)', lua)) == 3
assert 'SetScrap(ENEMY_TEAM, 40)' in lua and 'SetPilot(ENEMY_TEAM, 40)' in lua
assert 'CRCoop.ApplyCoopAlliances(ENEMY_TEAM)' in lua
assert 'rallyPoints = { [0] = "avrecycle" }' in lua, 'Respawns rally at the Utah'
update = lua.index('function Update(dt)')
gate = lua.index('if not CRCoop.IsAuthority() then return end', update)
assert gate < lua.index('M.user = GetPlayerHandle()', update), 'Authority gate must precede the mission body'
assert 'CRCoop.AnyPlayerSatisfies' in lua and 'CRCoop.ForEachPlayerHandle' in lua and 'CRCoop.ForEachHumanTeam' in lua
# IsInfo is local UI state: guests relay it to the leader, who honours it for one second.
assert 'Send(leaderId, "I", prefix)' in lua and 'INFO_PREFIXES = { "hbblde", "hbbldf" }' in lua
assert re.search(r'GetTime\(\) - reported <= 1\.0', lua)
body = lua[update:]
assert not re.search(r'Distance\(M\.user,', body), 'player-handle distance tests must use the any-player helpers'
assert not re.search(r'Attack\(M\.\w+,\s*M\.user\)', body), 'Attack targets must be the nearest player'
assert 'GetDistance(M.user' not in body
# Map-object markers travel by label and the guest wait is bounded on the guest clock (PR #186 pattern).
assert 'HANDLE_OPS' in lua and 'WireHandle' in lua and 'pendingSince' in lua and 'RESOLVE_TIMEOUT' in lua
assert 'EnsureLabel' in lua and 'AnnounceLabel' in lua and 'M.coopUnresolved' in lua and '[coop] unresolved' in lua
assert 'op == "Label"' in lua and 'GONE' in lua
assert 'expires' not in lua, 'Absolute leader-clock expiry must not return'
# Back-to-back dialogue plays then queues.
assert 'subtit.Queue("misn0804.wav")' in lua and 'subtit.Queue("misn0826.wav")' in lua
assert 'AudioMessage(' not in lua
# The failure line is substituted in a marked region, the DLL body keeps misn0421.
assert 'subtit.Play("misn0421.wav")' in lua and '["misn0421.wav"] = "misn0823.wav"' in raw_lua and 'misn0825' not in raw_lua

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn08.ini', 'Missions/misn08.vxt', 'Assets/Graphics/misn08.bmp', 'misn08.mpdes',
               'Missions/misn08.bzn', 'Missions/misn08.hg2', 'Missions/misn08.trn', 'Missions/misn08.mat',
               'Missions/misn08.lgt', 'Scripts/misn08.lua', 'Text/misn0823.txt', 'Text/misn0824.txt']:
    assert members.get(source) == Path(source).name, 'Map/lobby file must be admitted by the shipping manager: ' + source
print('misn08 co-op native map, team isolation, authority and lobby contract passed')
