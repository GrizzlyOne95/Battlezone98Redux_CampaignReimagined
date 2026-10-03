"""Black Dog 10 logic regressions; run with Python and lupa's Lua 5.1 module.

Engine calls are mocked: this validates sequencing, not in-game AI/camera/assets.
"""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "Scripts/bdmisn10.lua").read_text()
HARNESS = r'''
now = 0
health = {1, 1, 1, 1, 1, 1}
valid = {true, true, true, true, true, true}
near = nil
distance = 400
cancelled = false
arrived = false
audioDone = {}
calls = {}
nextHandle = 100
function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
function count(name)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
    return n
end
function builds(odf)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == 'BuildObject' and c[2] == odf then n = n + 1 end
    end
    return n
end
function GetTime() return now end
function GetPlayerHandle() return 50 end
function GetHandle(label) return tonumber(string.match(label, 'destroy_(%d)')) end
function IsValid(h) return valid[h] == true end
function GetHealth(h) assert(h ~= nil and valid[h]); return health[h] end
function GetNearestUnitOnTeam(path, point, team)
    assert(point == 0 and team == 1)
    record('Nearest', path, point, team)
    return near
end
function GetDistance(h, path, point) assert(h == near and point == 0); return distance end
function BuildObject(odf, team, path)
    record('BuildObject', odf, team, path)
    nextHandle = nextHandle + 1
    return nextHandle
end
function CameraReady() record('CameraReady'); return true end
function CameraFinish() record('CameraFinish'); return true end
function CameraCancelled() return cancelled end
function CameraPath(path, height, speed, target)
    record('CameraPath', path, height, speed, target)
    return arrived
end
function AudioMessage(file) record('AudioMessage', file); return file end
function IsAudioMessageDone(msg) assert(msg ~= nil); return audioDone[msg] == true end
function StopAudioMessage(msg) assert(msg ~= nil); record('StopAudioMessage', msg) end
for _, name in ipairs({'SetScrap', 'SetPilot', 'ClearObjectives', 'AddObjective',
    'Hunt', 'Goto', 'SetIndependence', 'Follow', 'SucceedMission'}) do
    local key = name
    _G[key] = function(...) record(key, ...) end
end
function tick(t) now = t; Update(0.1) end
function killAll() health = {0, 0, 0, 0, 0, 0} end
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
'''


class BlackDog10Tests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute(HARNESS)
        self.lua.globals().missionScript = SCRIPT
        self.lua.execute(SCRIPT)
        self.lua.execute("assert(_VERSION == 'Lua 5.1'); Start()")

    def check(self, code):
        self.lua.execute(code)

    def test_startup_and_all_ambushes(self):
        self.check('''
            tick(0); tick(1)
            assert(count('SetScrap') == 2 and count('SetPilot') == 1)
            assert(count('AddObjective') == 1)
            assert(count('BuildObject') == 0) -- no nearest friendly
            near = 50; tick(2)
            assert(count('BuildObject') == 0) -- exactly 400 is outside
            distance = 399.9; tick(3)
            assert(count('BuildObject') == 46 and count('Hunt') == 46)
            assert(builds('cvfigh') == 27 and builds('cvtnk') == 13)
            assert(builds('cvltnk') == 2 and builds('cvwalk') == 3)
            assert(builds('cvhtnk') == 1)
            -- Six/six/six/eight defences plus four groups of five patrols.
            reload(); tick(4)
            assert(count('BuildObject') == 46 and count('SetScrap') == 2)
        ''')

    def test_intro_waits_for_arrival_audio_and_two_seconds(self):
        self.check('''
            tick(0); audioDone['bd10001.wav'] = true; tick(10)
            assert(not Save().cameraComplete[1])
            arrived = true; tick(11)
            assert(Save().cameraTime == 13)
            reload(); tick(13); assert(not Save().cameraComplete[1])
            tick(13.1); assert(Save().cameraComplete[1])
            assert(count('CameraFinish') == 1 and count('AudioMessage') == 1)
        ''')

    def test_cancel_intro(self):
        self.check('''
            cancelled = true; tick(0); tick(1)
            assert(Save().cameraComplete[1])
            assert(count('StopAudioMessage') == 1 and count('CameraFinish') == 1)
        ''')

    def test_full_sequence_and_save_load(self):
        self.check('''
            cancelled = true; tick(0); cancelled = false
            health = {0,0,0,0,0,1}; tick(1)
            assert(not Save().objective1Complete)
            killAll(); tick(2); assert(Save().navDelay == 12)
            reload(); tick(12); assert(builds('apcamr') == 0)
            tick(12.1); assert(builds('apcamr') == 1)
            tick(20); assert(builds('bvapc') == 0) -- nav audio still playing
            audioDone['bd10002.wav'] = true; tick(21)
            assert(Save().apcDelay == 26)
            reload(); tick(26); assert(builds('bvapc') == 0)
            tick(26.1)
            assert(builds('bvapc') == 1 and builds('cbport') == 1)
            assert(Save().apcCameraTimeout == 33.1)
            reload(); tick(33.1); assert(builds('bvrecy') == 0)
            tick(33.2)
            assert(builds('bvrecy') == 1 and builds('cvtnka') == 6)
            assert(count('Follow') == 6 and count('SetIndependence') == 6)
            assert(Save().cameraTime == 43.2)
            audioDone['bd10003.wav'] = true
            reload(); tick(43.2); assert(count('SucceedMission') == 0)
            tick(43.3); assert(count('SucceedMission') == 1)
            assert(count('CameraFinish') == 2) -- final cut CameraFinish stays off
            local last = calls[#calls]
            assert(last[1] == 'SucceedMission' and last[2] == 44.3
                and last[3] == 'bd10win.des')
            reload(); tick(44); assert(count('SucceedMission') == 1)
            assert(builds('bvrecy') == 1 and builds('apcamr') == 1)
        ''')

    def test_apc_and_final_camera_cancellation(self):
        self.check('''
            cancelled = true; tick(0); cancelled = false
            killAll(); tick(1); tick(11.1)
            audioDone['bd10002.wav'] = true; tick(12); tick(17.1)
            cancelled = true; tick(17.2)
            -- Independent source if-blocks allow both cinematics in one update.
            assert(builds('bvrecy') == 1 and builds('cvtnka') == 6)
            assert(Save().cameraComplete[2] and Save().cameraComplete[3])
            assert(count('SucceedMission') == 1 and count('StopAudioMessage') == 2)
            assert(count('CameraFinish') == 2)
        ''')

    def test_missing_deleted_targets_are_zero_health(self):
        self.check('''
            tick(0); killAll()
            Save().destroy[1] = nil; valid[2] = false
            health[6] = 0.1; tick(1); assert(not Save().objective1Complete)
            health[6] = 0; tick(2); assert(Save().objective1Complete)
        ''')


if __name__ == '__main__':
    unittest.main()
