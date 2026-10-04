"""Chinese02 regressions: python Tools/test_ch02.py (requires lupa.lua51).

Mocked BZR calls test sequencing; movement, assets and camera require the game.
"""
from pathlib import Path
import hashlib
import re
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / 'Scripts/ch02.lua').read_text()
HARNESS = r'''
now = 0
calls = {}
health = { player = 1 }
valid = { player = true }
distances = {}
audioDone = {}
nextHandle = 0
cancelled = false
cameraArrived = false
pathCount = 4
AiCommand = { RECYCLE = 18 }
function record(name, ...) calls[#calls + 1] = {name, ...} end
function count(name, arg)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end
    end
    return n
end
function lastCall(name)
    for i = #calls, 1, -1 do
        if calls[i][1] == name then return calls[i] end
    end
end
function spawnCount(path)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == 'BuildObject' and c[4] == path then n = n + 1 end
    end
    return n
end
function GetTime() return now end
function GetPlayerHandle() return 'player' end
function GetHandle(label) valid[label] = true; health[label] = 1; return label end
function IsValid(h) return valid[h] == true end
function IsAlive(h) assert(h ~= nil); return valid[h] == true and health[h] > 0 end
function GetHealth(h) assert(h ~= nil and valid[h]); return health[h] end
function GetDistance(h, target, point)
    assert(valid[h] and target ~= nil)
    record('GetDistance', h, target, point)
    return distances[h .. ':' .. tostring(target) .. ':' .. tostring(point)] or 10000
end
function near(h, target, distance, point)
    distances[h .. ':' .. tostring(target) .. ':' .. tostring(point)] = distance
end
function GetPathPointCount(path) assert(path == 'walker_path'); return pathCount end
function BuildObject(odf, team, path)
    record('BuildObject', odf, team, path)
    nextHandle = nextHandle + 1
    local h = 'spawn' .. nextHandle
    valid[h] = true; health[h] = 1
    return h
end
function CameraReady() record('CameraReady'); return true end
function CameraFinish() record('CameraFinish'); return true end
function CameraCancelled() return cancelled end
function CameraPath(path, height, speed, target)
    assert(path == 'camera_start' and height == 800 and speed == 2000 and target == 'hanger')
    return cameraArrived
end
function AudioMessage(file) record('AudioMessage', file); return file end
function IsAudioMessageDone(msg) assert(msg ~= nil); return audioDone[msg] == true end
function StopAudioMessage(msg) assert(msg ~= nil); record('StopAudioMessage', msg) end
function Goto(h, target, priority)
    assert(valid[h] and target ~= nil)
    record('Goto', h, target, priority)
end
for _, name in ipairs({'SetScrap', 'SetPilot', 'EnableAllCloaking', 'ClearObjectives',
    'AddObjective', 'Hunt', 'Attack', 'Defend2', 'SetObjectiveOn', 'SetPerceivedTeam',
    'Retreat', 'SetTeamNum', 'SetCommand', 'SetName', 'StartCockpitTimer',
    'FailMission', 'SucceedMission'}) do
    local key = name
    _G[key] = function(...) record(key, ...) end
end
function tick(t) now = t; Update(0.1) end
function clone(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = clone(v) end
    return r
end
function reload()
    local snapshot = clone(Save())
    assert(loadstring(missionScript))()
    Load(snapshot)
end
function calm()
    local s = Save()
    s.startDone = true; s.cameraComplete[0] = true
    s.attack3Destroyed = true; s.attack5Destroyed = true
end
function convoy()
    Save().convoyTime = 0
    tick(1)
end
'''


