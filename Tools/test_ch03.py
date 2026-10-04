"""Chinese03 port regression checks with real Lua 5.1 and a strict engine mock.

Run: python Tools/test_ch03.py (requires lupa with its lua51 runtime).
The mock checks script behavior; it cannot prove engine AI attachment or assets.
"""
from pathlib import Path
import hashlib
import re
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Scripts/ch03.lua"
SOURCE = ROOT / "References/Chinese03Source/Chinese03Mission.cpp"
MOCK = r'''
now = 0; player = "player"; objects = {}; events = {}; audioDone = {}; distances = {}
timer = 780; nextId = 0
local function record(name, ...) events[#events+1] = {name, ...} end
local function obj(h) assert(h and objects[h] and objects[h].valid, "invalid handle"); return objects[h] end
function GetTime() return now end
function GetPlayerHandle() return player end
function GetHandle(label)
    objects[label] = {valid=true, health=100, ammo=100, team=1, piloted=false}
    return label
end
function IsValid(h) return objects[h] ~= nil and objects[h].valid end
function GetHealth(h) return obj(h).health / 1000 end
function GetCurHealth(h) return obj(h).health end
function GetCurAmmo(h) return obj(h).ammo end
function GetTeamNum(h) return obj(h).team end
function IsAliveAndPilot(h) return obj(h).health > 0 and obj(h).piloted end
function GetDistance(h, path) obj(h); return distances[h .. ":" .. path] or 10000 end
function BuildObject(odf, team, path)
    nextId = nextId + 1; local h = "unit" .. nextId
    objects[h] = {valid=true,health=1000,ammo=1000,team=team,piloted=true}
    record("BuildObject", odf, team, path, h); return h
end
function AudioMessage(file) record("AudioMessage", file); return file end
function IsAudioMessageDone(h) assert(h); return audioDone[h] or false end
function GetCockpitTimer() return timer end
function StartCockpitTimer(a,b,c) timer=a; record("StartCockpitTimer",a,b,c) end
function SetPerceivedTeam(h, team) obj(h); record("SetPerceivedTeam",h,team) end
function SetObjectiveOn(h) obj(h); record("SetObjectiveOn",h) end
function SetObjectiveOff(h) obj(h); record("SetObjectiveOff",h) end
function SetObjectiveName(h, name) obj(h); record("SetObjectiveName",h,name) end
function SetPilotClass(h, cls) obj(h); record("SetPilotClass",h,cls) end
function Stop(h, p) obj(h); record("Stop",h,p) end
function Goto(h, path, p) obj(h); record("Goto",h,path,p) end
function Attack(h, target, p) obj(h); obj(target); record("Attack",h,target,p) end
function Defend2(h, target, p) obj(h); obj(target); record("Defend2",h,target,p) end
for _, name in ipairs({"SetPilot","SetScrap","AddScrap","ClearObjectives","AddObjective",
    "StopCockpitTimer","HideCockpitTimer","MakeExplosion","FailMission","SucceedMission"}) do
    local n = name; _G[n] = function(...) record(n, ...) end
end
'''


