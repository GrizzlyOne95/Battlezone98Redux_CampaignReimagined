-- Run from the repository root: lua5.1 Tools/Test-Misn15.lua
-- Mock-host checks of the mission's public callbacks and observable behavior.
local now, objects, labels, calls, distances, serial, scrap, audioDone, cancelled
local objectives, options, randomBranch
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function countCalls(name, arg)
    local count = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (arg == nil or call[2] == arg) then count = count + 1 end
    end
    return count
end
local function lastCall(name)
    for index = #calls, 1, -1 do
        if calls[index][1] == name then return calls[index] end
    end
end
local function object(odf, team)
    serial = serial + 1
    objects[serial] = {odf = odf, team = team, alive = true, command = 0}
    return serial
end
AiCommand = {NONE = 0, GO = 3, ATTACK = 4, STOP = 2}
function GetHandle(label)
    if label == "misn15b" and not options.variant then return nil end
    if options.missing and options.missing[label] then return nil end
    if not labels[label] then labels[label] = object("mapobject", 0) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function IsOdf(h, odf) assert(IsValid(h)); return objects[h].odf == odf end
function GetDistance(from, to)
    assert(IsValid(from) and IsValid(to), "unsafe distance call")
    return distances[tostring(from) .. ":" .. tostring(to)] or 10000
end
function SetObjectiveName(h, name) assert(IsValid(h)); record("SetObjectiveName", h, name) end
function SetUserTarget(h) assert(IsValid(h)); record("SetUserTarget", h) end
function AddScrap(team, amount) assert(team == 1); scrap = scrap + amount; record("AddScrap", team, amount) end
function GetScrap(team) assert(team == 1); return scrap end
function ClearObjectives() objectives = {}; record("ClearObjectives") end
function AddObjective(name, color)
    objectives[name] = color
    local slots = 0
    for _ in pairs(objectives) do slots = slots + 1 end
    assert(slots <= 10, "objective panel overflow")
    record("AddObjective", name, color)
end
function BuildObject(odf, team, where)
    record("BuildObject", odf, team, where)
    if options.failedSpawn == odf then return nil end
    local h = object(odf, team)
    AddObject(h) -- Engine callbacks can occur synchronously inside BuildObject.
    return h
end
function Attack(h, target)
    assert(IsValid(h) and IsValid(target), "unsafe attack")
    objects[h].command = AiCommand.ATTACK
    record("Attack", h, target)
end
function Goto(h, path, priority)
    assert(IsValid(h), "unsafe Goto")
    objects[h].command = AiCommand.GO
    record("Goto", h, path, priority)
end
function GetCurrentCommand(h) assert(IsValid(h)); return objects[h].command end
function AudioMessage(name) record("AudioMessage", name); return "audio:" .. name end
function IsAudioMessageDone(msg) assert(type(msg) == "string"); return audioDone end
function CameraReady() record("CameraReady"); return true end
function CameraObject(base, right, up, forward, target)
    assert(IsValid(base) and IsValid(target), "unsafe camera object")
    record("CameraObject", base, right, up, forward, target)
end
function CameraPath(path, height, speed, target)
    assert(IsValid(target), "unsafe camera path")
    record("CameraPath", path, height, speed, target)
end
function CameraCancelled() return cancelled end
function CameraFinish() record("CameraFinish") end
function FailMission(time, filename) record("FailMission", time, filename) end
function SucceedMission(time, filename) record("SucceedMission", time, filename) end
local originalRandom = math.random
math.random = function(low, high)
    assert(low == 0 and high == 1, "unexpected random range")
    return randomBranch
end
local function reset(config)
    options = config or {}
    now, serial, scrap = 0, 0, options.scrap or 0
    audioDone, cancelled, randomBranch = false, false, 1
    objects, labels, calls, distances, objectives = {}, {}, {}, {}, {}
    dofile("Scripts/misn15.lua")
    if options.mapSilos then
        for _ = 1, options.mapSilos do AddObject(object("absilo", 1)) end
    end
    Start()
    Update(0.05)
    return Save()
