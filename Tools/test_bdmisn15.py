"""Black Dog 15 sequencing/parity regressions: python Tools/test_bdmisn15.py.

Requires lupa.lua51. Mock engine checks cannot validate assets or cinematics.
"""
from pathlib import Path
import hashlib
import re
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "Scripts/bdmisn15.lua").read_text()
SOURCE = ROOT / "References/BlackDog15Source/BlackDog15Mission.cpp"
HARNESS = r'''
now = 0
timer = 30
objects = {[1] = true}
nextHandle = 1
messages = {}
events = {}
distances = {}
function record(name, ...) events[#events + 1] = {name, ...} end
function count(name, value)
    local n = 0
    for _, e in ipairs(events) do
        if e[1] == name and (value == nil or e[2] == value) then n = n + 1 end
    end
    return n
end
function GetTime() return now end
function GetPlayerHandle() return 1 end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return objects[h] == true end
function GetDistance(h, path)
    assert(IsValid(h), 'invalid distance query')
    return distances[h] or 1000
end
function BuildObject(odf, team, path)
    nextHandle = nextHandle + 1
    objects[nextHandle] = true
    record('BuildObject', odf, team, path)
    return nextHandle
end
function Goto(h, path) assert(IsValid(h)); record('Goto', h, path) end
function SetObjectiveOn(h) assert(IsValid(h)); record('SetObjectiveOn', h) end
function AudioMessage(file) record('AudioMessage', file); return file end
function IsAudioMessageDone(id) assert(id ~= nil and id ~= 0); return messages[id] == true end
function GetCockpitTimer() return timer end
function StartCockpitTimer(t, warn, alert)
    assert(t == 30 and warn == 10 and alert == 5)
    timer = t
    record('StartCockpitTimer', t, warn, alert)
end
function CameraPath(path, height, speed, target)
    assert(path == 'camera_finale' and height == 2400 and speed == 0)
    assert(IsValid(target) and target ~= 1)
    record('CameraPath', path, height, speed, target)
end
function MakeExplosion(odf, path)
    assert(odf == 'xpltrso' and path == 'spawn_explosion1')
    record('MakeExplosion', odf, path)
end
for _, name in ipairs({'SetScrap', 'SetPilot', 'ClearObjectives', 'AddObjective',
    'HideCockpitTimer', 'SucceedMission', 'FailMission', 'ColorFade', 'CameraReady',
    'SetMaxHealth', 'SetCurHealth', 'Hide'}) do
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
    local saved = clone(Save())
    assert(loadstring(missionScript))()
    Load(saved)
end
function allWaves()
    tick(0)
    messages['bd15001.wav'] = true
    tick(1)
    tick(21)
    assert(Save().numUnits == 0)
    tick(21.1)
    assert(Save().numUnits == 1)
    messages['bd15002.wav'] = true
    tick(22)
    reload()
    tick(62)
    assert(Save().numUnits == 1)
    tick(62.1)
    assert(Save().numUnits == 7)
    messages['bd15003.wav'] = true
    tick(63)
    tick(183)
    assert(Save().numUnits == 7)
    tick(183.1)
    assert(Save().numUnits == 14)
    messages['bd15004.wav'] = true
    tick(184)
    tick(364)
    assert(Save().numUnits == 14)
    tick(364.1)
    assert(Save().numUnits == 20)
    tick(424.1)
    assert(Save().numUnits == 20)
    tick(424.2)
    assert(Save().numUnits == 26)
    tick(604.2)
    assert(Save().numUnits == 26)
    tick(604.3)
    assert(Save().numUnits == 32 and Save().allUnitsSpawned)
end
function killAll()
    for i = 1, Save().numUnits do objects[Save().units[i]] = nil end
end
'''


