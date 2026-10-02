-- Run from repository root with Lua 5.1: lua5.1 Tools/Test-BlackDog07.lua
-- Public-callback behavior tests; no BZR runtime or external modules required.
local now, objects, calls, labels, done, scrap, serial, options, player
local objectives
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, first)
    local n = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (first == nil or call[2] == first) then n = n + 1 end
    end
    return n
end
local function last(name)
    for i = #calls, 1, -1 do
        if calls[i][1] == name then return calls[i] end
    end
end
local function object()
    serial = serial + 1
    objects[serial] = {alive = true, health = 1}
    return serial
end
function GetHandle(label)
    record("GetHandle", label)
    if options.missing and options.missing[label] then return nil end
    if not labels[label] then labels[label] = object() end
    return labels[label]
end
function GetPlayerHandle() return player end
function GetTime() return now end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
function IsAlive(h) assert(IsValid(h), "invalid IsAlive"); return objects[h].alive end
function GetHealth(h) assert(IsValid(h), "invalid health"); return objects[h].health end
function SetObjectiveName(h, name)
    assert(IsValid(h), "invalid name")
    record("SetObjectiveName", h, name)
end
function SetAIP(name) record("SetAIP", name) end
function SetScrap(team, value) scrap[team] = value; record("SetScrap", team, value) end
function GetScrap(team) return scrap[team] end
function SetPilot(team, value) record("SetPilot", team, value) end
function AudioMessage(name)
    record("AudioMessage", name)
    return "message:" .. name
end
function IsAudioMessageDone(msg)
    assert(type(msg) == "string", "invalid audio")
    return done[msg] == true
end
function ClearObjectives() objectives = {}; record("ClearObjectives") end
function AddObjective(name, color)
    objectives[name] = color
    record("AddObjective", name, color)
end
function Goto(h, path, priority)
    assert(IsValid(h), "invalid Goto")
    record("Goto", h, path, priority)
end
function BuildObject(odf, team, path)
    record("BuildObject", odf, team, path)
    if options.failedBuild == odf then return nil end
    local h = object()
    AddObject(h) -- possible synchronous engine callback
    return h
end
function Attack(h, target, priority)
    assert(IsValid(h) and IsValid(target), "invalid attack")
    record("Attack", h, target, priority)
end
function SucceedMission(time, file) record("SucceedMission", time, file) end
function FailMission(time, file) record("FailMission", time, file) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function reset(config)
    options = config or {}
    now, serial = 0, 0
    objects, calls, labels, done, objectives = {}, {}, {}, {}, {}
    scrap = {[1] = 0, [2] = options.scrap or 0}
    player = object()
    if options.noPlayer then player = nil end
    dofile("Scripts/bdmisn07.lua")
    Start()
    Update(0.05)
    return Save()
end
local function tick(time)
    now = time
    Update(0.05)
    return Save()
end
local function kill(h)
    if h then objects[h].alive = false; objects[h].health = 0 end
end
local function killWaves(m)
    for i = 0, 2 do kill(m.waveUnits1[i]) end
    for i = 0, 7 do kill(m.waveUnits2[i]) end
end
local function killBase(m)
    for i = 0, 10 do kill(m.mustDestroy[i]) end