end
local function near(from, to, distance)
    distances[tostring(from) .. ":" .. tostring(to)] = distance
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local m = reset({scrap = 7})
check(m.start_done and scrap == 17 and countCalls("AddScrap") == 1, "startup adds ten scrap")
check(not m.misn15b and m.scav_du_jour == m.recy, "base map uses recycler target")
check(m.rendezvous1 == 180 and m.rendezvous2 == 240, "source rendezvous deadlines")
check(m.deny_time1 == 300 and m.deny_time2 == 400, "source denial deadlines")
check(m.second_message == 2 and m.sav_timer == 120 and m.check_time == 5, "initial timers")
check(m.misl_time == 40 and not m.found_group2 and not m.alien3, "unused state retained")
check(countCalls("Goto") == 3, "three Soviet marchers")
for _, call in ipairs(calls) do
    if call[1] == "Goto" then
        check(call[3] == "tank_path" and call[4] == 0, "march remains player-commandable")
    end
end
check(countCalls("SetObjectiveName") == 6, "camera pod names")
check(lastCall("SetUserTarget")[2] == m.cam6, "initial target Nav Beta")
check(countCalls("AudioMessage", "misn1501.wav") == 1 and countCalls("CameraReady") == 0, "opening briefing")
for index = 1, 4 do check(objectives["misn150" .. index .. ".otf"] == "white", "initial white objective") end
audioDone = true; now = 2; Update(0.05)
check(not m.camera1, "second briefing strict time boundary")
audioDone = false; now = 3; Update(0.05)
check(not m.camera1, "second briefing waits for opening audio")
audioDone = true; Update(0.05)
check(m.camera1 and m.camera_time == 11 and m.second_message == 99999, "intro camera starts after audio")
local camera = lastCall("CameraObject")
check(camera[2] == m.tank1 and camera[3] == 800 and camera[4] == 600 and camera[5] == 1200 and camera[6] == m.tank1, "centimeter camera offsets")
local saved = copy(Save()); Load(saved); m = Save()
now = 11; Update(0.05)
check(m.camera1 and countCalls("CameraReady") == 1 and countCalls("AddScrap") == 1, "intro resumes after load without startup replay")
now = 11.1; Update(0.05)
check(not m.camera1 and countCalls("CameraFinish") == 1, "eight-second intro ends once")

m = reset(); audioDone = true; now = 3; Update(0.05); cancelled = true; Update(0.05)
check(not m.camera1 and countCalls("CameraFinish") == 1, "intro cancellation")
m = reset(); audioDone = true; now = 3; Update(0.05); objects[m.tank1] = nil; Update(0.05)
check(not m.camera1 and countCalls("CameraFinish") == 1, "missing intro subject releases camera")

m = reset(); near(m.cam6, m.tank1, 100); Update(0.05)
check(not m.cca_here, "arrival strict distance boundary")
near(m.cam4, m.tank1, 99); Update(0.05); Update(0.05)
check(m.cca_here and countCalls("AudioMessage", "misn1503.wav") == 1, "either arrival pod completes Soviet objective once")
check(objectives["misn1501.otf"] == "green", "arrival objective green")
now = 180; Update(0.05)
check(countCalls("AudioMessage", "misn1511.wav") == 0, "rescue reminder strict boundary")
now = 181; Update(0.05); Update(0.05)
check(countCalls("AudioMessage", "misn1511.wav") == 1 and m.rendezvous1 == 99999, "three-minute reminder once")
check(lastCall("SetUserTarget")[2] == m.cam2, "NW rescue target")
near(m.cam2, m.player, 150); Update(0.05)
check(not m.found_group1, "rescue strict distance boundary")
near(m.cam2, m.player, 149); Update(0.05)
check(m.found_group1 and m.camera2 and m.rcam1 == 184, "first rescue activates")
check(objects[m.scavcam].odf == "avscav" and m.scav_du_jour == m.scavcam and m.found, "spawn callback selects newest scavenger")
check(countCalls("BuildObject", "avscav") == 1 and countCalls("BuildObject", "avapc") == 1 and countCalls("BuildObject", "avturr") == 1, "original rescue composition")
local shot = lastCall("CameraPath")
check(shot[2] == "rescue_cam1" and shot[3] == 1000 and shot[4] == 0 and shot[5] == m.scavcam, "original rescue camera")
saved = copy(Save()); Load(saved); m = Save(); now = 184; Update(0.05)
check(m.camera2 and countCalls("BuildObject", "avscav") == 1, "rescue save/load and strict camera boundary")
now = 184.1; Update(0.05); Update(0.05)
check(not m.camera2 and m.rcam1 == 99999 and countCalls("CameraFinish") == 1, "rescue camera finishes once")
near(m.cam3, m.player, 1); now = 500; Update(0.05)
check(not m.found_group2 and countCalls("BuildObject", "avartl") == 0 and countCalls("AudioMessage", "misn1512.wav") == 0, "second rescue remains cut")
check(countCalls("BuildObject", "waspmsl") == 0, "missile experiment remains cut")
check(countCalls("BuildObject", "hvsat") == 0, "base map has no denial attacks")