class BlackDog15Tests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute(HARNESS)
        self.lua.globals().missionScript = SCRIPT
        self.lua.execute(SCRIPT)
        self.lua.execute("assert(_VERSION == 'Lua 5.1'); Start()")

    def check(self, code):
        self.lua.execute(code)

    def test_waves_and_escape(self):
        self.check("""
            allWaves()
            assert(count('SetScrap') == 1 and count('SetPilot') == 1)
            assert(count('BuildObject') == 32 and count('Goto') == 32)
            assert(count('SetObjectiveOn') == 32)
            assert(not Save().objective1Complete)
            tick(605)
            assert(count('AudioMessage', 'bd15007.wav') == 0)
            killAll()
            tick(606)
            assert(count('AudioMessage', 'bd15007.wav') == 1)
            assert(count('AddObjective', 'bd15002.otf') == 1)
            reload()
            messages['bd15007.wav'] = true
            tick(607)
            assert(count('StartCockpitTimer') == 1)
            timer = 3; tick(634)
            assert(count('CameraReady') == 0)
            timer = 2; tick(635)
            assert(count('CameraReady') == 1 and count('CameraPath') == 1)
            assert(count('BuildObject', 'apcamr') == 1 and Save().numUnits == 32)
            reload()
            timer = 1; tick(636)
            assert(count('CameraReady') == 1 and count('CameraPath') == 2)
            assert(count('BuildObject', 'apcamr') == 1)
            timer = 0; tick(637)
            assert(count('MakeExplosion') == 1 and count('SucceedMission') == 1)
            assert(count('ColorFade') == 1)
            for _, e in ipairs(events) do
                if e[1] == 'SucceedMission' then
                    assert(e[2] == 642 and e[3] == 'bd15win.des')
                end
            end
            tick(638)
            assert(count('SucceedMission') == 1 and count('StartCockpitTimer') == 1)
            assert(count('FailMission') == 0)
        """)
        # Compare exact ordered spawn/path/ODF triples to native Execute.
        expected = re.findall(r'BuildObject\("([^"]+)", 2, "(spawn_\w+_wave)"\)', SOURCE.read_text())
        actual = []
        for i in range(1, len(self.lua.globals().events) + 1):
            e = self.lua.globals().events[i]
            if e[1] == "BuildObject" and e[3] == 2:
                actual.append((e[2], e[4]))
        self.assertEqual(expected, actual)
        self.assertEqual(len(actual), 32)

    def test_breach_loss_exclusive_and_saved_audio_delay(self):
        self.check("""
            allWaves()
            distances[Save().units[32]] = 100
            tick(605)
            assert(not Save().wonLost)
            distances[Save().units[32]] = 99
            tick(606)
            assert(Save().wonLost and count('AudioMessage', 'bd15011.wav') == 1)
            killAll()
            reload()
            tick(607)
            assert(not Save().objective1Complete)
            messages['bd15011.wav'] = true
            tick(608)
            reload()
            tick(613)
            assert(count('AudioMessage', 'bd15012.wav') == 0)
            tick(613.1)
            assert(count('AudioMessage', 'bd15012.wav') == 1)
            messages['bd15012.wav'] = true
            tick(614)
            assert(count('FailMission') == 1)
            assert(count('AudioMessage', 'bd15007.wav') == 0)
            assert(count('StartCockpitTimer') == 0 and count('SucceedMission') == 0)
            tick(615)
            assert(count('FailMission') == 1)
        """)

    def test_dead_and_missing_handles_do_not_breach(self):
        self.check("""
            tick(0)
            messages['bd15001.wav'] = true; tick(1); tick(21.1)
            local h = Save().units[1]
            distances[h] = 0; objects[h] = false
            tick(22)
            assert(not Save().wonLost)
            objects[h] = nil; tick(23)
            assert(not Save().wonLost)
        """)

    def test_launch_warning_once_and_strict_radius(self):
        self.check("""
            distances[1] = 300; tick(0)
            assert(count('AudioMessage', 'bd15010.wav') == 0)
            distances[1] = 299; tick(1); reload(); tick(2)
            assert(count('AudioMessage', 'bd15010.wav') == 1)
        """)

    def test_no_early_completion_and_save_between_waves(self):
        self.check("""
            tick(0)
            messages['bd15001.wav'] = true; tick(1); tick(21.1)
            killAll(); reload(); tick(22)
            assert(not Save().objective1Complete)
            messages['bd15002.wav'] = true; tick(23); tick(63.1)
            killAll(); reload(); tick(64)
            assert(not Save().objective1Complete)
            messages['bd15003.wav'] = true; tick(65); tick(185.1)
            killAll(); reload(); tick(186)
            assert(not Save().objective1Complete)
            messages['bd15004.wav'] = true; tick(187); tick(367.1)
            killAll(); reload(); tick(368)
            assert(not Save().objective1Complete)
            tick(427.2); killAll(); reload(); tick(428)
            assert(not Save().objective1Complete)
            tick(607.3)
            assert(Save().numUnits == 32 and not Save().objective1Complete)
            killAll(); tick(608)
            assert(Save().objective1Complete)
            assert(count('AudioMessage', 'bd15007.wav') == 1)
        """)

    def test_cut_explosion_test_switch(self):
        self.lua.execute(SCRIPT.replace("local DO_EXPLOSION = false",
                                        "local DO_EXPLOSION = true"))
        self.check("""
            Start(); tick(0)
            assert(count('AudioMessage', 'bd15007.wav') == 1)
            messages['bd15007.wav'] = true; tick(1)
            assert(count('StartCockpitTimer') == 1)
            tick(1000)
            assert(Save().numUnits == 0 and count('Goto') == 0)
            timer = 0; tick(1001)
            assert(count('SucceedMission') == 1 and count('MakeExplosion') == 1)
        """)

    def test_source_archive(self):
        data = SOURCE.read_bytes()
        digest = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        self.assertEqual(digest, "7a7d7d440cbc1ec875abf02a97683349820d1814")
        # Every commented-out Execute statement remains visible in the Lua port.
        for statement in ("explTime = GetTime() + 32.0f;",
                          "cameraTime = GetTime() + 30.0f;",
                          "sound8Time = GetTime() + 32.0f;",
                          "if (dist > 800.0f)",
                          'sound9 = AudioMessage("bd15013.wav");'):
            self.assertIn(statement, SCRIPT)


if __name__ == "__main__":
    unittest.main()
