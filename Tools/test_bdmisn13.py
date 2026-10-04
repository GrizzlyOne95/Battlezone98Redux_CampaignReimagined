"""Source-derived flow checks; run with Python and lupa's Lua 5.1 runtime."""
from pathlib import Path
import re
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "Scripts/bdmisn13.lua").read_text()
SOURCE = (ROOT / "References/BlackDog13Source/BlackDog13Mission.cpp").read_text()


def mission():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        now = 0; timer = 2700; scrap = 0; cancelled = false; arrived = false
        health = {}; distance = {}; recycled = {}; done = {}; calls = {}
        local function record(name, ...)
            calls[#calls+1] = {name, ...}
        end
        function GetHandle(label) health[label] = 1; return label end
        function GetPlayerHandle() return "player" end
        health.player = 1
        function IsValid(h) return health[h] ~= nil and health[h] > 0 end
        function GetHealth(h) assert(h ~= nil); return health[h] or 0 end
        function GetDistance(h, target) return distance[target] or 100 end
        function IsRecycledByTeam(h, team)
            assert(h ~= nil and team == 1); return recycled[h] == true
        end
        function GetTime() return now end
        function GetScrap(team) return scrap end
        function GetCockpitTimer() return timer end
        function CameraCancelled() return cancelled end
        function CameraPath(...) record("CameraPath", ...); return arrived end
        function AudioMessage(name) record("AudioMessage", name); return name end
        function IsAudioMessageDone(h) assert(h ~= nil); return done[h] == true end
        function StopAudioMessage(h) record("StopAudioMessage", h); done[h] = true end
        function BuildObject(odf, team, path)
            record("BuildObject", odf, team, path)
            return "unit" .. #calls
        end
        function SetScrap(team, value) scrap = value; record("SetScrap", team, value) end
        for _, name in ipairs({"SetPilot", "SetObjectiveName", "StartCockpitTimer",
            "CameraReady", "CameraFinish", "ClearObjectives", "AddObjective",
            "Goto", "Defend2", "HideCockpitTimer", "FailMission", "SucceedMission"}) do
            local key = name
            _G[key] = function(...) record(key, ...) end
        end
    ''')
    lua.execute(SCRIPT)
    g = lua.globals()
    g.Start()
    return lua, g


def calls(g, name):
    return [list(row.values())[1:] for row in g.calls.values() if row[1] == name]


def recycle(g, i):
    h = f"chin_silo{i}"
    g.health[h] = 0
    g.recycled[h] = True


def run():
    lua, g = mission()
    assert g._VERSION == "Lua 5.1"
    g.Update(0.1)
    assert calls(g, "SetScrap") == [[1, 30]]
    assert calls(g, "SetPilot") == [[1, 10]]
    assert calls(g, "StartCockpitTimer") == [[2700, 30, 10]]
    assert len(calls(g, "SetObjectiveName")) == 6
    assert calls(g, "CameraPath") == [["camera_intro", 500, 1500, "chin_silo6"]]
    # Recover all 24 defender builds directly from native source in order.
    section = SOURCE.split("if (!defendersSpawned[0]")[1].split("if (!recycleChecked")[0]
    expected = [[odf, 2, path] for odf, path in re.findall(
        r'BuildObject\("([^"]+)", 2, "([^"]+)"\)', section)]
    assert calls(g, "BuildObject") == expected and len(expected) == 24
    assert [x[1] for x in calls(g, "Defend2")] == [f"chin_silo{i}" for i in range(1, 7) for _ in range(4)]
    lua.execute("calls = {}")
    g.Update(0.1)
    assert not calls(g, "BuildObject") and not calls(g, "SetScrap")
    # Camera needs BOTH path completion and audio; cancellation also completes.
    g.done["bd13001.wav"] = True
    g.Update(0.1)
    assert not g.Save().cameraComplete[1]
    g.arrived = True
    g.Update(0.1)
    assert g.Save().cameraComplete[1]
    assert calls(g, "AddObjective") == [["bd13001.otf", "white"]]
    # Strict < timers and native wave arrays, commands, counts, and spawn paths.
    arrays = re.findall(r'char \*units\[\d+\] = \{(.*?)\};', SOURCE, re.S)
    for deadline, array in zip((180, 600, 900, 1800), arrays):
        lua.execute("calls = {}")
        g.now = deadline
        g.Update(0.1)
        assert not calls(g, "BuildObject")
        g.now = deadline + 0.01
        g.Update(0.1)
        units = re.findall(r'"([^"]+)"', array)
        assert calls(g, "BuildObject") == [[odf, 2, "spawn_attack_waves"] for odf in units]
        assert len(calls(g, "Goto")) == len(units)
        assert all(c[1:] == ["recycler", 1] for c in calls(g, "Goto"))
        lua.execute("calls = {}")
        state = g.Save()
        g.Load(state)
        g.Update(0.1)
        assert not calls(g, "BuildObject") and not calls(g, "StartCockpitTimer")

    lua, g = mission()
    g.distance["chin_silo1"] = 0
    g.cancelled = True
    g.Update(0.1)
    assert not g.Save().defendersSpawned[1]  # Lua numeric truthiness must not leak.
    assert g.Save().cameraComplete[1]
    assert calls(g, "StopAudioMessage") == [["bd13001.wav"]]
    g.distance["chin_silo1"] = 1
    g.Update(0.1)
    assert g.Save().defendersSpawned[1]

    # All four native failure debriefs and the delayed audio-driven transitions.
    for kind, audio, debrief in (
        ("timeout", "bd13005.wav", "bd13lsea.des"),
        ("recycler", "bd13004.wav", "bd13lseb.des"),
        ("silo", None, "bd13lsec.des"),
        ("enemy", None, "bd13lsed.des"),
    ):
        lua, g = mission()
        g.Update(0.1)
        lua.execute("calls = {}")
        g.now = 20
        if kind == "timeout": g.timer = 0
        elif kind == "recycler": g.health["recycler"] = 0
        elif kind == "silo": g.health["chin_silo1"] = 0
        else: g.health["chin_recycler"] = 0.999
        g.Update(0.1)
        assert g.Save().lost and not g.Save().won
        if audio:
            assert not calls(g, "FailMission")
            g.Load(g.Save())
            g.done[audio] = True
            g.Update(0.1)
        assert calls(g, "FailMission") == [[21, debrief]]
        lua.execute("calls = {}")
        g.Update(0.1)
        assert not calls(g, "FailMission")

    lua, g = mission()
    g.Update(0.1)
    lua.execute("calls = {}")
    # Partially recycled state survives Load; dead handles reach the native query.
    recycle(g, 1)
    g.Update(0.1)
    assert g.Save().recycled[1] and not g.Save().silosRecycled
    g.Load(g.Save())
    for i in range(2, 7): recycle(g, i)
    g.Update(0.1)
    assert g.Save().silosRecycled and not g.Save().lost
    assert calls(g, "AudioMessage") == [["bd13002.wav"]]
    assert calls(g, "AddObjective") == [["bd13001.otf", "green"], ["bd13002.otf", "white"]]
    g.timer = 0
    g.health["chin_recycler"] = 0.5
    g.Update(0.1)
    assert not g.Save().lost
    g.health["chin_recycler"] = 0
    g.Update(0.1)
    assert g.Save().won and not calls(g, "SucceedMission")
    g.Load(g.Save())
    g.done["bd13003.wav"] = True
    g.Update(0.1)
    assert calls(g, "SucceedMission") == [[1, "bd13win.des"]]
    lua.execute("calls = {}")
    g.Update(0.1)
    assert not calls(g, "SucceedMission")

    # Source ordering: final silo recycling on the expired-timer frame loses.
    lua, g = mission()
    g.Update(0.1)
    for i in range(1, 7): recycle(g, i)
    g.timer = 0
    g.Update(0.1)
    assert g.Save().lost and not g.Save().silosRecycled
    print("PASS: Lua 5.1, source-derived units, camera, timers, recycling, four failures, victory, save/load")


if __name__ == "__main__":
    run()
