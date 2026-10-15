"""Native map, ownership, listing and Lua-authority invariants for shared solo/co-op misn09."""
from pathlib import Path
import configparser
import json
import math
import re

root = Path(__file__).resolve().parents[1]
raw = (root / 'Missions/misn09.bzn').read_bytes()
assert b'\n' not in raw.replace(b'\r\n', b''), 'BZN must retain native CRLF'
bzn = raw.decode('utf-8').replace('\r\n', '\n')
assert 'name = MultSTMission\n' in bzn
assert 'TerrainName = misn09\n' in bzn
blocks = bzn.split('[GameObject]')[1:]
assert int(re.search(r'size \[1\] =\n(\d+)\n', bzn)[1]) == len(blocks) == 215
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
assert sorted(teams) == [1, 2, 3, 4] and enemies == 13
# The CCA base, artillery and launch pad are team 5; the player's factory and its convoy are the leader's team 1.
for name in ['launchpad', 'svmuf', 'svrecycle'] + [f'artil{i}' for i in range(1, 7)]:
    assert labels[name][1:] == (5, 5), name
assert labels['launchpad'][0] == 'sblpad' and labels['svmuf'][0] == 'svmuf' and labels['svrecycle'][0] == 'svrecy'
assert all(labels[f'artil{i}'][0] == 'svartl' for i in range(1, 7))
for name in ['avmuf', 'rig', 'avslf', 'scav1', 'scav2', 'scav3', 'cam1', 'player0_hover']:
    assert labels[name][1:] == (1, 1), name
assert labels['avmuf'][0] == 'avmuf'
# The relic and the geysers the script reads are neutral map objects (the relic itself is built at runtime).
assert {'cut_off_geyser', 'convoy_geyser', 'hbchar0_i76building', 'key_scrap'} <= set(labels)
assert labels['cut_off_geyser'][1:] == (0, 0) and labels['convoy_geyser'][1:] == (0, 0)
for team in (1, 2, 3):
    a, b = spawns[team], spawns[team + 1]
    assert 15 < math.hypot(b[0] - a[0], b[2] - a[2]) < 30, 'Human starts must be a short step apart'
assert len(seqs) == len(set(seqs)) and int(re.search(r'seq_count \[1\] =\n(\d+)', bzn)[1]) > max(seqs)
# Paths the script drives: the convoy's spawn points and route, the factory's return path, the posts and cameras.
for path in ['spawn1', 'spawn2', 'spawn3', 'spawn4', 'soviet_path', 'return_path', 'post1', 'post2', 'post3', 'post4',
             'charon_spawn', 'camera_circle', 'camera_path', 'convoy_cam_path', 'edge_path']:
    assert f'label = {path}\n' in bzn, 'path missing from the converted map: ' + path

ini = configparser.ConfigParser()
ini.read(root / 'Config/misn09.ini')
assert ini['WORKSHOP']['mapType'] == '"multiplayer"'
assert dict(ini['MULTIPLAYER']) == {'minplayers': '"2"', 'maxplayers': '"4"', 'gametype': '"S"'}
assert (root / 'Assets/Graphics/misn09.bmp').read_bytes()[:2] == b'BM'
assert (root / 'Missions/misn09.vxt').read_text(encoding='utf-8').splitlines() == ['avtank ,', 'avfimp ,', 'avltnk ,', 'avrckt ,', 'avhraz ,', 'avwalk ,']
assert len((root / 'misn09.des').read_text().strip()) <= 300
campaign = (root / 'Config/crcampgn.ini').read_text()
assert re.search(r'missionBZN = "misn09\.bzn"', campaign), 'Campaign must launch the shared BZN'

raw_lua = (root / 'Scripts/misn09.lua').read_text().replace('\r\n', '\n')
lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', raw_lua, flags=re.S)
lua = re.sub(r'--[^\n]*', '', lua)
assert 'local LEADER_TEAM, ENEMY_TEAM, SUPPORT_TEAM = 1, 5, 7' in lua
assert not re.search(r'BuildObject\([^\n]*,\s*[234]\s*,', lua), 'Hostile spawns must use team constants'
# Tug, ten escorts, two extras per scaling step in the loop, and the replacement tug.
assert len(re.findall(r'BuildObject\("\w+",\s*ENEMY_TEAM,', lua)) == 11 + 2 + 1
assert 'BuildObject("svhaul", ENEMY_TEAM, M.ccamuf)' in lua
# Prescott's platoon is the support team (allied with every human, hostile to the CCA), perceived as NSDF.
assert 'BuildObject("avtank", SUPPORT_TEAM, SetVector(px, py, pz))' in lua and 'SetPerceivedTeam(unit, LEADER_TEAM)' in lua
assert not re.search(r'SetAIP\([^)]*SUPPORT_TEAM', lua) and not re.search(r'SetAIControl\(SUPPORT_TEAM', lua)
# The relic is neutral: team 3 is a guest slot.
assert 'local RELIC_TEAM = 0' in lua and 'BuildObject("obdata", RELIC_TEAM, M.convoy_geyser)' in lua
assert 'SetAIControl(ENEMY_TEAM, true)' in lua
# Chunk-root only: Start runs after the engine's DR_AI_Init (misn08 live host crash at load).
assert len(re.findall(r'SetAIControl\(', lua)) == 1 and re.search(r'^SetAIControl\(ENEMY_TEAM, true\)$', lua, flags=re.M), \
    'SetAIControl must be a single chunk-root call, never inside Start/Update'
