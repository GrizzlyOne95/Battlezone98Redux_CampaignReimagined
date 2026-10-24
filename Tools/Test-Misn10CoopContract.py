"""Native map, ownership, listing and Lua-authority invariants for shared solo/co-op misn10."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn10.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
assert 'TerrainName = misn10\n' in bzn
# The stock [AiMission] block must survive the conversion: LuaMission needs it for the AIPs to load.
assert '[AiMission]' in bzn, 'the AiMission block must stay in the BZN'
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks)
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
assert sorted(teams) == [1, 2, 3, 4] and enemies == 8
# The CCA base is team 5; Utah and the nav beacons belong to the leader (team 1).
assert labels['svrecycler'] == ('svrecy', 5, 5) and labels['svmuf'] == ('svmuf', 5, 5)
assert labels['svartil1'] == ('svartl', 5, 5) and labels['svartil2'] == ('svartl', 5, 5)
for name, odf in [('avrecycler', 'avrecy'), ('cam1', 'apcamr'), ('cam2', 'apcamr'), ('cam3', 'apcamr'),
                  ('player0_hover', 'player')]:
    assert labels[name][1:] == (1, 1), name
# The relic and the geysers the script routes by are neutral map objects (no human team may own the relic).
assert labels['relic'] == ('hvsrb', 0, 0)
for name in ['geyser%d' % i for i in range(1, 8)] + ['post1_geyser', 'post3_geyser']:
    assert labels[name][0] == 'eggeizr1' and labels[name][1:] == (0, 0), name
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert 15 < math.hypot(b[0] - a[0], b[2] - a[2]) < 30, 'Human starts must be a short step apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
# Paths the script drives.
for path in ['relic_path1', 'attack_path_central', 'attack_path_south', 'attack_path_north', 'artil1_path',
             'artil2_path', 'main_return_path', 'lsouth_return_path', 'ssouth_return_path', 'msouth_return_path']:
    assert f'label = {path}\n' in bzn, 'path missing from the converted map: ' + path

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn10.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Assets/Graphics/misn10.bmp').read_bytes()[:2] == b'BM'
assert (root / 'Missions/misn10.vxt').read_text(encoding='utf-8').splitlines() == ['avtank ,', 'avfimp ,', 'avltnk ,', 'avrckt ,', 'avhraz ,', 'avwalk ,']
assert len((root / 'misn10.mpdes').read_text().strip()) <= 300
campaign = (root / 'Config/crcampgn.ini').read_text()
assert re.search(r'missionBZN = "misn10\.bzn"', campaign), 'Campaign must launch the shared BZN'
section = re.search(r'\[MISSION9\]\n((?:[^\[\n][^\n]*\n)+)', campaign.replace('\r\n', '\n'))[1]
assert 'voice = "misn1007.wav"' in section, 'the campaign epilogue is the previously unused misn1007 line'

raw_lua = (root / 'Scripts/misn10.lua').read_text().replace('\r\n', '\n')
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
lua = re.sub(r'--[^\n]*', '', lua)
assert 'local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'Hostile spawns must use team constants'
assert len(re.findall(r'BuildObject\(', lua)) == 2, 'only the replacement tug and the relic-carrier hunters are built'
assert 'BuildObject("svhaul", ENEMY_TEAM, factory)' in lua and 'BuildObject(HUNTER_ODF, ENEMY_TEAM,' in lua
assert not re.search(r'SetAIP\([^)]*SUPPORT_TEAM', lua) and not re.search(r'SetAIControl\(SUPPORT_TEAM', lua)
# Chunk-root only: Start runs after the engine's DR_AI_Init (misn08 live host crash at load).
assert 'SetAIControl(ENEMY_TEAM, true)' in lua
assert len(re.findall(r'SetAIControl\(', lua)) == 1 and re.search(r'^SetAIControl\(ENEMY_TEAM, true\)$', lua, flags=re.M), \
    'SetAIControl must be a single chunk-root call, never inside Start/Update'
assert 'SetAIP("misn10.aip", ENEMY_TEAM)' in lua and 'SetAIP("misn10a.aip", ENEMY_TEAM)' in lua
assert 'SetAIP(PLAN_B_AIP, ENEMY_TEAM)' in lua and 'PLAN_B_AIP = "misn10b.aip"' in lua
assert 'SetScrap(ENEMY_TEAM, 40)' in lua and 'SetPilot(ENEMY_TEAM, 40)' in lua
assert 'CRCoop.ApplyCoopAlliances(ENEMY_TEAM)' in lua
# Only the host manages building: team 1 keeps the DLL resources, nobody gets per-guest scrap.
assert 'SetScrap(1, 30)' in lua and 'SetPilot(1, 10)' in lua
assert 'local function SetScrap' not in lua and 'Present("Resources"' not in lua
assert 'rallyPoints = { [0] = "avrecycler" }' in lua, 'Respawns rally at Utah'
assert 'respawn.SetRallyPoints({})' in lua, 'The rally point is dropped when Utah dies'
update = lua.index('function Update(dt)')
gate = lua.index('if not CRCoop.IsAuthority() then return end', update)
assert gate < lua.index('M.user = GetPlayerHandle()', update), 'Authority gate must precede the mission body'
assert 'CRCoop.AnyPlayerSatisfies' in lua and 'CRCoop.ForEachPlayerHandle' in lua and 'CRCoop.ForEachHumanTeam' in lua
body = lua[update:]
assert not re.search(r'Distance\(M\.user,', body) and 'GetDistance(M.user' not in body
assert 'AnyPlayerWithin(M.sav, 100.0)' in body and 'NearestPlayer(M.geys1)' in body
# Any human team may carry the relic; a CCA tug seizes it.
assert 'GetTeamNum(M.tugger) ~= ENEMY_TEAM' in body and 'CRCoop.IsHumanTeam(GetTeamNum(M.tugger))' in body
assert 'GetTeamNum(M.tugger) == 1' not in lua
# The restored content.
assert 'TUG_REBUILD_DELAY_S, TUG_REBUILD_MAX = 30.0, 2' in lua
assert 'CCA_START_SCRAP, CCA_SCRAP_PER_EXTRA, CCA_EXTRA_MAX = 40, 10, 3' in lua
assert 'CRIoWeather.Quake(PICKUP_QUAKE_STRENGTH, PICKUP_QUAKE_SECONDS)' in lua
assert 'PICKUP_QUAKE_STRENGTH, PICKUP_QUAKE_SECONDS = 0.85, 6.0' in lua
assert not re.search(r'\bStartEarthquake\(|\bStopEarthquake\(', lua), 'the director owns the engine shake'
# Io weather rides the ordered presentation stream to every guest.
assert 'IO_OPS = { IoState = true, IoErupt = true, IoQuake = true }' in lua
assert 'CRIoWeather.ApplyNetEvent(op, ...)' in lua and 'IO_OPS[op]' in lua
assert 'sites = IoSites' in lua and 'require("CRIoSites10")' in lua
assert 'startLevel = 1' in lua and 'targetLevel = 1' in lua, 'calm at the start'
assert 'CRIoWeather.ForceLevel(5, 60.0, 10.0)' in lua and 'CRIoWeather.ReleaseForcedLevel()' in lua
# Map-object markers travel by label and the guest wait is bounded on the guest clock (PR #186 pattern).
assert 'HANDLE_OPS' in lua and 'WireHandle' in lua and 'pendingSince' in lua and 'RESOLVE_TIMEOUT' in lua
assert 'EnsureLabel' in lua and 'AnnounceLabel' in lua and 'M.coopUnresolved' in lua and '[coop] unresolved' in lua
assert 'op == "Label"' in lua and 'GONE' in lua
assert 'expires' not in lua, 'Absolute leader-clock expiry must not return'
# There is no intro cutscene: the adapter carries no camera path.
assert 'CameraPath' not in lua and 'CameraReady' not in lua, 'misn10 has no cinematics'
# Dialogue is the shared presented line; the DLL AudioMessage name is a lexical alias of it.
assert 'local function AudioMessage(file) return subtit.Play(file) end' in lua

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn10.ini', 'Missions/misn10.vxt', 'Assets/Graphics/misn10.bmp', 'misn10.mpdes',
               'Missions/misn10.bzn', 'Missions/misn10.hg2', 'Missions/misn10.trn', 'Missions/misn10.mat',
               'Missions/misn10.lgt', 'Scripts/misn10.lua']:
    assert members.get(source) == Path(source).name, 'Map/lobby file must be admitted by the shipping manager: ' + source
print('misn10 co-op native map, team isolation, authority and lobby contract passed')
