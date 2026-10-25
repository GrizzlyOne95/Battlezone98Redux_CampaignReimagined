"""Native map, ownership, listing, snapshot-stripping and Lua-authority invariants for shared solo/co-op misn13."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn13.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
assert 'TerrainName = misn13\n' in bzn
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
        # The 1.5 BZN is a mid-play snapshot: no frozen order and no motion may ship.
        assert re.search(r'^what = 00000000$', block, re.M), 'snapshot order left on ' + odf
        assert re.search(r'^who \[1\] =\n0$', block, re.M) and re.search(r'^where = 00000000$', block, re.M), \
            'snapshot target left on ' + odf
        speed = re.search(r'^ v_mag \[1\] =\n(\S+)$', block, re.M)
        assert speed is None or float(speed.group(1)) < 0.5, 'snapshot velocity left on ' + odf
    if team == 5:
        enemies += 1
        assert re.search(r'perceivedTeam \[1\] =\n5\n', block), 'CCA objects must be perceived as team 5'
assert sorted(teams) == [1, 2, 3, 4] and enemies == 48, 'the CCA base, units and geysers-free objects are team 5'
# Authored labels the script resolves: unique, on the right teams.
EXPECTED = {'avrecycle': ('avrecy', 1), 'apcamr20_camerapod': ('apcamr', 1), 'svmuf': ('svmuf13', 5),
            'svguntower1': ('sbhqt1', 5), 'svguntower2': ('sbhang', 5), 'svcom_tower': ('sbcomm', 5),
            'center': ('sbhqt2', 5), 'svslf': ('svslf', 5),
            'svsilo1': ('sbsilo', 5), 'svsilo2': ('sbsilo', 5), 'svsilo3': ('sbsilo', 5), 'svsilo4': ('sbsilo', 5),
            'spawn_geyser1': ('eggeizr1', 0), 'spawn_geyser2': ('eggeizr1', 0), 'key_geyser1': ('eggeizr1', 0),
            'key_geyser2': ('eggeizr1', 0), 'center_geyser': ('eggeizr1', 0), 'split_geyser': ('eggeizr1', 0),
            'artil_escort1': ('svtank', 5), 'artil_escort2': ('svtank', 5), 'artil_escort3': ('svtank', 5),
            'cca_reserve1': ('svtank', 5), 'cca_reserve2': ('svtank', 5)}
for n in range(1, 5):
    EXPECTED[f'artil{n}'] = ('svartl', 5)
    EXPECTED[f'svscav{n}'] = ('svscav', 5)
    EXPECTED[f'tank{n}'] = ('svtank', 5)
for n in range(1, 7):
    EXPECTED[f'turret{n}'] = ('svturr', 5)
    EXPECTED[f'fighter{n}'] = ('svfigh', 5)
for name, (odf, team) in EXPECTED.items():
    assert labels.get(name) == [(odf, team, team)], 'authored label wrong or not unique: ' + name
# The old duplicate wingman labels are gone (GetHandle on a duplicate is ambiguous).
assert not [k for k in labels if k.endswith('_wingman')], 'duplicate-labelled wingmen must be relabelled'
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert 15 < math.hypot(b[0] - a[0], b[2] - a[2]) < 30, 'Human starts must be a short step apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
assert '[AiMission]' in bzn, 'the native AiMission block must stay: the CCA AIP needs it'
# Paths: the named ones survive, the 133 unnamed runtime unit paths are stripped.
path_blocks = bzn.split('[AiPath]\n')[1:]
assert int(re.search(r'\[AiPaths\]\ncount \[1\] =\n(\d+)', bzn)[1]) == len(path_blocks) == 14, 'path count'
names = []
for block in path_blocks:
    label = re.search(r'^label = (\S+)$', block.split('pointCount', 1)[0], re.M)
    assert label, 'an unnamed runtime path survived'
    names.append(label[1])
assert sorted(names) == sorted(['artil_path1', 'choke_point1', 'choke_point2', 'choke_point3', 'artil_point4',
                                'artil_point3', 'artil_point2', 'artil_point1', 'turret_path1', 'turret_path2',
                                'turret_path3', 'slf_path', 'silo_spot', 'edge_path']), 'named paths changed'
# The map builder is the single source of the stripped map.
builder = (root / 'Tools/Build-CoopMap.py').read_text(encoding='utf-8')
assert 'STRIP_UNNAMED_PATHS = {"misn13"}' in builder and 'CLEAR_COMMANDS = {"misn13"}' in builder

# Terrain companions are Redux's own (the Europa terrain has no lightning key to strip).
for suffix in ('hg2', 'lgt', 'trn', 'mat', 'vxt'):
    assert (root / f'Missions/misn13.{suffix}').is_file(), 'missing companion: misn13.' + suffix
trn = (root / 'Missions/misn13.trn').read_text(encoding='latin-1')
assert 'LightningBolt' not in trn and 'eu_detail_atlas' in trn
assert len((root / 'Missions/misn13.mat').read_bytes()) == 131072
assert (root / 'Missions/misn13.vxt').read_text(encoding='utf-8').splitlines() == ['avtank ,', 'avfimp ,', 'avltnk ,', 'avrckt ,', 'avhraz ,', 'avwalk ,']

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn13.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Assets/Graphics/misn13.bmp').read_bytes()[:2] == b'BM'
des = (root / 'misn13.mpdes').read_text()
assert len(des.strip()) <= 300
assert 'Unit Factory' in des and 'hangar' in des and 'silos' in des, 'the briefing must state the real win'
campaign = (root / 'Config/crcampgn.ini').read_text().replace('\r\n', '\n')
assert re.search(r'missionBZN = "misn13\.bzn"', campaign), 'Campaign must launch the shared BZN'
section = re.search(r'\[MISSION12\]\n((?:[^\[\n][^\n]*\n)+)', campaign)[1]
assert 'voice = "misn1305.wav"' in section, 'the campaign retrospective is the previously unused misn1305 line'
assert 'planet = "europa"' in section

raw_lua = (root / 'Scripts/misn13.lua').read_text().replace('\r\n', '\n')
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
lua = re.sub(r'--[^\n]*', '', lua)
assert 'local LEADER_TEAM, ENEMY_TEAM = 1, 5' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'Hostile spawns must use team constants'
assert not re.search(r'\b(SetScrap|SetPilot|AddScrap|GetScrap)\(\s*[234]\s*[,)]', lua), 'scrap/pilots use ENEMY_TEAM'
# The strategic AI: enabled exactly once at chunk load (never inside a function), AIPs set in Update.
assert len(re.findall(r'\bSetAIControl\(', lua)) == 1 and re.search(r'(?m)^SetAIControl\(ENEMY_TEAM, true\)$', lua)
assert lua.index('SetAIControl(ENEMY_TEAM, true)') < lua.index('function Start()')
assert all(re.search(r'SetAIP\("misn13[ac]?\.aip", ENEMY_TEAM\)', call) for call in re.findall(r'SetAIP\([^)]*\)', lua))
assert len(re.findall(r'\bSetAIP\(', lua)) == 3 and 'GetAIP(' not in lua
assert 'CRCoop.ApplyCoopAlliances(ENEMY_TEAM)' in lua
assert 'SetScrap(1, 40)' in lua and 'SetPilot(1, 10)' in lua and 'SetPilot(ENEMY_TEAM, 40)' in lua
# Pilot Mode / aiCore never manage human teams here.
assert 'PlayerPilotMode' not in lua and 'aiCore' not in lua, 'neither Pilot Mode nor aiCore belongs in misn13'
assert not re.search(r'\bFormation\(', lua), 'stock Lua Formation() is broken; use SetCommand FORMATION'
assert 'exu.DisableStartingRecycler()' in lua and 'rallyPoints = { [0] = "avrecycle" }' in lua
assert 'respawn.SetRallyPoints({})' in lua, 'the rally point is dropped when the Recycler dies'
update = lua.index('function Update(dt)')
gate = lua.index('if not CRCoop.IsAuthority() then return end', update)
assert gate < lua.index('M.user = GetPlayerHandle()', update), 'Authority gate must precede the mission body'
body = lua[update:]
assert len(re.findall(r'GetPlayerHandle', body)) == 1 and not re.search(r'M\.user\b[^=]', re.sub(r'M\.user = GetPlayerHandle\(\)', '', body)), \
    'the host handle assignment is the DLL one and nothing reads it'
# Every API that read team 1 / all objects is human-team aware.
assert len(re.findall(r'\bCountUnitsNearObject\(', lua)) == 1 and 'local function HumanUnitsNear' in lua
assert 'M.check = HumanUnitsNear(M.ccamuf, 400.0) - (HumanCount() - 1)' in body, 'count every human team, scale the threshold'
assert 'AddObjectTeamAllowed(h)' in lua and 'ENEMY_TRACKED = { "svapc13", "svhr13", "svtk13" }' in lua
assert 'HUMAN_TRACKED = { "abtowe", "abcomm", "avmuf", "avcnst", "avscav" }' in lua
assert 'CRCoop.ForEachPlayerHandle' in lua and 'ArtilleryShot(h)' in lua, 'misn1302 covers every human craft'
# The win and the objectives.
assert 'CCABaseDestroyed()' in body and 'SILO_COUNT = 4' in lua
assert 'M.hangar = GetHandle("svguntower2")' in lua
for key in ('misn13_recycler', 'misn13_factory', 'misn13_hangar', 'misn13_silos'):
    assert f'"{key}"' in lua, 'objective missing: ' + key
assert 'ClearObjectives()' in lua and 'UpdateObjective(' in lua and 'AddObjective(line[1], line[2], OBJECTIVE_SECONDS, line[3])' in lua
assert 'local function AudioMessage(file) return subtit.Play(file) end' in lua
assert '"misn1301.wav"' in lua and 'COLLINS_DELAY_S = 25.0' in lua
assert 'misn1305' not in raw_lua, 'misn1305 is the campaign retrospective voice, not an in-mission line'
assert 'misn1303.wav' in lua and 'CCABaseDestroyed() then' in lua, 'the victory line fires on the new win'
# Restored waves (cut content), gated and scaled.
assert 'RESTORED_WAVES = true' in lua and 'WAVE_PERIOD_S, WAVE_RETRY_S, WAVE_LIVE_CAP = 300.0, 30.0, 16' in lua
assert 'EXTRA_MAX = 3' in lua and 'ExtraHumans()' in lua
for needle in ('spawn = "spawn_point1"', 'spawn = "spawn_point2"', 'choke = "choke_point3"', 'choke = "choke_point2"',
               'WAVE_ROUTE_PATH = "turret_path3"'):
    assert needle in lua, 'wave routing missing: ' + needle
assert not re.search(r'BuildObject\("avhraz"', lua) and 'M.bomber_reload = true' not in lua, 'bomber reload stays disabled'
# Escort and reserve roles use the relabelled map objects.
for label in ('artil_escort1', 'artil_escort2', 'artil_escort3', 'cca_reserve1', 'cca_reserve2'):
    assert f'GetHandle("{label}")' in lua
# Map-object markers travel by label and the guest wait is bounded on the guest clock (PR #186 pattern).
assert 'HANDLE_OPS' in lua and 'WireHandle' in lua and 'pendingSince' in lua and 'RESOLVE_TIMEOUT' in lua
assert 'EnsureLabel' in lua and 'AnnounceLabel' in lua and 'M.coopUnresolved' in lua and '[coop] unresolved' in lua
assert 'op == "Label"' in lua and 'GONE' in lua
assert 'expires' not in lua, 'Absolute leader-clock expiry must not return'
assert 'CameraPath' not in lua and 'CameraReady' not in lua, 'misn13 has no cinematics'
assert 'edge_path' not in raw_lua, 'edge_path is the play boundary, not a route'
# Weather: the shared Europa director, host-run beats, no stock earthquake calls.
assert 'require("CREuropaSites13")' in lua and 'sites = EuropaSites' in lua
assert 'EUROPA_OPS = { EuropaState = true, EuropaPlume = true, EuropaQuake = true, EuropaSurge = true }' in lua
assert 'CREuropaWeather.ApplyNetEvent(op, ...)' in lua and 'CREuropaWeather.ForceLevel(5, 60.0, 10.0)' in lua
assert not re.search(r'\bStartEarthquake\(|\bStopEarthquake\(', lua), 'the director owns the engine shake'
assert (root / 'Scripts/CREuropaWeather.lua').is_file() and (root / 'Scripts/CREuropaSites13.lua').is_file()
assert 'mission = "misn13"' in (root / 'Scripts/CREuropaSites13.lua').read_text()
assert (root / 'Docs/MISN13_COOP.md').is_file()

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn13.ini', 'Missions/misn13.vxt', 'Assets/Graphics/misn13.bmp', 'misn13.mpdes',
               'Missions/misn13.bzn', 'Missions/misn13.hg2', 'Missions/misn13.trn', 'Missions/misn13.mat',
               'Missions/misn13.lgt', 'Scripts/misn13.lua', 'Scripts/CREuropaSites13.lua', 'ODF/b_misn13.odf']:
    assert members.get(source) == Path(source).name, 'Map/lobby file must be admitted by the shipping manager: ' + source
assert lock['count'] == len(lock['files'])
print('misn13 co-op native map, snapshot stripping, team isolation, authority and lobby contract passed')
