-- Run from repository root: lua5.1 Tools/Test-Misns4.lua
-- Public-callback behavior tests using a strict mock BZR host.
local now, objects, calls, distances, serial, deferred, pending, failSpawn
local checks = 0
local function check(value, why)
    assert(value, why)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, arg)
    local n = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (arg == nil or arg == call[2]) then n = n + 1 end
    end
    return n
end
local function last(name)
    for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end
local function object(odf, team)
    serial = serial + 1
    objects[serial] = {odf = odf, team = team, alive = true}
    return serial
end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function IsOdf(h, odf) assert(IsValid(h)); return objects[h].odf == odf end
function GetPlayerHandle() return 1 end
function GetTime() return now end
function GetDistance(h, path)
    assert(IsAlive(h), "distance on absent/dead object")
    return distances[tostring(h) .. ":" .. path] or 10000
end
function BuildObject(odf, team, path)
    record("BuildObject", odf, team, path)
    if failSpawn == odf then return nil end
    local h = object(odf, team)
    if deferred then pending[#pending + 1] = h else AddObject(h) end
    return h
end
function Goto(h, path, priority)
    assert(IsValid(h)); record("Goto", h, path, priority)
end
function SetObjectiveName(h, name) assert(IsValid(h)); record("SetObjectiveName", h, name) end
function SetObjectiveOn(h) assert(IsValid(h)); record("SetObjectiveOn", h) end
function SetPilot(team, n) record("SetPilot", team, n) end
function AddScrap(team, n) record("AddScrap", team, n) end
function ClearObjectives() record("ClearObjectives") end
function AddObjective(name, color) record("AddObjective", name, color) end
function AudioMessage(name) record("AudioMessage", name) end
function StartCockpitTimer(...) record("StartCockpitTimer", ...) end
function StopCockpitTimer() record("StopCockpitTimer") end
function HideCockpitTimer() record("HideCockpitTimer") end
function SetAIP(name) record("SetAIP", name) end
function FailMission(...) record("FailMission", ...) end
function SucceedMission(...) record("SucceedMission", ...) end
local function near(h, path, d) distances[tostring(h) .. ":" .. path] = d end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function reset(config)
    config = config or {}
    now, serial = 0, 0
    objects, calls, distances, pending = {}, {}, {}, {}
    deferred, failSpawn = config.deferred, config.failSpawn
    object("svtank", 1)
    dofile("Scripts/misns4.lua")
    if config.mapHauler then AddObject(object("svhaul", 1)) end
    Start()
    Update(0.05)
    return Save()
end
local function step(t) now = t; Update(0.05) end
local function spawnAll(m)
    for _ = m.convoy_count + 1, m.convoy_total do step(m.convoy_time + 0.1) end
end

local m = reset()
check(m.start_done and m.convoy_total == 5 and m.convoy_count == 0, "startup state")
check(m.convoy_time == 420 and m.wakeup_time == 30 and m.raider_time == 30 and m.army_time == 100, "source deadlines")
check(m.attack_time == 99999 and not m.first_bridge and m.safe[9] == false, "unused native state retained")
check(count("BuildObject") == 7, "initial artillery/pod/towers/powers/constructor")
check(count("BuildObject", "avartl") == 1 and count("BuildObject", "abtowe") == 2 and count("BuildObject", "ablpow") == 2, "initial hostile composition")
check(last("AddScrap")[2] == 1 and last("AddScrap")[3] == 50, "50 added scrap")
check(count("SetPilot") == 2 and last("SetPilot")[2] == 2 and last("SetPilot")[3] == 30, "pilot setup")
check(last("SetObjectiveName")[2] == m.cam1 and last("SetObjectiveName")[3] == "Bridge", "Bridge pod name")
check(last("AddObjective")[2] == "misns4.otf" and last("AddObjective")[3] == "white", "single objective")
check(count("AudioMessage", "misns401.wav") == 1 and count("AudioMessage", "misns410.wav") == 1, "both briefing lines")
local timer = last("StartCockpitTimer")
check(timer[2] == 420 and timer[3] == 300 and timer[4] == 0, "cockpit thresholds")
step(30); check(count("BuildObject", "avfigh") == 0, "strict wakeup/raider boundary")
step(30.1); Update(0.05)
check(count("BuildObject", "avfigh") == 3 and count("Goto") == 1 and last("Goto")[3] == "wakeup", "one reminder and two raiders once")
check(count("BuildObject", "avltnk") == 0, "cut raider disabled")
step(100); check(count("BuildObject", "avtank") == 0, "strict army boundary")
step(100.1); Update(0.05)
check(count("BuildObject", "avtank") == 2 and count("BuildObject", "avhraz") == 1, "two tanks/one howitzer, cut second disabled")
near(1, "sbridge", 200); Update(0.05); check(not m.north_bridge, "strict bridge radius")
near(1, "sbridge", 199); Update(0.05); Update(0.05)
check(m.north_bridge and not m.bridge_clear, "north spawns before guards cleared")
check(count("BuildObject", "avltnk") == 1 and count("BuildObject", "avturr") == 1 and count("BuildObject", "avscav") == 1 and count("BuildObject", "avrecy") == 1, "north composition")
objects[m.t1].alive = false; objects[m.t2].alive = false; Update(0.05)
check(not m.bridge_clear, "howitzer still blocks bridge clear")
objects[m.b1].alive = false; step(110); Update(0.05)
check(m.bridge_clear and m.counter_time == 260 and count("SetAIP", "misns4.aip") == 1, "bridge clear and 150s counter deadline once")
check(count("AudioMessage", "misns405.wav") == 1, "source annotated wrong audio retained")
near(1, "warn1", 200); Update(0.05); check(not m.warning, "strict warning radius")
near(1, "warn1", 199); Update(0.05); Update(0.05)
check(m.warning and count("AudioMessage", "misns409.wav") == 1, "warning once")
step(261); check(not m.counter, "counter waits for third hauler despite expired timer")
step(420); check(m.convoy_count == 0, "strict convoy boundary")
step(420.1)
check(m.convoy_count == 1 and m.convoy_time == 465.1 and IsAlive(m.convoy_handle[0]), "first hauler zero-based and 45s spacing")
check(count("AudioMessage", "misns402.wav") == 1 and count("StopCockpitTimer") == 1 and count("HideCockpitTimer") == 1, "convoy announcement/timer stop once")
check(last("Goto")[3] == "escort" and last("Goto")[4] == nil, "escort default uncommandable priority")
step(m.convoy_time); check(m.convoy_count == 1, "strict second-hauler boundary")
step(m.convoy_time + 0.1); check(not m.counter and m.convoy_count == 2, "second hauler cannot trigger counter")
step(m.convoy_time + 0.1)
check(m.convoy_count == 3 and m.counter and count("BuildObject", "avrckt") == 4, "third hauler unlocks expired counter")
check(last("Goto")[3] == "sbridge", "counter advances to bridge")
spawnAll(m); Update(0.05)
check(m.convoy_count == 5 and m.convoy_time == 99999 and count("BuildObject", "svhaul") == 5, "five-spawn cap")
check(count("SetObjectiveOn") == 5 and count("BuildObject", "avrckt") == 4, "all haulers marked and counter one-shot")
local saved = copy(Save()); dofile("Scripts/misns4.lua"); Load(saved); m = Save(); Update(0.05)
check(m.convoy_count == 5 and m.counter and m.bridge_clear and count("AddScrap") == 1 and count("BuildObject", "svhaul") == 5, "save/load resumes without replay")
for i = 0, 2 do near(m.convoy_handle[i], "goal", 99) end
near(m.convoy_handle[3], "goal", 100); Update(0.05)
check(m.win_count == 3 and not m.won, "three arrivals insufficient and strict 100m boundary")
near(m.convoy_handle[3], "goal", 99); near(m.convoy_handle[4], "goal", 99); step(700); Update(0.05)
check(m.win_count == 5 and m.won and count("SucceedMission") == 1, "simultaneous fourth/fifth arrivals succeed once")
check(last("SucceedMission")[2] == 710 and last("SucceedMission")[3] == "misns4w1.des", "ten-second victory debrief")
saved = copy(Save()); Load(saved); Update(0.05); check(count("SucceedMission") == 1, "loaded victory not reissued")

m = reset(); spawnAll(m)
objects[m.convoy_handle[0]].alive = false; near(m.convoy_handle[0], "goal", 1); step(650)
check(m.convoy_dead == 1 and not m.lost and m.win_count == 0, "one loss allowed and dead hauler cannot arrive")
objects[m.convoy_handle[1]] = nil; step(651); Update(0.05)
check(m.convoy_dead == 2 and m.lost and count("FailMission") == 1, "second loss fails once, deleted handle counted")
check(last("FailMission")[2] == 666 and last("FailMission")[3] == "misns4l1.des", "15s failure debrief")
objects[m.convoy_handle[2]].alive = false; step(660)
check(m.convoy_dead == 3 and count("FailMission") == 1 and last("FailMission")[2] == 666, "later death cannot postpone defeat")
check(count("AudioMessage", "misns403.wav") == 3, "each loss reports once")
saved = copy(Save()); Load(saved); Update(0.05)
check(count("FailMission") == 1 and count("AudioMessage", "misns403.wav") == 3, "loss save/load retains latches")
m.win_count = 4; Update(0.05); check(not m.won and count("SucceedMission") == 0, "latched loss takes precedence over stale arrival count")

m = reset(); spawnAll(m)
for i = 0, 3 do near(m.convoy_handle[i], "goal", 99) end
Update(0.05); check(m.won and m.win_count == 4, "ordinary four-of-five success")

m = reset(); near(1, "sbridge", 1); step(1)
check(m.bridge_clear and m.counter_time == 151 and count("SetAIP") == 1, "source early bridge-clear behavior preserved")
step(100.1); check(IsAlive(m.t1) and m.bridge_clear, "early clear does not cancel scheduled guards")

m = reset(); step(420.1); step(m.convoy_time + 0.1); step(m.convoy_time + 0.1)
near(m.convoy_handle[1], "warn1", 1); Update(0.05); check(not m.counter, "second hauler near warn1 cannot trigger")
near(m.convoy_handle[2], "warn1", 200); Update(0.05); check(not m.counter, "strict third-hauler distance boundary")
near(m.convoy_handle[2], "warn1", 199); Update(0.05)
check(m.counter and count("BuildObject", "avrckt") == 4, "proximity trigger without bridge clear")

m = reset(); spawnAll(m); objects[m.convoy_handle[2]].alive = false; m.counter_time = 1; Update(0.05)
check(not m.counter, "destroyed third hauler disables both counter triggers as source")

m = reset({deferred = true}); spawnAll(m)
check(m.convoy_count == 5, "deferred callbacks still preserve five-spawn schedule")
local gotos = count("Goto")
for _, h in ipairs(pending) do AddObject(h); AddObject(h) end
check(m.convoy_count == 5 and count("Goto") == gotos, "deferred/duplicate callbacks cannot double count or reissue escort")
AddObject(nil); AddObject(0); AddObject(object("svhaul", 2)); AddObject(object("avtank", 1))
check(m.convoy_count == 5, "invalid/unrelated callbacks ignored")
for _ = 1, 7 do AddObject(object("svhaul", 1)) end
check(m.convoy_count == 10 and m.convoy_handle[10] == nil, "native array bound guarded")

m = reset({mapHauler = true}); check(m.convoy_count == 1, "Start preserves map callback")
spawnAll(m); check(count("BuildObject", "svhaul") == 4 and m.convoy_count == 5, "preplaced hauler counts as source")

m = reset({failSpawn = "svhaul"}); step(420.1)
check(m.convoy_count == 0 and m.convoy_time == 465.1 and count("SetObjectiveOn") == 0, "failed spawn safe and next attempt scheduled")
objects[1] = nil; Update(0.05); check(not m.warning and not m.north_bridge, "missing player cannot trigger proximity")
m = reset({failSpawn = "spcamr"}); check(count("SetObjectiveName") == 0, "missing camera creation guarded")
print("misns4: " .. checks .. " checks passed (" .. _VERSION .. ")")