end
local function reload()
    local snapshot = copy(Save())
    local before = #calls
    dofile("Scripts/bdmisn07.lua")
    Load(snapshot)
    check(#calls == before, "load must not perform engine actions")
    return Save()
end

local m = reset()
check(count("SetAIP", "bdmisn07.aip") == 1, "Chinese AIP initialized")
check(scrap[1] == 8 and last("SetPilot")[2] == 1 and last("SetPilot")[3] == 10, "initial resources")
check(m.startDone and m.wavesSpawned and not m.won and not m.lost, "source flags")
check(not m.objective2Complete and not m.objective3Complete, "unused objectives retained")
check(m.sound1Time == 5 and m.sound2Time == 999999.9 and m.sound3Time == 999999.9, "briefing timers")
check(m.waveDelay[0] == 999999.9 and m.waveDelay[1] == 999999.9 and m.annoyTime == 999999.9, "dormant timers")
check(count("GetHandle") == 27 and count("SetObjectiveName") == 2, "all 25 mission units and two beacons resolved")
check(m.mustSave[0] == labels.recycler and m.mustSave[2] == labels.my_hq, "protected array boundaries")
check(m.mustDestroy[10] == labels.chin_hangar and m.waveUnits2[7] == labels.chin_bomber2, "enemy array boundaries")
check(last("SetObjectiveName")[3] == "Chinese Base", "beacon label")
check(count("AddObjective") == 0 and count("Goto") == 0, "no premature objective/path scheduling")
tick(5)
check(count("AudioMessage") == 0, "opening strict boundary")
tick(5.1)
check(count("AudioMessage", "bd07001.wav") == 1 and m.sound1Time == 999999.9, "opening after five seconds")
m = reload()
tick(20)
check(count("AudioMessage", "bd07002.wav") == 0, "wait for actual audio completion")
done[m.sound1] = true; tick(20)
check(m.sound1 == nil and m.sound2Time == 21, "one-second gap after first message")
m = reload(); tick(21)
check(count("AudioMessage", "bd07002.wav") == 0, "second strict boundary after load")
tick(21.1)
check(count("AudioMessage", "bd07002.wav") == 1, "second audio once")
done[m.sound2] = true; tick(22)
check(m.sound2 == nil and m.sound3Time == 24, "two-second third-message gap")
m = reload(); tick(24)
check(count("AudioMessage", "bd07003.wav") == 0, "third strict boundary")
tick(24.1); m = reload()
done[m.sound3] = true; tick(25); tick(26)
check(m.sound3 == nil and objectives["bd07001.otf"] == "white" and count("AddObjective") == 1, "initial objective once after briefing")
check(count("SetScrap", 1) == 1 and count("SetPilot") == 1 and count("SetAIP") == 1, "load/update never replay startup")
tick(600)
check(count("Goto") == 0 and count("BuildObject") == 0, "no invented opening path timing or harassment")

-- All eleven original wave units must be gone; second-wave endpoint matters.
m = reset({scrap = 7})
killWaves(m)
objects[m.waveUnits2[7]].alive = true; objects[m.waveUnits2[7]].health = 1
tick(10)
check(not m.objective1Complete, "last bomber holds first objective")
kill(m.waveUnits2[7]); tick(10)
check(m.objective1Complete and objectives["bd07002.otf"] == "white", "wave elimination advances objective")
check(scrap[2] == 40 and count("AudioMessage", "bd07004.wav") == 1 and m.annoyTime == 11, "wave completion reward and timer")
m = reload(); tick(11)
check(count("BuildObject") == 0, "harassment strict first boundary")
tick(11.1)
check(count("BuildObject", "cvfigh") == 3 and count("BuildObject", "cvltnk") == 2 and count("Attack") == 5, "exact harassment composition")
for _, call in ipairs(calls) do
    if call[1] == "BuildObject" then check(call[3] == 2 and call[4] == "annoy_1", "harassment team/path") end
    if call[1] == "Attack" then check(call[3] == player and call[4] == nil, "current player, default attack priority") end
end
check(m.annoyTime == 311.1, "five-minute recurrence")
m = reload(); local nextTime = m.annoyTime
player = object(); tick(nextTime)
check(count("BuildObject") == 5, "recurrence strict boundary")
tick(nextTime + 0.1)
check(count("BuildObject") == 10 and last("Attack")[3] == player, "repeat wave follows player vehicle change")
check(count("AudioMessage", "bd07004.wav") == 1 and count("SetScrap", 2) == 1, "phase transition/reward stay one-shot")
done["message:" .. "bd07001.wav"] = true
tick(400); tick(401.1)
done["message:" .. "bd07002.wav"] = true
tick(402); tick(404.1)
done["message:" .. "bd07003.wav"] = true; tick(405)
check(objectives["bd07002.otf"] == "white" and objectives["bd07001.otf"] == nil, "late briefing cannot revert earned phase")

m = reset({scrap = 65}); killWaves(m); tick(1)
check(scrap[2] == 65 and count("SetScrap", 2) == 0, "enemy scrap floor never reduces resources")

-- Retain otherwise dormant source branches; arming them via a saved state
-- exercises the original path commands without inventing a startup schedule.
m = reset(); m.waveDelay[0] = 10; tick(10)
check(count("Goto") == 0, "first path strict boundary")
tick(10.1)
check(count("Goto") == 3 and m.waveDelay[1] == 40.1, "first three units and thirty-second gap")
local gap = m.waveDelay[1]
m = reload(); tick(gap)
check(count("Goto") == 3, "second path strict boundary")
tick(gap + 0.1)
check(count("Goto") == 11 and m.waveDelay[0] == 999999.9 and m.waveDelay[1] == 999999.9, "second eight units once")
for i, call in ipairs(calls) do
    if call[1] == "Goto" then
        check(call[4] == 1, "path priority remains uncommandable")
        check(call[3] == "attack_path1" or call[3] == "attack_path2", "source path names")
    end
end
tick(100); check(count("Goto") == 11, "path dispatch not repeated")

-- Defeat requires all three protected health values to reach zero.
m = reset(); kill(m.mustSave[0]); kill(m.mustSave[1]); tick(5)
check(not m.lost and count("FailMission") == 0, "any one protected building suffices")
objects[m.mustSave[2]].alive = false; tick(5)
check(not m.lost, "health-based loss is distinct from IsAlive/pilot")
kill(m.mustSave[2]); tick(6)
check(m.lost and last("FailMission")[2] == 7 and last("FailMission")[3] == "bd07lose.des", "failure descriptor and one-second delay")
killBase(m); m = reload(); tick(7)
check(count("FailMission") == 1 and count("SucceedMission") == 0, "latched defeat cannot become victory")

-- Victory uses exactly eleven structures, independent of wave completion.
m = reset(); killBase(m)
objects[m.mustDestroy[10]].alive = true; tick(10)
check(not m.won, "last hangar holds victory")
kill(m.mustDestroy[10]); tick(10)
check(m.won and not m.objective1Complete, "base victory does not require wave objective")
check(last("SucceedMission")[2] == 11 and last("SucceedMission")[3] == "bd07win.des", "success descriptor and one-second delay")
check(objectives["bd07002.otf"] == "green", "victory objective")
killWaves(m); tick(10.1)
check(m.objective1Complete and objectives["bd07002.otf"] == "green", "late wave completion keeps victory green")
check(count("AudioMessage", "bd07004.wav") == 1 and m.annoyTime == 11.1, "post-victory source flow retained")
m = reload(); tick(11.2)
check(count("SucceedMission") == 1 and count("BuildObject") == 5, "outcome latches while source harassment still runs")
done["message:" .. "bd07001.wav"] = true; tick(12); tick(13.1)
done["message:" .. "bd07002.wav"] = true; tick(14); tick(16.1)
done["message:" .. "bd07003.wav"] = true; tick(17)
check(objectives["bd07002.otf"] == "green", "late briefing keeps victory green")

m = reset(); killBase(m)
for i = 0, 2 do kill(m.mustSave[i]) end
tick(1)
check(m.won and not m.lost and count("SucceedMission") == 1 and count("FailMission") == 0, "simultaneous result preserves victory precedence")

-- Nil holes must not truncate zero-based arrays; deleted objects must not be
-- passed to mutating/health APIs. A malformed map must not crash the port.
m = reset({missing = {recycler = true, nav_mybase = true, chin_scout1 = true}})
check(count("SetObjectiveName") == 1 and not m.lost and not m.objective1Complete, "missing objects preserve remaining fixed slots")
m.waveDelay[0] = 1; tick(2)
check(count("Goto") == 2, "missing first slot does not truncate path commands")
objects[m.mustSave[1]] = nil; objects[m.mustSave[2]] = nil; tick(3)
check(m.lost and count("FailMission") == 1, "deleted/missing protected objects safely fail")
m = reset({failedBuild = "cvfigh"}); killWaves(m); tick(1); tick(2.1)
check(count("BuildObject") == 5 and count("Attack") == 2, "failed fighter spawns safely skip attack only")
m = reset({noPlayer = true}); killWaves(m); tick(1); tick(2.1)
check(count("BuildObject") == 5 and count("Attack") == 0, "absent player preserves spawn cadence")
print("BlackDog07: " .. checks .. " behavior checks passed (" .. _VERSION .. ").")
