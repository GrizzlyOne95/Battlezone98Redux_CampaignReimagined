"""Native map, ownership, listing, lava and Lua-authority invariants for shared solo/co-op misn11."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn11.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
assert 'TerrainName = misn11\n' in bzn
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks)
teams, seqs, enemies, spawns, labels = [], [], 0, {}, {}
for block in blocks:
    odf = re.search(r'PrjID \[1\] =\n([^\n]+)', block)[1]
    team = int(re.search(r'team \[1\] =\n(\d+)', block)[1])
    seqs.append(int(re.search(r'seqno \[1\] =\n(\d+)', block)[1]))
    label = re.search(r'^label = (.*)$', block, re.M)
    if label:
        labels.setdefault(label[1], []).append((odf, team, int(re.search(r'perceivedTeam \[1\] =\n(\d+)', block)[1])))
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
assert sorted(teams) == [1, 2, 3, 4] and enemies == 8, 'five svturr, two svartl, one svwalk are the CCA'
# Authored labels the script resolves: unique, on the right teams.
EXPECTED = {'avhaul0_tug': ('avhaul', 1), 'avhaul1_tug': ('avhaul', 1), 'avhaul2_tug': ('avhaul', 1),
            'apcamr3_camerapod': ('apcamr', 1), 'apcamr4_camerapod': ('apcamr', 1),
            'apcamr5_camerapod': ('apcamr', 1), 'launch_pad': ('ablpad', 1),
            'launch_pad2': ('ablpad', 1), 'svturr0_turrettank': ('svturr', 5),
            'svturr1_turrettank': ('svturr', 5), 'svturr2_turrettank': ('svturr', 5),
            'svturr3_turrettank': ('svturr', 5), 'second_blockade': ('svturr', 5),
            'svwalk0_walker': ('svwalk', 5), 'svartl0_howitzer': ('svartl', 5),
            'svartl0(1)_howitzer': ('svartl', 5)}
for name, (odf, team) in EXPECTED.items():
    assert labels.get(name) == [(odf, team, team)], 'authored label wrong or not unique: ' + name
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert 15 < math.hypot(b[0] - a[0], b[2] - a[2]) < 30, 'Human starts must be a short step apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
assert '[AiMission]' in bzn
for path in ['base1', 'base2', 'escape', 'openheimer', 'strike1', 'strike2', 'strike_path1', 'strike_path2',
             'check2', 'launch_attack', 'last_camera', 'edge_path']:
    assert f'label = {path}\n' in bzn, 'path missing from the converted map: ' + path

# Terrain: lava is painted and the engine is told which TextureType is lava.
trn = (root / 'Missions/misn11.trn').read_text(encoding='latin-1').replace('\r\n', '\n')
assert re.search(r'(?m)^Lava=1$', trn), 'Lava=1 missing: lava would be inert'
assert re.search(r'(?m)^\[TextureType1\] Lava Pool', trn)
mat = (root / 'Missions/misn11.mat').read_bytes()
assert len(mat) == 131072
cells = [int.from_bytes(mat[i:i + 2], 'little') for i in range(0, len(mat), 2)]
pool = sum(1 for v in cells if (v >> 12) == 1 and ((v >> 8) & 15) == 1)
assert pool > 20000, 'the map must be painted with lava pool tiles'
assert all(((v >> 12) & 15) in (0, 1, 3) for v in cells), 'only crust, lava pool and sulphur tiles'
assert (root / 'Tools/Build-Misn11Lava.py').exists()

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn11.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Assets/Graphics/misn11.bmp').read_bytes()[:2] == b'BM'
assert len((root / 'misn11.des').read_text().strip()) <= 300
campaign = (root / 'Config/crcampgn.ini').read_text()
assert re.search(r'missionBZN = "misn11\.bzn"', campaign), 'Campaign must launch the shared BZN'
section = re.search(r'\[MISSION10\]\n((?:[^\[\n][^\n]*\n)+)', campaign.replace('\r\n', '\n'))[1]
assert 'voice = "misn1100.wav"' in section, 'the campaign retrospective is the previously unused misn1100 line'
assert 'planet = "io"' in section

raw_lua = (root / 'Scripts/misn11.lua').read_text().replace('\r\n', '\n')
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
lua = re.sub(r'--[^\n]*', '', lua)
assert 'local LEADER_TEAM, ENEMY_TEAM = 1, 5' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'Hostile spawns must use team constants'
assert not re.search(r'SetAIControl\(|SetAIP\(|GetAIP\(', lua), 'script-only CCA: no strategic AI'
assert 'CRCoop.ApplyCoopAlliances(ENEMY_TEAM)' in lua
assert 'SetScrap(1, 50)' in lua and 'SetPilot' not in lua, 'Only the host manages the base'
assert 'rallyPoints = { [0] = "base1", [1] = "avhaul0_tug" }' in lua and 'CRCoop.SetMissionPhase(1)' in lua
assert 'respawn.SetRallyPoints({})' in lua, 'The rally point is dropped when the lead tug dies'
update = lua.index('function Update(timestep)')
gate = lua.index('if not CRCoop.IsAuthority() then return end', update)
assert gate < lua.index('if not M.start_done then', update), 'Authority gate must precede the mission body'
body = lua[update:]
assert 'GetPlayerHandle' not in body and not re.search(r'M\.player\b', body)
assert 'AnyPlayerWithin(M.cam1, 50.0)' in body and 'AnyPlayerWithin(M.launch, 450.0)' in body
assert 'AllPlayersArrived(M.launch2, 200.0)' in body, 'the win needs every human at launch2'
assert 'CRCoop.AnyPlayerSatisfies' in lua and 'CRCoop.ForEachPlayerHandle' in lua and 'CRCoop.ForEachHumanTeam' in lua
assert len(re.findall(r'IsBackupUnit\(h\)', body)) == 3, 'the strike scans must skip the backup squad'
assert 'EXTRA_MAX = 3' in lua and 'function BuildExtras' in lua
assert '"misn1114.wav"' in lua and '"misn1115.wav"' in lua
assert not re.search(r'\bStartEarthquake\(|\bStopEarthquake\(', lua), 'the director owns the engine shake'
assert 'IO_OPS = { IoState = true, IoErupt = true, IoQuake = true }' in lua
assert 'CRIoWeather.ApplyNetEvent(op, ...)' in lua and 'sites = IoSites' in lua and 'require("CRIoSites11")' in lua
assert 'startLevel = 1' in lua and 'targetLevel = 1' in lua
assert 'CRIoWeather.ForceLevel(5, 60.0, 10.0)' in lua and 'CRIoWeather.ReleaseForcedLevel()' in lua
# Map-object markers travel by label and the guest wait is bounded on the guest clock (PR #186 pattern).
assert 'HANDLE_OPS' in lua and 'WireHandle' in lua and 'pendingSince' in lua and 'RESOLVE_TIMEOUT' in lua
assert 'EnsureLabel' in lua and 'AnnounceLabel' in lua and 'M.coopUnresolved' in lua and '[coop] unresolved' in lua
assert 'op == "Label"' in lua and 'GONE' in lua
assert 'expires' not in lua, 'Absolute leader-clock expiry must not return'
assert 'CameraPath' not in lua and 'CameraReady' not in lua, 'misn11 has no cinematics'
assert 'local function AudioMessage(file) return subtit.Play(file) end' in lua
assert 'edge_path' not in raw_lua, 'edge_path is the play boundary, not a route'

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn11.ini', 'Missions/misn11.vxt', 'Assets/Graphics/misn11.bmp', 'misn11.des',
               'Missions/misn11.bzn', 'Missions/misn11.hg2', 'Missions/misn11.trn', 'Missions/misn11.mat',
               'Missions/misn11.lgt', 'Scripts/misn11.lua', 'Scripts/CRIoSites11.lua']:
    assert members.get(source) == Path(source).name, 'Map/lobby file must be admitted by the shipping manager: ' + source
assert lock['count'] == len(lock['files'])
print('misn11 co-op native map, team isolation, lava, authority and lobby contract passed')