class Chinese02(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute(HARNESS)
        self.lua.globals().missionScript = SCRIPT
        self.lua.execute(SCRIPT)
        self.lua.globals().Start()

    def run_lua(self, code):
        self.lua.execute(code)

    def test_opening_camera_and_strict_timers(self):
        self.run_lua('''
        tick(0); tick(1)
        assert(count('SetScrap') == 1 and count('SetPilot') == 1)
        assert(count('EnableAllCloaking') == 1 and count('CameraReady') == 1)
        assert(count('AudioMessage', 'ch02001.wav') == 0)
        tick(1.1); assert(count('AudioMessage', 'ch02001.wav') == 1)
        cameraArrived = true; tick(2); tick(4)
        assert(not Save().cameraComplete[0])
        tick(4.1); assert(Save().cameraComplete[0])
        assert(count('AddObjective', 'ch02001.otf') == 1)
        tick(64.1); assert(count('AudioMessage', 'ch02002.wav') == 0)
        tick(64.2); assert(count('AudioMessage', 'ch02002.wav') == 1)
        tick(124.1); assert(spawnCount('annoy_1') == 0)
        tick(124.2); assert(spawnCount('annoy_1') == 4)
        tick(244.3); assert(spawnCount('annoy_1') == 8)
        ''')

    def test_cancel_before_and_after_audio(self):
        self.run_lua('''
        cancelled = true; tick(0)
        assert(count('CameraFinish') == 1 and count('StopAudioMessage') == 0)
        tick(2); assert(count('AudioMessage', 'ch02001.wav') == 0)
        Start(); cancelled = false; tick(3); tick(4.1)
        cancelled = true; tick(4.2)
        assert(count('StopAudioMessage', 'ch02001.wav') == 1)
        ''')

    def test_full_timed_sequence_and_save_load(self):
        self.run_lua('''
        calm(); Save().attack3Destroyed = false; Save().attack5Destroyed = false
        for i = 1, 5 do health['attack_3_' .. i] = 0; health['attack_5_' .. i] = 0 end
        tick(0); assert(spawnCount('hanger_attack_2') == 1)
        reload(); tick(60); assert(spawnCount('attack_6') == 0)
        tick(60.1)
        assert(spawnCount('attack_6') == 9 and spawnCount('attack_7') == 9)
        assert(spawnCount('hanger_attack_3') == 2)
        reload(); tick(300.1); assert(Save().walker == nil)
        tick(300.2); local walker = Save().walker
        assert(walker and spawnCount('walker_spawn') == 1)
        assert(count('Retreat') == 1 and count('SetPerceivedTeam') == 1)
        assert(count('AudioMessage', 'ch02007.wav') == 1)
        tick(310.3); assert(spawnCount('hanger_attack_5') == 1)
        near(walker, 'walker_path', 24, 3); tick(311)
        assert(Save().walker == nil and count('SetCommand') == 1)
        assert(count('AudioMessage', 'ch02008.wav') == 1)
        reload(); tick(600.3); assert(spawnCount('attack_8') == 7)
        tick(870.4)
        assert(spawnCount('convoy_units') == 3 and spawnCount('convoy_defend') == 6)
        assert(count('Goto') == 28) -- 18 + 7 attackers plus 3 APCs
        reload(); tick(930.5)
        assert(spawnCount('convoy_attack_1') == 4)
        for i = 2, 9 do assert(spawnCount('convoy_attack_' .. i) == 1) end
        tick(1170.5); assert(spawnCount('hanger_attack_6') == 2)
        tick(1200); assert(spawnCount('walker_spawn') == 1 and spawnCount('convoy_units') == 3)
        ''')

    def test_walker_ambushes_and_disabled_content(self):
        self.run_lua('''
        calm(); Save().walkerTime = 0; tick(1); local w = Save().walker
        near(w, 'walker_attack_1', 0)
        near(w, 'walker_attack_2', 200); near(w, 'walker_attack_3', 200); tick(2)
        assert(spawnCount('walker_attack_1') == 0 and spawnCount('walker_attack_2') == 0)
        near(w, 'walker_attack_2', 199); near(w, 'walker_attack_3', 199); tick(3)
        assert(spawnCount('walker_attack_2') == 6 and spawnCount('walker_attack_3') == 4)
        reload(); tick(4)
        assert(spawnCount('walker_attack_2') == 6 and spawnCount('walker_attack_3') == 4)
        ''')

    def test_path_end_uses_last_point_and_no_empty_path(self):
        self.run_lua('''
        calm(); Save().walkerTime = 0; tick(1); local w = Save().walker
        near(w, 'walker_path', 0, 0); tick(2); assert(Save().walker == w)
        near(w, 'walker_path', 25, 3); tick(3); assert(Save().walker == w)
        pathCount = 0; near(w, 'walker_path', 0, 3); tick(4); assert(Save().walker == w)
        pathCount = 4; tick(5)
        assert(Save().walker == nil and count('SetCommand') == 1)
        ''')

    def test_convoy_damage_and_proximity_waves(self):
        self.run_lua('''
        calm(); convoy(); local a = Save().apc[0]
        health[a] = .9; near(a, 'trigger_point_1', 30); near(a, 'trigger_point_2', 40); tick(2)
        assert(count('AudioMessage', 'ch02004.wav') == 1 and spawnCount('nav_convoy') == 1)
        assert(count('SetName') == 1 and count('AddObjective', 'ch02002.otf') == 1)
        assert(spawnCount('convoy_attack_10') == 0 and spawnCount('attack_9') == 0)
        near(a, 'trigger_point_1', 29); near(a, 'trigger_point_2', 39); tick(3)
        assert(spawnCount('convoy_attack_10') == 6 and spawnCount('hanger_attack_3') == 3)
        assert(spawnCount('attack_9') == 6 and spawnCount('attack_10') == 6)
        assert(spawnCount('hanger_attack_4') == 3)
        reload(); tick(4)
        assert(spawnCount('convoy_attack_10') == 6 and spawnCount('attack_9') == 6)
        ''')

    def test_one_surviving_apc_arrival_wins_after_audio(self):
        self.run_lua('''
        calm(); convoy(); local a = Save().apc[0]
        health[Save().apc[1]] = 0
        near(a, 'hanger', 30); tick(2); assert(not Save().won)
        near(a, 'hanger', 29); tick(3)
        assert(Save().won and count('StartCockpitTimer', 30) == 1)
        assert(count('SucceedMission') == 0)
        reload(); tick(4); assert(count('AudioMessage', 'ch02005.wav') == 1)
        audioDone['ch02005.wav'] = true; tick(5); tick(6)
        assert(count('SucceedMission', 6) == 1)
        ''')

    def test_hangar_defeat_and_audio_delay(self):
        self.run_lua('''
        calm(); health.hanger = 0; tick(1)
        assert(Save().lost and count('FailMission') == 0)
        reload(); audioDone['ch02006.wav'] = true; tick(2); tick(3)
        assert(count('FailMission', 3) == 1)
        assert(calls[#calls][3] == 'ch02lsea.des')
        ''')

    def test_two_apc_defeat_blocks_same_frame_victory(self):
        self.run_lua('''
        calm(); convoy()
        health[Save().apc[0]] = 0; health[Save().apc[1]] = 0
        near(Save().apc[2], 'hanger', 0); tick(2)
        assert(Save().lost and not Save().won)
        assert(count('AudioMessage', 'ch02005.wav') == 0)
        audioDone['ch02006.wav'] = true; tick(3)
        assert(count('FailMission', 4) == 1 and lastCall('FailMission')[3] == 'ch02lseb.des')
        ''')

    def test_walker_defeat_blocks_convoy_victory(self):
        self.run_lua('''
        calm(); Save().walkerTime = 0; tick(1); local w = Save().walker
        convoy(); health[w] = 0; near(Save().apc[0], 'hanger', 0); tick(2)
        assert(Save().lost and not Save().won and count('FailMission', 2) == 1)
        assert(count('AudioMessage', 'ch02005.wav') == 0)
        ''')

    def test_wrecks_do_not_trigger_proximity_or_win(self):
        self.run_lua('''
        calm(); convoy(); local a = Save().apc[0]; health[a] = 0
        near(a, 'trigger_point_1', 0); near(a, 'trigger_point_2', 0); near(a, 'hanger', 0)
        tick(2)
        assert(not Save().lost and not Save().won)
        assert(not Save().apcTrigger1 and not Save().apcTrigger2)
        ''')

    def test_missing_handles_and_no_apc_target(self):
        self.run_lua('''
        calm(); convoy(); local s = Save()
        for i = 0, 2 do valid[s.apc[i]] = false; s.apc[i] = nil end
        s.convoyAttack1Time = 0; tick(2)
        assert(spawnCount('convoy_attack_1') == 4 and count('Goto') == 3)
        assert(s.lost and not s.won)
        ''')

    def test_base_fallback_and_live_apc_target_selection(self):
        self.run_lua('''
        calm(); convoy(); local s = Save()
        health.hanger = 0; health.recycler = 0; health.armory = 0; health.comm_tower = 0
        health[s.apc[0]] = 0; health[s.apc[1]] = 0
        s.attack8Time = 0; s.convoyAttack1Time = 0; tick(2)
        for _, c in ipairs(calls) do
            if c[1] == 'Goto' and c[4] == 1 then
                assert(c[3] == 'player' or c[3] == s.apc[2])
            end
        end
        ''')

    def test_active_build_and_audio_source_parity(self):
        source = (ROOT / 'References/Chinese02Source/Chinese02Mission.cpp').read_text()
        source = re.sub(r'#if 0.*?#endif', '', source, flags=re.S)
        source = re.sub(r'//[^\n]*|/\*.*?\*/', '', source, flags=re.S)
        active = re.sub(r'--\[=\[.*?\]=\]', '', SCRIPT, flags=re.S)
        active = re.sub(r'--[^\n]*', '', active)
        for function in ('BuildObject', 'AudioMessage', 'GetHandle', 'AddObjective'):
            pattern = function + r'\("([^"\n]+)"'
            self.assertEqual(re.findall(pattern, source), re.findall(pattern, active), function)
        # All 91 active immediate spawns retain their original order/team/path.
        pattern = r'BuildObject\("([^"\n]+)",\s*(\d+),\s*"([^"\n]+)"\)'
        self.assertEqual(re.findall(pattern, source), re.findall(pattern, active))

    def test_source_archive_and_disabled_lua_syntax(self):
        source = (ROOT / 'References/Chinese02Source/Chinese02Mission.cpp').read_bytes()
        blob = b'blob ' + str(len(source)).encode() + b'\0' + source
        self.assertEqual(hashlib.sha1(blob).hexdigest(), 'a73b6107b9e22c7073d36f9e102322c360c511ca')
        disabled = re.search(r'--\[=\[ Cut content:[^\n]*\n(.*?)\]=\]', SCRIPT, re.S)[1]
        self.lua.execute('assert(loadstring(...))', disabled)
        for code in ('-- h = BuildObject("svhraz", 2, "walker_attack_3")',
                     '-- AudioMessage("ch02008.wav")'):
            self.assertIn(code, SCRIPT)


if __name__ == '__main__':
    unittest.main(verbosity=2)
