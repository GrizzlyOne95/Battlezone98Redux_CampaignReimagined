"""Native map, ownership, listing, Razor One route and Lua-authority invariants for shared solo/co-op misn12."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn12cr.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
assert 'TerrainName = misn12\n' in bzn
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks)
teams, seqs, enemies, spawns, labels, pods = [], [], 0, {}, {}, 0
for block in blocks:
    odf = re.search(r'PrjID \[1\] =\n([^\n]+)', block)[1]
    team = int(re.search(r'team \[1\] =\n(\d+)', block)[1])
    seqs.append(int(re.search(r'seqno \[1\] =\n(\d+)', block)[1]))
    label = re.search(r'^label = (.*)$', block, re.M)
    perceived = int(re.search(r'perceivedTeam \[1\] =\n(\d+)', block)[1])
    if label:
        labels.setdefault(label[1], []).append((odf, team, perceived))
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
        assert perceived == 5, 'CCA objects must be perceived as team 5'
    if odf == 'apcamr' and team == 7:
        pods += 1
        assert perceived == 7, 'hidden camera pods are perceived as the support team'
assert sorted(teams) == [1, 2, 3, 4] and enemies == 49, 'the whole CCA (49 objects) is team 5'
assert pods == 6, 'the six authored nav pods hide on the support team'
# Authored labels the script resolves: unique, on the right teams.
EXPECTED = {'checktower1': ('sbhqt1', 5), 'center': ('sbhqt2', 5), 'svguntower2': ('sbhang', 5),
            'svmuf': ('svmuf', 5), 'svsilo1': ('sbsilo', 5), 'svcom_tower': ('sbcomm', 5),
            'spawn_geyser': ('eggeizr1', 0), 'spawn_geyser1': ('eggeizr1', 0), 'spawn_geyser2': ('eggeizr1', 0),
            'check2_geyser': ('eggeizr1', 0), 'center_geyser': ('eggeizr1', 0),
            'apcamr20_camerapod': ('apcamr', 1), 'gtank1': ('svtank', 5), 'gtank2': ('svtank', 5),
            'pfighter1': ('svfigh', 5), 'turret1': ('svturr', 5), 'turret6': ('svturr', 5),
            'svfigh1_1': ('svfigh', 5), 'svfigh4_2': ('svfigh', 5),
            'artil1': ('svartl', 5), 'artil2': ('svartl', 5), 'artil3': ('svartl', 5), 'artil4': ('svartl', 5)}
for name, (odf, team) in EXPECTED.items():
    assert labels.get(name) == [(odf, team, team)], 'authored label wrong or not unique: ' + name
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert 15 < math.hypot(b[0] - a[0], b[2] - a[2]) < 30, 'Human starts must be a short step apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
assert '[AiMission]' in bzn
for path in ['first_path', 'path1_to', 'path1_from', 'path2', 'path3', 'path4', 'path5', 'turret1_path', 'turret2_path',
             '3spawn', '4spawn', 'center_cam', 'start_cam', 'check2_cam', 'check3_cam', 'check4_cam', 'goal_cam',
             'start_camera_path']:
    assert f'label = {path}\n' in bzn, 'path missing from the converted map: ' + path
# The Razor One route is authored nowhere: it is data in the script, measured from the heightmap.
hg2 = root / 'Missions/misn12.hg2'
assert hg2.exists()

trn = (root / 'Missions/misn12.trn').read_text(encoding='latin-1')
assert trn.strip(), 'the Redux terrain companion ships with the map'
for ext in ('mat', 'lgt'):
    assert (root / f'Missions/misn12.{ext}').exists()

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn12cr.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Assets/Graphics/misn12cr.bmp').read_bytes()[:2] == b'BM'
des = (root / 'misn12cr.mpdes').read_text()
assert len(des.strip()) <= 300
assert '60 m' in des and '45 s' in des and '50 m' not in des, 'the briefing must state the script\'s tap range and time'
campaign = (root / 'Config/crcampgn.ini').read_text()
assert re.search(r'missionBZN = "misn12cr.bzn"', campaign), 'Campaign must launch the shared BZN'
section = re.search(r'\[MISSION11\]\n((?:[^\[\n][^\n]*\n)+)', campaign.replace('\r\n', '\n'))[1]
assert 'voice = "misn1227.wav"' in section, 'the campaign retrospective is the previously unused misn1227 line'
assert 'planet = "europa"' in section

raw_lua = (root / 'Scripts/misn12cr.lua').read_text().replace('\r\n', '\n')
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
lua = re.sub(r'--[^\n]*', '', lua)
assert 'local LEADER_TEAM, ENEMY_TEAM, HIDDEN_TEAM = 1, 5, 7' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'Hostile spawns must use team constants'
assert not re.search(r'SetAIControl\(|SetAIP\(|GetAIP\(', lua), 'script-only CCA: no strategic AI'
assert 'CRCoop.ApplyCoopAlliances(ENEMY_TEAM)' in lua
assert 'SetScrap' not in lua and 'SetPilot' not in lua, 'the infiltration has no base economy'
assert 'rallyPoints = { [0] = "apcamr20_camerapod" }' in lua
update = lua.index('function Update(dt)')
gate = lua.index('if not CRCoop.IsAuthority() then return end', update)
assert gate < lua.index('UpdateStart()', update), 'Authority gate must precede the mission body'
body = lua[update:]
assert body.count('GetPlayerHandle') == 1 and 'M.user = GetPlayerHandle()' in body, 'only the leader anchors M.user'
assert 'ForEachHuman(UpdateProgress)' in body and 'ForEachHuman(UpdateCapture)' in body
assert 'ForEachSlot(UpdateKeyCycle)' in body and 'AllHumansArrived(M.nav1, 75.0)' in lua
assert 'KEY_STAGGER_S = 25.0' in lua and 'MAX_PLAYERS = 4' in lua
assert 'CRCoop.ForEachPlayerHandle' in lua and 'CRCoop.ForEachHumanTeam' in lua
assert 'IsInfo' in lua and '"sbhqt1", "sbhqt2"' in lua and 'remoteInfo[from][prefix]' in lua
assert 'EUROPA_OPS = { EuropaState = true, EuropaPlume = true, EuropaQuake = true, EuropaSurge = true }' in lua
assert 'CREuropaWeather.ApplyNetEvent(op, ...)' in lua and 'sites = EuropaSites' in lua and 'require("CREuropaSites12")' in lua
assert 'startLevel = 1' in lua and 'targetLevel = 1' in lua and 'CREuropaWeather.ReleaseForcedLevel()' in lua
assert not re.search(r'\bStartEarthquake\(|\bStopEarthquake\(', lua), 'the director owns the engine shake'
# The weather is cosmetic: the mission calls only the director's presentation API.
weather_calls = set(re.findall(r'CREuropaWeather\.(\w+)', lua))
assert weather_calls <= {'ApplyNetEvent', 'Init', 'Update', 'Shutdown', 'OnObjectCreated', 'Save', 'Load', 'AnnounceState',
                         'SetTargetLevel', 'ReleaseForcedLevel', 'TriggerPlume', 'Quake', 'Surge', 'GetVentSites', 'Seed'}, weather_calls
# Map-object markers travel by label and the guest wait is bounded on the guest clock (PR #186 pattern).
assert 'HANDLE_OPS' in lua and 'WireHandle' in lua and 'pendingSince' in lua and 'RESOLVE_TIMEOUT' in lua
assert 'EnsureLabel' in lua and 'AnnounceLabel' in lua and 'M.coopUnresolved' in lua and '[coop] unresolved' in lua
assert 'op == "Label"' in lua and 'GONE' in lua
assert 'expires' not in lua, 'Absolute leader-clock expiry must not return'
assert 'local function AudioMessage(file) return subtit.Play(file) end' in lua
assert 'edge_path' not in raw_lua, 'edge_path is the play boundary, not a route'
# Stealth: shared cover (several humans), per-human capture, perceived-team disguise.
assert 'SetPerceivedTeam(entry.handle, ENEMY_TEAM)' in lua and 'SetPerceivedTeam(h, 1)' in lua
assert 'M.strict = M.multi' in lua and 'CoverBlown(' in lua
# Razor One: the unused east-side route, driven by script; the cut line is wired; Formation is never called.
assert '"misn1224.wav"' in lua and 'RAZOR_ROUTE' in lua
assert re.search(r'\bFormation\s*\(', lua) is None, 'stock Lua Formation() is broken: use SetCommand(.., AiCommand.FORMATION, ..)'
route = re.search(r'RAZOR_ROUTE = \{(.*?)\n\}', lua, re.S)[1]
points = [(int(x), int(z)) for x, z in re.findall(r'\{\s*(\d+),\s*(\d+)\s*\}', route)]
assert len(points) == 27 and points[0] == (2942, 100812) and points[-1] == (3562, 97862), 'route runs compound -> Drop Zone'
assert points[14] == (3343, 99632) and points[15] == (3347, 99518), 'the lip crest and the landing'
jump = math.hypot(points[15][0] - points[14][0], points[15][1] - points[14][1])
assert 100 <= jump <= 125, 'the jump is the measured 100+ m gap'
for a, b in zip(points, points[1:]):
    assert math.hypot(b[0] - a[0], b[1] - a[1]) < 420, 'consecutive route points stay within AI order range'
assert 'RAZOR_WAIT_LEG, RAZOR_LIP_LEG, RAZOR_LAND_LEG = 14, 15, 16' in lua
# The preview tool exists and is deterministic input for the evidence image.
assert (root / 'Tools/Preview-Misn12Map.py').exists() and (root / 'Docs/MISN12_ROUTE_PREVIEW.png').read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn12cr.ini', 'Missions/misn12cr.vxt', 'Assets/Graphics/misn12cr.bmp', 'misn12cr.mpdes',
               'Missions/misn12cr.bzn', 'Missions/misn12.hg2', 'Missions/misn12.trn', 'Missions/misn12.mat',
               'Missions/misn12.lgt', 'Scripts/misn12cr.lua', 'Scripts/CREuropaWeather.lua', 'Scripts/CREuropaSites12.lua',
               'Materials/cr_europa.particle.payload', 'Assets/Audio/misn1224.wav']:
    assert members.get(source) == Path(source).name, 'Map/lobby file must be admitted by the shipping manager: ' + source
assert (root / 'Text/misn1224.txt').is_file(), 'the restored Razor One line needs its subtitle'
assert lock['count'] == len(lock['files'])
print('misn12 co-op native map, team isolation, Razor One route, authority and lobby contract passed')