class Mission(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute(SCRIPT.read_text())
        self.g = self.lua.globals()
        self.g.Start()
        self.step(0)

    def step(self, time):
        self.g.now = time
        self.g.Update(0.1)

    @property
    def state(self):
        return self.g.Save()

    def events(self, name):
        return [list(e.values()) for e in self.g.events.values() if e[1] == name]

    def ready(self):
        for i in range(1, 7):
            self.g.objects[f"howitzer_{i}"]["health"] = 401
            self.g.objects[f"howitzer_{i}"]["ammo"] = 401
        self.step(1)

    def spawn(self):
        self.ready()
        self.step(1.1)

    def near(self, h, path, distance):
        self.g.distances[f"{h}:{path}"] = distance

    def test_initialization_and_strict_opening_audio(self):
        self.assertEqual(self.events("StartCockpitTimer"), [["StartCockpitTimer",780,30,10]])
        self.assertEqual(len(self.events("SetObjectiveOn")), 6)
        self.step(1)
        self.assertFalse(self.events("AudioMessage"))
        self.step(1.01)
        self.assertEqual(self.events("AudioMessage"), [["AudioMessage","ch03001.wav"]])
        self.g.audioDone["ch03001.wav"] = True
        self.step(2)
        self.assertIsNone(self.state["openingSound"])

    def test_repair_thresholds_and_next_frame_spawn(self):
        for i in range(1,7):
            self.g.objects[f"howitzer_{i}"]["health"] = 400
            self.g.objects[f"howitzer_{i}"]["ammo"] = 401
        self.step(0.5)
        self.assertFalse(self.state["objective1Complete"])
        self.ready()
        self.assertTrue(self.state["objective1Complete"])
        self.assertEqual(len(self.events("BuildObject")), 1)
        self.step(1)  # strict '<', not '<='
        self.assertEqual(len(self.events("BuildObject")), 1)
        self.step(1.1)
        builds = self.events("BuildObject")
        self.assertEqual(len(builds), 31)
        self.assertEqual(sum(e[1]=="svapcq" for e in builds), 1)
        for i in range(6):
            block = builds[1+5*i:6+5*i]
            self.assertEqual([e[1] for e in block[1:]], ["svtank","svtank","svhraz","svfigh"])
            self.assertEqual(block[0][3], ["apc_east","apc_north","apc_west"][i//2])
        self.assertEqual(len(self.events("Defend2")),24)

    def test_all_six_random_general_slots(self):
        for slot in range(6):
            self.setUp()
            self.lua.execute(f"math.random = function(a,b) assert(a==0 and b==5); return {slot} end")
            self.spawn()
            self.assertEqual(self.state["generalApc"],slot)
            self.assertEqual(self.state["general"],self.state["apc"][slot])

    def test_factory_strict_timer_resources_and_cut_scavs(self):
        self.step(480)
        self.assertFalse(self.events("BuildObject"))
        self.step(480.01)
        self.assertEqual([e[1] for e in self.events("BuildObject")],["cvmufa","cvslfa"])
        self.assertEqual(self.events("AddScrap"),[["AddScrap",1,100],["AddScrap",1,100]])
        self.step(481)
        self.assertEqual(len(self.events("BuildObject")),2)

    def test_three_routes_and_fifteen_explosions(self):
        self.spawn()
        for route, path in enumerate(["east_exit","north_exit","west_exit"]):
            self.near(self.state["apc"][route*2],path,40)
        self.step(2)
        self.assertFalse(self.events("MakeExplosion"))
        for route, path in enumerate(["east_exit","north_exit","west_exit"]):
            self.near(self.state["apc"][route*2+1],path,39.99)
        self.step(3)
        self.assertEqual(len(self.events("MakeExplosion")),3)
        self.assertEqual(len(self.events("Attack")),6)
        for t in [8,13,18,23]: self.step(t)
        self.assertEqual(len(self.events("MakeExplosion")),15)
        self.step(24)
        self.assertEqual(len(self.events("MakeExplosion")),15)
        self.assertEqual([e[1] for e in self.events("AudioMessage")][-3:],
                         ["ch03003.wav","ch03004.wav","ch03005.wav"])

    def test_timeout_has_source_priority_over_last_repair(self):
        for i in range(1,7):
            self.g.objects[f"howitzer_{i}"]["health"] = 401
            self.g.objects[f"howitzer_{i}"]["ammo"] = 401
        self.g.timer = 0
        self.step(780)
        self.assertTrue(self.state["lost"])
        self.assertEqual(self.events("FailMission"),[["FailMission",781,"ch03lsea.des"]])

    def test_factory_destruction_and_general_audio_loss(self):
        self.step(481)
        self.g.objects[self.state["factory"]]["valid"] = False
        self.step(482)
        self.assertEqual(self.events("FailMission"),[["FailMission",483,"ch03lsee.des"]])
        self.setUp()
        self.spawn()
        self.g.objects[self.state["general"]]["valid"] = False
        self.step(2)
        self.assertTrue(self.state["lost"])
        self.assertFalse(self.events("FailMission"))
        self.g.audioDone["ch03008.wav"] = True
        self.step(3)
        self.step(3.1)
        self.assertEqual(self.events("FailMission"),[["FailMission",4,"ch03lsec.des"]])

    def test_escape_grace_audio_and_post_win_guard(self):
        self.spawn()
        self.near(self.state["general"],"base_fail",49)
        self.step(121.1)
        self.assertFalse(self.state["lost"])
        self.step(121.2)
        self.assertTrue(self.state["lost"])
        self.g.audioDone["ch03009.wav"] = True
        self.step(122)
        self.step(123)
        self.assertEqual(self.events("FailMission"),[["FailMission",123,"ch03lsed.des"]])
        self.setUp()
        self.spawn()
        self.g.objects[self.state["general"]]["team"] = 1
        self.near(self.state["general"],"won_mission",29)
        self.step(2)
        self.near(self.state["general"],"base_fail",0)
        self.step(130)
        self.assertFalse(self.state["lost"])
        self.assertEqual(self.events("SucceedMission"),[["SucceedMission",3,"ch03win.des"]])

    def test_capture_ambush_and_delivery(self):
        self.spawn()
        self.step(481)
        general = self.state["general"]
        self.g.objects[general]["team"] = 1
        self.near(general,"trigger_1",29)
        self.step(482)
        self.assertTrue(self.state["objective2Complete"])
        self.assertTrue(self.state["trigger1Done"])
        self.assertEqual([e[1] for e in self.events("BuildObject")][-15:],
                         ["svfigh"]*10+["svtank"]*3+["svfigh"]*2)
        self.assertEqual(len(self.events("Attack")),15)
        self.step(483)
        self.assertEqual(len(self.events("Attack")),15)
        self.near(general,"won_mission",30)
        self.step(484)
        self.assertFalse(self.state["won"])
        self.near(general,"won_mission",29)
        self.step(485)
        self.assertEqual(self.events("SucceedMission"),[["SucceedMission",486,"ch03win.des"]])

    def test_early_ambush_without_factory_and_dead_apc_distance(self):
        self.spawn()
        general = self.state["general"]
        self.g.objects[general]["team"] = 1
        self.near(general,"trigger_1",0)
        self.step(2)  # factory is still nil: commands are safely omitted
        self.assertEqual(len(self.events("Attack")),10)
        self.setUp()
        self.spawn()
        for i in [0,1]:
            self.g.objects[self.state["apc"][i]]["health"] = 0
            self.near(self.state["apc"][i],"east_exit",0)
        self.step(2)
        self.assertFalse(self.state["turnedAround"][0])

    def test_final_howitzer_exit_one_shot_and_no_extra_enter_audio(self):
        self.g.player = "howitzer_6"
        self.ready()
        self.assertTrue(self.state["inHowitzer"][5])
        self.g.player = "player"
        self.step(1.1)
        self.step(1.2)
        self.assertEqual(self.events("Stop"),[["Stop","howitzer_6",0]])
        self.assertEqual(sum(e[1]=="ch03002.wav" for e in self.events("AudioMessage")),1)

    def test_save_load_no_reinitialization_or_duplicate_spawns(self):
        self.spawn()
        self.step(481)
        # Copy the serializable table graph, as the engine saves a snapshot
        # rather than retaining the same mutable Lua table reference.
        saved = self.lua.eval('''function(s)
            local function copy(t)
                if type(t) ~= "table" then return t end
                local result = {}
                for k,v in pairs(t) do result[k] = copy(v) end
                return result
            end
            return copy(s)
        end''')(self.state)
        count = len(self.events("BuildObject"))
        self.g.Load(saved)
        self.step(482)
        self.assertEqual(len(self.events("BuildObject")),count)
        self.assertEqual(len(self.events("StartCockpitTimer")),1)
        self.assertEqual(self.state["general"],saved["general"])

    def test_source_asset_parity_and_disabled_content(self):
        data = SOURCE.read_bytes()
        self.assertEqual(hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest(),
                         "41b44bf53de2ce74a49bca874aaa440bb2fcfc9c")
        source = SOURCE.read_text()
        lua = SCRIPT.read_text()
        active_source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
        active_lua = re.sub(r'--\[\[.*?\]\]|--[^\n]*', '', lua, flags=re.S)
        # Source-only diagnostics and disabled cspilo/scavenger code are excluded.
        assets = lambda s: set(re.findall(r'"([^"\n]+\.(?:wav|otf|des))"', s))
        self.assertEqual(assets(active_source),assets(active_lua))
        builds = lambda s: set(re.findall(r'BuildObject\("([^"]+)"',s))
        self.assertEqual(builds(active_source),builds(active_lua))
        self.assertEqual(lua.count('--h = BuildObject("cvscav"'),4)
        self.assertIn('obj->curPilot = 0;//*(PrjID*)"cspilo\\0";',lua)


if __name__ == "__main__":
    unittest.main(verbosity=2)