assert len(re.findall(r'SetAIP\("misn09\w?\.aip",\s*ENEMY_TEAM\)', lua)) == 3
assert 'SetScrap(ENEMY_TEAM, 40)' in lua and 'SetPilot(ENEMY_TEAM, 40)' in lua
assert 'CRCoop.ApplyCoopAlliances(ENEMY_TEAM)' in lua
# Only the host manages building: team 1 keeps the DLL's resources, nobody gets per-guest scrap.
assert 'SetScrap(1, 20)' in lua and 'SetPilot(1, 7)' in lua
assert 'local function SetScrap' not in lua and 'Present("Resources"' not in lua
assert 'rallyPoints = { [0] = "avmuf" }' in lua, 'Respawns rally at the Unit Factory'
assert 'respawn.SetRallyPoints({})' in lua, 'The rally point is dropped when the factory dies'
update = lua.index('function Update(dt)')
gate = lua.index('if not CRCoop.IsAuthority() then return end', update)
assert gate < lua.index('M.user = GetPlayerHandle()', update), 'Authority gate must precede the mission body'
assert 'CRCoop.AnyPlayerSatisfies' in lua and 'CRCoop.ForEachPlayerHandle' in lua and 'CRCoop.ForEachHumanTeam' in lua
# IsInfo is local UI state: guests relay it to the leader, who honours it for one second.
assert 'Send(leaderId, "I", prefix)' in lua and 'INFO_PREFIXES = { "hbchar" }' in lua
assert re.search(r'GetTime\(\) - reported <= 1\.0', lua)
body = lua[update:]
assert not re.search(r'Distance\(M\.user,', body), 'player-handle distance tests must use the any-player helpers'
assert 'GetDistance(M.user' not in body
assert body.count('AnyPlayerWithin(') >= 5 and body.count('NoPlayerWithin(') >= 1
# Map-object markers travel by label and the guest wait is bounded on the guest clock (PR #186 pattern).
assert 'HANDLE_OPS' in lua and 'WireHandle' in lua and 'pendingSince' in lua and 'RESOLVE_TIMEOUT' in lua
assert 'EnsureLabel' in lua and 'AnnounceLabel' in lua and 'M.coopUnresolved' in lua and '[coop] unresolved' in lua
assert 'op == "Label"' in lua and 'GONE' in lua
assert 'expires' not in lua, 'Absolute leader-clock expiry must not return'
# Cinematics go through the presentation adapter (label-aware camera snapshots), never raw to one peer.
assert 'WireCameraFrame' in lua and 'cameraFrame = { "P", path, height, speed, target }' in lua
assert 'CameraObject(' in lua  # the adapter supports the object kind even though misn09 uses path shots
# Dialogue is the shared presented line; the DLL's AudioMessage name is a lexical alias of it.
assert 'local function AudioMessage(file) return subtit.Play(file) end' in lua
# Restored radio lines are in marked regions with their text and wavs; 0912 stays cut.
assert 'misn0917.wav' in lua and 'misn0910.wav' in lua
assert 'misn0912' not in lua and 'misn0912' in raw_lua
assert 'FACTORY_COMBAT_ODFS' in lua and 'WALKER_FAR_M' in lua and 'TUG_REBUILD_DELAY_S' in lua
assert 'PRESCOTT_TRIGGER_M, PRESCOTT_DELAY_S, PRESCOTT_RETARGET_S = 350.0, 45.0, 4.0' in lua
assert 'CONVOY_EXTRA_MAX = 3' in lua and 'local PRESCOTT_COUNT = 5' in lua and 'PRESCOTT_BASE' not in lua and 'PRESCOTT_MAX' not in lua

lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8-sig'))
members = {entry['source'].replace('\\', '/'): entry['runtime'] for entry in lock['files']}
for source in ['Config/misn09.ini', 'Missions/misn09.vxt', 'Assets/Graphics/misn09.bmp', 'misn09.des',
               'Missions/misn09.bzn', 'Missions/misn09.hg2', 'Missions/misn09.trn', 'Missions/misn09.mat',
               'Missions/misn09.lgt', 'Scripts/misn09.lua', 'Text/misn0910.txt', 'Text/misn0917.txt']:
    assert members.get(source) == Path(source).name, 'Map/lobby file must be admitted by the shipping manager: ' + source
# Files this mission adds that still need a shipping-lock bless (empty now: the lock admits all of them). A file listed
# here that the lock already admits must be removed, so the list cannot go stale.
# The two restored lines are stock-format PCM like Test-ShippedCutVo.py demands of every shipped cut line (that
# test's WAVS list gains misn0910 and misn0917 when the lock admits them).
for name in ('misn0910', 'misn0917'):
    data = (root / 'Assets/Audio' / (name + '.wav')).read_bytes()
    assert data[:4] == b'RIFF' and data[8:16] == b'WAVEfmt ', name + ' is not a RIFF/WAVE file'
    assert int.from_bytes(data[20:22], 'little') == 1 and int.from_bytes(data[22:24], 'little') == 1
    assert int.from_bytes(data[24:28], 'little') == 11025 and int.from_bytes(data[34:36], 'little') == 8
    assert (root / 'Text' / (name + '.txt')).is_file()
PENDING_LOCK = []
for source in PENDING_LOCK:
    assert (root / source).is_file(), 'pending file missing: ' + source
    assert source not in members, 'already blessed; drop it from PENDING_LOCK: ' + source
if PENDING_LOCK:
    print('NOTE: awaiting a shipping-lock bless for: ' + ', '.join(PENDING_LOCK))
print('misn09 co-op native map, team isolation, authority and lobby contract passed')
