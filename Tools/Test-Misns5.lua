-- Run from repository root: lua5.1 Tools/Test-Misns5.lua
local now, objects, labels, calls, serial, done, cancelled, random, distance, failed
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function record(name, ...) calls[#calls + 1] = {name, ...} end
local function count(name, arg)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end
    end
    return n
end
local function last(name)
    for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end
local function object(odf, team)
    serial = serial + 1; objects[serial] = {odf = odf, team = team, alive = true}; return serial
end
function GetHandle(label)
    if not labels[label] then labels[label] = object("map", 1) end
    return labels[label]
end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function IsOdf(h, odf) assert(IsValid(h)); return objects[h].odf == odf end
function GetTime() return now end
function GetDistance(h, target) assert(IsValid(h) and IsValid(target)); return distance end
function BuildObject(odf, team, where)
    record("BuildObject", odf, team, where)
    if failed == odf then return nil end
    local h = object(odf, team); AddObject(h); return h
end
for _, name in ipairs({"Goto", "Attack", "Defend2"}) do
    local command = name
    _G[command] = function(h, target)
        assert(IsValid(h) and IsValid(target), "invalid command handles")
        record(command, h, target)
    end
end
function SetAIControl(team, enabled) record("SetAIControl", team, enabled) end
function SetAIP(name) record("SetAIP", name) end
function AddScrap(team, amount) record("AddScrap", team, amount) end
function SetPilot(team, amount) record("SetPilot", team, amount) end
function AudioMessage(name) serial = serial + 1; record("AudioMessage", name); return serial end
function IsAudioMessageDone(aud) return done[aud] or false end
function StopAudioMessage(aud) record("StopAudioMessage", aud) end
function CameraReady() record("CameraReady") end
function CameraPath(path, height, speed, target)
    assert(IsValid(target)); record("CameraPath", path, height, speed, target)
end
function CameraCancelled() return cancelled end
function CameraFinish() record("CameraFinish") end
function ClearObjectives() record("ClearObjectives") end
function AddObjective(name, color) record("AddObjective", name, color) end
function SetObjectiveOn(h) assert(IsValid(h)); record("SetObjectiveOn", h) end
function SucceedMission(time, des) record("SucceedMission", time, des) end
function FailMission(time, des) record("FailMission", time, des) end
local nativeRandom = math.random
math.random = function(low, high) assert(low == 0 and high == 3); return random end
local function copy(t)
    local result = {}; for k, v in pairs(t) do result[k] = v end; return result
end
local function reset(preWalker)
    now, serial, cancelled, random, distance, failed = 0, 0, false, 0, 10000, nil
    objects, labels, calls, done = {}, {}, {}, {}
    dofile("Scripts/misns5.lua")
    if preWalker then AddObject(object("avwalk", 2)) end
    Start(); Update(0.05); return Save()
end
local function tick(time) now = time; Update(0.05); return Save() end
local function finishIntro(time)
    cancelled = true; tick(time); cancelled = false; return Save()
end

local m = reset()
check(m.camera1 and m.start_done and m.camera_time == 17 and m.apc_wave == 70, "startup deadlines")
check(count("BuildObject", "avartl") == 2 and count("CameraReady") == 1, "two artillery and opening shot")
check(last("AddScrap")[2] == 1 and last("AddScrap")[3] == 10, "ten starting scrap")
check(last("SetAIControl")[2] == 2 and last("SetAIControl")[3], "startup strategic AI")
check(last("CameraPath")[3] == 5000 and last("CameraPath")[4] == 2500, "source camera units")
tick(18); check(m.camera1, "17-second timer does not end audio-driven intro")
done[m.aud] = true; tick(19)
check(m.second_message and m.camera1 and last("AudioMessage")[2] == "misns503.wav", "second audio waits before ending intro")
done[m.aud] = true; tick(20)
check(not m.camera1 and not m.third_message and m.chaff == 200 and m.add_defender == 30, "intro exit deadlines and disabled third message")
check(count("Goto") == 2 and count("Attack") == 2 and count("CameraFinish") == 1, "deploy producers and artillery orders")
check(last("AddObjective")[2] == "misns501.otf" and last("AddObjective")[3] == "white", "opening objective")
tick(30); check(not m.defender, "defender strict boundary")
tick(30.1); check(m.defender and IsAlive(m.commander) and m.add_defender == 99999, "commander spawn once")
check(count("BuildObject", "avwalk") == 1 and count("BuildObject", "avtank") == 0 and last("SetPilot")[3] == 30, "pilot reserve and cut tank stays disabled")
objects[m.t1].alive = false; objects[m.t2].alive = false; tick(31)
check(m.third_attack and m.fourth_attack and count("Attack") == 4, "artillery redirect to third plant and depot")
check(last("Attack")[2] == m.a2 and last("Attack")[3] == m.t4, "second artillery target")
objects[m.a1].alive = false; tick(32); check(not m.art_dead, "both artillery must die")
objects[m.a2].alive = false; tick(33); tick(34)
check(m.art_dead and count("AudioMessage", "misns504.wav") == 1, "artillery message once")
tick(70); check(m.h1 == nil, "APC strict boundary")
tick(70.1)
check(IsAlive(m.h1) and IsAlive(m.h2) and IsAlive(m.killme), "two APCs and enemy recycler")
check(count("Defend2") == 2 and last("Defend2")[3] == m.killme, "two recycler guards use Lua target overload")
check(last("Attack")[2] == m.h2 and last("Attack")[3] == m.muf, "APCs attack factory")
distance = 100; tick(71); check(not m.apc_here, "APC distance strict boundary")
distance = 99; tick(72); tick(73)
check(m.apc_here and count("AudioMessage", "misns505.wav") == 1, "APC arrival once")
distance = 10000
objects[m.commander].alive = false; tick(80)
check(m.com_dead and m.wave == 200, "commander death starts 120-second delay")
tick(200); check(m.wave_count == 0 and count("BuildObject", "avfigh") == 0, "wave and chaff strict boundaries")
random = 3; tick(200.1)
check(m.wave_count == 1 and m.wave == 380.1 and m.chaff == 280.1, "first wave and 80-second chaff gap")
check(count("BuildObject", "bvhraz") == 3 and count("BuildObject", "bvltnk") == 0, "first wave consists of three razors")
check(count("Goto") == 6, "fighter and all three razors route to player recycler")
local commander = m.commander; AddObject(object("avwalk", 2))
check(m.commander == commander, "later walker cannot replace original commander")
local saved = copy(Save()); dofile("Scripts/misns5.lua"); Load(saved); m = Save()
check(m.commander == commander and m.wave_count == 1 and m.wave == 380.1, "reload restores handles and wave schedule")
tick(380.2)
check(m.wave_count == 2 and count("BuildObject", "bvltnk") == 3 and not m.last_phase, "second wave has three light tanks")
tick(560.3)
check(m.wave_count == 3 and m.last_phase and count("BuildObject", "bvltnk") == 6, "third wave unlocks final phase")
check(count("BuildObject", "avrecy") == 1 and count("BuildObject", "avscav") == 2 and count("BuildObject", "spcamr") == 1, "reuse recycler and build two scavs and intelligence pod")
check(count("SetAIP", "misns5.aip") == 1 and last("SetObjectiveOn")[2] == m.killme, "AIP and source recycler marker")
check(last("AddObjective")[2] == "misns502.otf" and count("AudioMessage", "misns506.wav") == 1, "final intelligence briefing")
objects[m.killme].alive = false; tick(561); tick(562)
check(m.won and not m.lost and count("SucceedMission") == 1, "victory once")
check(last("SucceedMission")[2] == 571 and last("SucceedMission")[3] == "misns5w1.des", "source success delay and description")
objects[m.recy].alive = false; tick(563); check(count("FailMission") == 0, "won suppresses subsequent loss")
check(count("CameraReady") == 1 and count("AddScrap") == 1 and count("SetAIControl") == 1, "load does not replay startup")
tick(740.4)
check(m.wave_count == 4 and count("BuildObject", "bvltnk") == 9, "source waves continue beyond third even during outcome delay")
check(count("SetAIP") == 1 and count("BuildObject", "spcamr") == 1, "final phase activates exactly once")

m = reset(); finishIntro(0); objects[m.recy].alive = false; tick(1); tick(2)
check(m.lost and not m.won and count("FailMission") == 1, "recycler loss once")
check(last("FailMission")[2] == 11 and last("FailMission")[3] == "misns5l1.des", "source failure delay and description")
m.last_phase = true; tick(3); check(count("SucceedMission") == 0, "loss suppresses victory")

m = reset(); finishIntro(0); tick(71); objects[m.killme].alive = false; tick(72)
check(not m.won and count("SucceedMission") == 0, "early enemy recycler destruction waits for final phase")
m.last_phase = true; objects[m.recy].alive = false; tick(73)
check(m.won and not m.lost and count("SucceedMission") == 1 and count("FailMission") == 0, "source victory-before-loss order for simultaneous destruction")

m = reset(true); commander = m.commander; Start()
check(m.commander == commander, "Start preserves map-discovered commander")
finishIntro(0); tick(11); check(m.commander == commander, "spawned defender does not replace map commander")
AddObject(object("avwalk", 1)); check(m.commander == commander, "player walker ignored")
local routed = count("Goto"); AddObject(object("bvtank", 2)); AddObject(object("avfigh", 1))
check(count("Goto") == routed, "guard tank and player fighter are not routed")

for branch = 0, 3 do
    m = reset(); finishIntro(0); random = branch; tick(181)
    check(m.chaff == 181 + 50 + branch * 10, "all discrete chaff gaps")
end
m = reset(); local intro = copy(Save()); dofile("Scripts/misns5.lua"); Load(intro); m = tick(1)
check(m.camera1 and count("CameraReady") == 1 and count("BuildObject", "avartl") == 2, "mid-intro load resumes without rebuild")
finishIntro(1); check(m.chaff == 181 and m.add_defender == 11, "cancel releases intro at current simulation time")

m = reset(); finishIntro(0); failed = "avwalk"; tick(11)
check(m.defender and m.com_dead and m.wave == 131, "failed commander retains native death-trigger flow")
failed = "avapc"; tick(71); check(m.h1 == nil and m.h2 == nil, "failed APC spawn skips invalid attack")
objects[m.muf] = nil; tick(72); check(not m.apc_here, "missing factory cannot announce APC arrival")
math.random = nativeRandom
print("misns5 mock-host checks passed: " .. checks)