m = reset(); near(m.cam2, m.player, 10); Update(0.05); cancelled = true; Update(0.05)
check(m.found_group1 and not m.camera2 and countCalls("BuildObject", "avscav") == 1, "rescue cancel preserves reinforcements")
check(countCalls("CameraFinish") == 1, "rescue cancel releases camera")
m = reset(); near(m.cam2, m.player, 10); Update(0.05); objects[m.scavcam] = nil; Update(0.05)
check(not m.camera2 and m.found_group1, "missing rescue subject releases camera")
m = reset({failedSpawn = "avscav"}); near(m.cam2, m.player, 10); Update(0.05)
check(m.found_group1 and not m.camera2 and countCalls("CameraPath") == 0, "failed subject creation remains safe")

m = reset(); near(m.player, m.tart, 150); Update(0.05)
check(not m.tartarus, "Tartarus strict distance boundary")
near(m.player, m.tart, 149); Update(0.05); Update(0.05)
check(m.tartarus and countCalls("AudioMessage", "misn1513.wav") == 1 and countCalls("AudioMessage", "misn1514.wav") == 1, "both relic warnings once")

m = reset(); now = 120; Update(0.05)
check(m.savcount == 0, "first wave strict boundary")
now = 121; Update(0.05)
check(m.savcount == 1 and IsAlive(m.savlist[0]) and m.sav_timer == 361, "wave at zero-based slot zero")
check(lastCall("BuildObject")[4] == "alien1" and lastCall("Attack")[3] == m.recy, "alien1 wave attacks recycler")
local sav = m.savlist[0]; objects[sav].command = AiCommand.NONE
now = m.check_time; Update(0.05)
check(objects[sav].command == AiCommand.NONE, "scheduler strict five-second boundary")
now = now + 0.1; Update(0.05)
check(objects[sav].command == AiCommand.GO and lastCall("Goto")[3] == "alien_path", "idle wave takes alien path")
objects[sav].command = AiCommand.ATTACK; now = 132; Update(0.05)
check(objects[sav].command == AiCommand.ATTACK, "scheduler preserves existing attack")
objects[sav].alive = false; objects[sav].command = AiCommand.NONE; now = 138; Update(0.05)
check(objects[sav].command == AiCommand.NONE, "scheduler skips dead units")
randomBranch = 0; now = 361; Update(0.05)
check(m.savcount == 1, "repeat wave strict boundary")
now = 362; Update(0.05)
check(m.savcount == 2 and lastCall("BuildObject")[4] == "alien2", "alien2 random branch")
saved = copy(Save()); Load(saved); m = Save(); Update(0.05)
check(m.savcount == 2 and m.savlist[0] == sav and m.sav_timer == 602, "wave save/load preserves zero-based list and timer")
for _ = 3, 50 do now = m.sav_timer + 1; Update(0.05) end
check(m.savcount == 50 and IsAlive(m.savlist[49]), "50-wave cap covers last slot")
now = m.sav_timer + 1; Update(0.05)
check(m.savcount == 50 and countCalls("BuildObject", "hvsav") == 50, "wave cap prevents extra spawn")

