"""Chinese06 stock-API simulation checks. Run with Python + lupa.lua51."""
from pathlib import Path
import hashlib
import re
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "Scripts/ch06.lua").read_text()

MOCK = r"""
now = 0
objects, labels, events, audioDone = {}, {}, {}, {}
nextHandle = 0
function record(kind, ...)
    events[#events + 1] = {kind, ...}
end
function create(odf, team, path)
    nextHandle = nextHandle + 1
    objects[nextHandle] = {odf=odf, team=team, path=path, health=1, valid=true, alive=true}
    return nextHandle
end
function GetHandle(label)
    if missingLabels and missingLabels[label] then return nil end
    if not labels[label] then
        labels[label] = create(label, label:match("^psu") and 2 or 1, label)
    end
    return labels[label]
end
function GetPlayerHandle() return 10000 end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil and objects[h].valid end
function IsAlive(h) return objects[h] ~= nil and objects[h].valid and objects[h].alive end
function GetHealth(h) assert(IsValid(h), "invalid health"); return objects[h].health end
function GetDistance(h, p)
    assert(IsValid(h), "invalid distance")
    local d = objects[h].distances
    return d and d[p] or 10000
end
function BuildObject(odf, team, p)
    local h = create(odf, team, p)
    record("build", odf, team, p, h)
    return h
end
function SetPerceivedTeam(h, team)
    assert(IsValid(h)); objects[h].perceived = team; record("perceived", h, team)
end
function SetTeamNum(h, team)
    assert(IsValid(h)); objects[h].team = team; record("team", h, team)
end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function SetPilotClass(h, odf)
    assert(IsValid(h)); objects[h].pilot=odf; record("pilotClass",h,odf)
end
function Goto(h, p, priority) assert(IsValid(h)); record("goto", h, p, priority) end
function Attack(h, target, priority)
    assert(IsValid(h) and IsValid(target)); record("attack", h, target, priority)
end
function SetObjectiveName(h, name) assert(IsValid(h)); record("name", h, name) end
function SetAIP(p) record("aip", p) end
function SetPilot(t, n) record("pilots",t,n) end
function SetScrap(t, n) record("scrap",t,n) end
function AddScrap(t, n) record("addScrap",t,n) end
function ClearObjectives() record("clear") end
function AddObjective(p, c) record("objective",p,c) end
function AudioMessage(p) record("audio",p); return p end
function IsAudioMessageDone(p) return audioDone[p] == true end
function SucceedMission(t,p) record("win",t,p) end
function FailMission(t,p) record("lose",t,p) end
function AllObjects()
    local i = 0
    return function()
        repeat i = i + 1 until i > nextHandle or objects[i].valid
        if i <= nextHandle then return i end
    end
end
function tick(t) now=t; Update(0.05) end
function kill(h, deleted)
    objects[h].health=0; objects[h].alive=false
    if deleted then objects[h].valid=false end
end
function clone(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k,v in pairs(t) do r[k]=clone(v) end
    return r
end
"""


class MissionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute(SCRIPT)
        self.g = self.lua.globals()
        self.g.Start()
        self.g.tick(0)

    def state(self):
        return self.g.Save()

    def events(self, kind):
        return [e for _, e in self.g.events.items() if e[1] == kind]

    def spawn(self, choice=0):
        self.lua.execute("math.random = function(n) return %d %% n + 1 end" % choice)
        self.state().ranTime = 1
        self.g.tick(2)
        return self.state()

    def test_lua51_and_source_archive(self):
        self.assertEqual(self.lua.eval("_VERSION"), "Lua 5.1")
        source = (ROOT / "References/Chinese06Source/Chinese06Mission.cpp").read_bytes()
        blob = b"blob " + str(len(source)).encode() + b"\0" + source
        self.assertEqual(hashlib.sha1(blob).hexdigest(),
                         "fb13ebac8532415ad2a8e3ad29677d1514087d6f")
        self.assertIn('--BuildObject("cvtnk", 1, user);', SCRIPT)
        self.assertIn('--_DEBUGMSG0("Setting traitor', SCRIPT)
        native = source.decode()
        # Ensure all referenced audio/objective/debrief/AIP resources survive.
        for resource in re.findall(r'"([^"]+\.(?:wav|otf|des|aip))"', native):
            self.assertIn('"' + resource + '"', SCRIPT)

    def test_startup_and_strict_audio_timeline(self):
        self.assertEqual([(e[2], e[3]) for e in self.events("scrap")], [(2,0),(1,50)])
        self.g.tick(2)
        self.assertFalse(self.events("audio"))
        self.g.tick(2.01)
        self.assertEqual(self.events("audio")[0][2], "ch06001.wav")
        self.assertEqual(self.events("objective")[0][2], "ch06001.otf")
        self.g.tick(60)
        self.assertEqual(len(self.events("audio")), 1)
        self.g.tick(60.01)
        self.assertEqual(self.events("audio")[-1][2], "ch06002.wav")
        self.g.audioDone["ch06002.wav"] = True
        self.g.tick(61)
        self.assertEqual(self.state().sound3Time, 76)
        self.assertEqual(self.events("name")[0][3], "CCA Base")
        self.g.tick(76)
        self.assertEqual(len(self.events("audio")), 2)
        self.g.tick(76.01)
        self.g.audioDone["ch06003.wav"] = True
        self.g.tick(77)
        self.assertEqual(self.state().sound4Time, 78)
        self.g.tick(78.01)
        self.g.audioDone["ch06004.wav"] = True
        self.g.tick(79)
        self.assertEqual(self.state().ranTime, 259)
        self.g.tick(259)
        self.assertFalse(self.state().ranDone)
        self.g.tick(259.01)
        self.assertTrue(self.state().ranDone)

    def test_all_three_convoy_entries_and_pilots(self):
        for choice in range(3):
            self.setUp()
            s = self.spawn(choice)
            builds = self.events("build")
            self.assertEqual(len(builds), 12)
            self.assertEqual([e[2] for e in builds], ["cvfigh"]*4+["cvtnk"]*4+["cvhraz"]*4)
            self.assertTrue(all(e[3] == 1 and e[4] == "ran_%d" % (choice+1) for e in builds))
            self.assertEqual(s.ranChoice, choice)
            self.assertTrue(all(e[3] == "ran_%d_path" % (choice+1) and e[4] == 1
                                for e in self.events("goto")))
            for _, h in s.reinf.items():
                o = self.g.objects[h]
                self.assertEqual((o.team, o.perceived, o.pilot), (1,2,"sspilo"))
            self.assertFalse(s.turnTraitor)

    def test_damage_threshold_and_dead_member_betrayal(self):
        s = self.spawn()
        self.g.objects[s.reinf[1]].health = 0.70
        self.g.tick(3)
        self.assertFalse(s.turnTraitor)
        self.g.kill(s.reinf[1], True)
        self.g.tick(4)
        self.assertTrue(s.turnTraitor)
        self.assertEqual(len(self.events("attack")), 11)
        self.assertEqual(s.moreRanTime, 124)
        self.assertTrue(all(e[4] == 0 for e in self.events("attack")))
        self.g.tick(5)
        self.assertEqual(len([e for e in self.events("audio") if e[2]=="ch06005.wav"]),1)

    def test_proximity_threshold_and_followup_once(self):
        s = self.spawn(1)
        self.g.objects[s.reinf[12]].distances = self.lua.table_from({"ran_2_trigger":75})
        self.g.tick(3)
        self.assertFalse(s.turnTraitor)
        self.g.objects[s.reinf[12]].distances["ran_2_trigger"] = 74.99
        self.g.tick(4)
        self.assertTrue(s.turnTraitor)
        self.g.tick(124)
        self.assertEqual(len(self.events("build")),12)
        self.g.tick(124.01)
        follow = self.events("build")[12:]
        self.assertEqual([e[2] for e in follow], ["svfigh"]*4+["svtank"]*4)
        self.assertTrue(all(e[3] == 2 and e[4] in ("ran_1","ran_3") for e in follow))
        for t in (124.02,125,200,500): self.g.tick(t)
        self.assertEqual(len(self.events("build")),20)

    def test_raids_retry_refill_and_third_round_cap(self):
        s = self.state()
        self.g.tick(600.01)
        self.assertEqual(s.annoyStartTime,660.01)
        self.g.objects[s.recycler].distances = self.lua.table_from({"activate_1":499})
        self.g.tick(660.02)
        self.assertEqual(len(self.events("build")),0)  # strict next-update gate
        self.g.tick(660.03)
        self.assertEqual(len(self.events("build")),10)
        self.assertTrue(all(e[4]=="annoy_1" for e in self.events("build")))
        self.assertTrue(all(e[3]=="annoy_1_path" and e[4] is None for e in self.events("goto")))
        self.g.tick(960.04)
        self.assertEqual(len(self.events("build")),10)  # surviving slots retained
        for _,h in s.annoy.items(): self.g.kill(h,True)
        self.g.tick(1260.05)
        self.assertEqual(s.numAnnoyRounds,3)
        self.assertEqual(s.maxAnnoy,6)
        self.assertEqual(len(self.events("build")),16)
        for _,h in s.psu.items(): self.g.kill(h,True)
        self.g.tick(1560.06)
        self.assertEqual(s.annoyTime,999999.9)
        self.assertEqual(len(self.events("build")),16)

    def test_twenty_minute_scrap_once(self):
        self.g.tick(1200)
        self.assertFalse(self.events("addScrap"))
        self.g.tick(1200.01)
        self.g.tick(1300)
        self.assertEqual([(e[2],e[3]) for e in self.events("addScrap")],[(2,50)])

    def test_victory_counts_every_living_enemy_including_pilots(self):
        s = self.spawn()
        for _,h in s.reinf.items(): self.g.kill(h,True)
        for _,h in s.psu.items(): self.g.kill(h,True)
        pilot = self.g.create("sspilo",2,"anywhere")
        self.g.tick(3)
        self.assertTrue(s.reinfDestroyed)
        self.assertFalse(s.won)
        self.g.kill(pilot,True)
        self.g.tick(4)
        self.assertEqual([(e[2],e[3]) for e in self.events("win")],[(5,"ch06win.des")])
        self.g.tick(5)
        self.assertEqual(len(self.events("win")),1)
        self.assertEqual(len([e for e in self.events("audio") if e[2]=="ch06006.wav"]),1)

    def test_defeat_requires_both_producers_and_blocks_later_win(self):
        s = self.state()
        self.g.kill(s.recycler,True)
        self.g.tick(1)
        self.assertFalse(s.lost)
        self.g.kill(s.factory,True)
        self.g.tick(2)
        self.assertEqual([(e[2],e[3]) for e in self.events("lose")],[(2,"ch06lsea.des")])
        s.ranDone = True
        for _,h in s.psu.items(): self.g.kill(h,True)
        self.g.tick(3)
        self.assertFalse(self.events("win"))
        self.assertEqual(len(self.events("lose")),1)

    def test_no_base_target_and_missing_handles(self):
        s = self.spawn()
        for name in ("recycler","factory","armoury","silo1","silo2"):
            self.g.kill(s[name],True)
        self.g.objects[s.reinf[1]].health=0.69
        self.g.tick(3)
        self.assertTrue(s.turnTraitor)
        self.assertFalse(self.events("attack"))
        self.assertTrue(s.lost)
        self.g.tick(123.01)
        self.assertEqual(len(self.events("build")),20)
        self.assertFalse(self.events("attack"))
        self.lua.execute('missingLabels = {avrecy2_recycler=true, avmuf2_factory=true}')
        self.g.Start()
        self.g.tick(200)
        self.assertTrue(self.state().lost)

    def test_save_load_pending_audio_convoy_and_consumed_wave(self):
        self.g.tick(60.01)
        saved = self.g.clone(self.state())
        self.g.Load(saved)
        self.g.tick(61)
        self.assertEqual(len(self.events("audio")),2)
        self.g.audioDone["ch06002.wav"]=True
        self.g.tick(62)
        self.assertEqual(len(self.events("name")),1)
        s = self.spawn(2)
        self.g.objects[s.reinf[1]].health=0.69
        self.g.tick(3)
        self.g.Load(self.g.clone(s))
        self.g.tick(123.01)
        self.assertEqual(len(self.events("build")),21)  # nav + convoy + followup
        self.g.Load(self.g.clone(self.state()))
        self.g.tick(124)
        self.assertEqual(len(self.events("build")),21)
        self.assertEqual(len(self.events("scrap")),2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