m = reset(); AddObject(object("avscav", 2)); AddObject(object("absilo", 2))
check(m.scav_du_jour == m.recy and m.silocount == 0, "enemy additions ignored")
local friendly = object("avscav", 1); AddObject(friendly); now = 121; Update(0.05)
check(lastCall("Attack")[3] == friendly, "new friendly scavenger receives next wave")
objects[friendly] = nil; now = m.sav_timer + 1; Update(0.05)
check(m.scav_du_jour == friendly and m.savcount == 2 and lastCall("Goto")[3] == "alien_path", "missing target is not silently retargeted")

m = reset({variant = true}); now = 300; Update(0.05)
check(m.misn15b and countCalls("BuildObject", "hvsat") == 0, "variant denial strict boundary")
now = 301; Update(0.05)
check(countCalls("BuildObject", "hvsat") == 2 and lastCall("Goto")[3] == "deny1", "first variant pair")
local firstPair = {m.sat1, m.sat2}
saved = copy(Save()); Load(saved); m = Save(); now = 400; Update(0.05)
check(countCalls("BuildObject", "hvsat") == 2, "variant save/load and second strict boundary")
now = 401; Update(0.05); Update(0.05)
check(countCalls("BuildObject", "hvsat") == 4 and lastCall("Goto")[3] == "deny2", "second variant pair once")
check(m.sat1 ~= firstPair[1] and IsAlive(firstPair[1]) and IsAlive(firstPair[2]), "source overwrites handles without removing first pair")

m = reset({mapSilos = 1}); check(m.silocount == 1 and not m.silo_built, "Start preserves map AddObject counts")
local silo = object("absilo", 1); AddObject(silo); Update(0.05)
check(m.silocount == 2 and m.silo_built and objectives["misn1503.otf"] == "green", "second silo completes objective")
objects[silo].alive = false; Update(0.05)
check(m.silocount == 2 and m.silo_built, "silo destruction does not undo source's cumulative objective")
saved = copy(Save()); Load(saved); m = Save(); Update(0.05)
check(m.silocount == 2 and countCalls("AddScrap") == 1, "load preserves silo count without startup")

m = reset(); scrap = 74; Update(0.05)
check(not m.got_dough and countCalls("SucceedMission") == 0, "74 scrap is insufficient")
scrap = 75; now = 20; Update(0.05); Update(0.05)
check(m.got_dough and m.won and countCalls("SucceedMission") == 1, "75 scrap succeeds once without rescue/silo/arrival prerequisites")
check(lastCall("SucceedMission")[2] == 30 and lastCall("SucceedMission")[3] == "misn15w1.des", "source success delay and debrief")
near(m.cam4, m.tank1, 1); Update(0.05)
for index = 1, 4 do check(objectives["misn150" .. index .. ".otf"] == "green", "victory colors survive refresh") end
saved = copy(Save()); Load(saved); Update(0.05)
check(countCalls("SucceedMission") == 1 and countCalls("AudioMessage", "misn1510.wav") == 1, "loaded victory is not reissued")

m = reset(); objects[m.recy].alive = false; scrap = 75; now = 30; Update(0.05); Update(0.05)
check(m.lost and not m.got_dough and countCalls("FailMission") == 1 and countCalls("SucceedMission") == 0, "recycler failure wins simultaneous 75 scrap")
check(lastCall("FailMission")[2] == 40 and lastCall("FailMission")[3] == "misn15l1.des", "source failure delay and debrief")
check(countCalls("AudioMessage", "misn1414.wav") == 1, "original cross-mission failure audio preserved")

m = reset({missing = {apcamr0_camerapod = true, apcamr1_camerapod = true,
    apcamr2_camerapod = true, apcamr3_camerapod = true, apcamr4_camerapod = true,
    apcamr5_camerapod = true, ubtart0_i76building = true, svtank0_wingman = true,
    svtank1_wingman = true, svapc0_apc = true}})
audioDone = true; now = 3; Update(0.05)
check(not m.cca_here and not m.found_group1 and not m.tartarus and not m.camera1, "missing map subjects cannot cause false proximity or invalid camera calls")
check(countCalls("Goto") == 0 and countCalls("SetObjectiveName") == 0, "missing map unit calls guarded")
AddObject(nil); AddObject(0)
check(m.silocount == 0, "invalid AddObject callbacks ignored")

math.random = originalRandom
print("misn15: " .. checks .. " checks passed (" .. _VERSION .. ")")
