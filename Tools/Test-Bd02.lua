-- Run from the repository root: lua5.1 Tools/Test-Bd02.lua
-- Strict mock host: transition/timing regression checks, not in-game qualification.
local now, objects, labels, calls, distances, serial, done, cancelled, arrived, objectives
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function record(name, ...) calls[#calls + 1] = {name, ...} end
local function count(name, arg)
    local result = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then result = result + 1 end
    end
    return result
end
local function last(name)
    for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end
local function object()
    serial = serial + 1
    objects[serial] = {alive = true, current = 100, maximum = 100, command = 0}
    return serial
end
AiCommand = {NONE = 0, GO = 3, ATTACK = 4, STOP = 2}
function GetTime() return now end
function GetHandle(label) return labels[label] end
function GetPlayerHandle() return labels.player end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) assert(IsValid(h), "invalid IsAlive"); return objects[h].alive end
function SetScrap(team, amount) record("SetScrap", team, amount) end
function SetPilot(team, amount) record("SetPilot", team, amount) end
function SetCloaked(h) assert(IsValid(h)); record("SetCloaked", h) end
function SetObjectiveName(h, name) assert(IsValid(h)); record("SetObjectiveName", h, name) end
function ClearObjectives() objectives = {}; record("ClearObjectives") end
function AddObjective(name, color)
    objectives[name] = color
    local n = 0
    for _ in pairs(objectives) do n = n + 1 end
    assert(n <= 10, "objective overflow")
    record("AddObjective", name, color)
end
function BuildObject(odf, team, path)
    local h = object()
    record("BuildObject", odf, team, path, h)
    AddObject(h) -- reentrant engine callback
    return h
end
function Goto(h, target) assert(IsValid(h)); objects[h].command = AiCommand.GO; record("Goto", h, target) end
function Attack(h, target)
    assert(IsValid(h) and IsValid(target)); objects[h].command = AiCommand.ATTACK
    record("Attack", h, target)
end
function Stop(h) assert(IsValid(h)); objects[h].command = AiCommand.STOP; record("Stop", h) end
function RemoveObject(h) assert(IsValid(h)); objects[h] = nil; record("RemoveObject", h) end
function GetCurrentCommand(h) assert(IsValid(h)); return objects[h].command end
function GetDistance(h, path) assert(IsValid(h)); return distances[h .. ":" .. path] or 10000 end
function GetCurHealth(h) assert(IsValid(h)); return objects[h].current end
function GetMaxHealth(h) assert(IsValid(h)); return objects[h].maximum end
function GetHealth(h) assert(IsValid(h)); return objects[h].current / objects[h].maximum end
function AddHealth(h, amount) assert(IsValid(h)); objects[h].current = objects[h].current + amount; record("AddHealth", h, amount) end
function AudioMessage(name) local msg = {audio = name}; record("AudioMessage", name); return msg end
function IsAudioMessageDone(msg) assert(type(msg) == "table" and msg.audio, "invalid audio handle"); return done end
function CameraReady() record("CameraReady"); return true end
function CameraPath(path, height, speed, target)
    assert(IsValid(target), "invalid camera target"); record("CameraPath", path, height, speed, target); return arrived
end
function CameraPathDir(path, height, speed) record("CameraPathDir", path, height, speed); return arrived end
function CameraCancelled() return cancelled end
function CameraFinish() record("CameraFinish"); return true end
function FailMission(time, filename) record("FailMission", time, filename) end
function SucceedMission(time, filename) record("SucceedMission", time, filename) end
local function reset(deadPlayer, missingTurrets)
    now, serial, done, cancelled, arrived = 0, 0, false, false, false
    objects, labels, calls, distances, objectives = {}, {}, {}, {}, {}
    labels.player, labels.recycler = object(), object()
    if not missingTurrets then
        for i = 1, 4 do labels["enemy_turret" .. i] = object() end
    end
    objects[labels.player].alive = not deadPlayer
    dofile("Scripts/bd02.lua")
    Start()
    Update(0.05)
    return Save()
end
local function step(time) now = time; Update(0.05) end
local function copy(v)
    if type(v) ~= "table" then return v end
    local result = {}
    for k, item in pairs(v) do result[k] = copy(item) end
    return result
end
local function reload()
    local snapshot, n = copy(Save()), #calls
    dofile("Scripts/bd02.lua")
    Load(snapshot)
    check(#calls == n, "Load must not issue engine commands")
    return Save()
end

-- Complete trajectory, with exact boundaries and save/load across cinematics.
local m = reset()
check(m.missionState == 1 and m.stateTimer == 2, "startup state and timer")
check(last("SetScrap")[3] == 20 and last("SetPilot")[3] == 10, "starting resources")
check(count("SetCloaked") == 4 and objectives["bd02001.otf"] == "white", "cloaked turrets and first objective")
AddObject(object())
check(m.missionState == 1, "disabled factory callback remains inactive")
step(2)
check(count("AudioMessage") == 0, "strict startup timer boundary")
step(2.1)
check(m.missionState == 2 and m.stateTimer == 0, "first narration")
step(3)
check(m.missionState == 2, "wait for narration")
done = true; step(4)
check(m.missionState == 3 and m.stateTimer == 24, "wave one twenty-second delay")
done = false; step(24)
check(count("BuildObject") == 0, "strict wave one boundary")
step(24.1)
check(m.missionState == 4 and count("BuildObject") == 3 and count("Goto") == 3, "first wave composition and paths")
check(count("CameraPath", "camera_decloak") == 1, "wave one cinematic falls through same frame")
check(last("CameraPath")[3] == 2000 and last("CameraPath")[4] == 1000, "decloak camera parameters")
m = reload()
cancelled = true; step(25)
check(m.missionState == 5 and m.stateTimer == 30, "camera cancellation retains five-second objective delay")
cancelled = false; step(30)
check(m.missionState == 5, "strict objective delay boundary")
step(30.1)
check(m.missionState == 6 and objectives["bd02001.otf"] == "green" and objectives["bd02002.otf"] == "white", "source objective advance precedes wave death")
objects[m.wave1_scout1] = nil; objects[m.wave1_scout2] = nil
step(31)
check(m.missionState == 6, "first tank must also die")
objects[m.wave1_tank1] = nil; step(32)
check(m.missionState == 7 and m.stateTimer == 52, "second wave twenty-second delay")
step(52); check(count("BuildObject") == 3, "strict second wave boundary")
step(52.1)
check(m.missionState == 8 and count("BuildObject") == 7, "second wave four scouts")
objects[m.wave2_scout1] = nil; objects[m.wave2_scout2] = nil; objects[m.wave2_scout3] = nil
step(53); check(m.missionState == 8, "all four scouts required")
objects[m.wave2_scout4] = nil; step(54)
check(m.missionState == 9 and m.stateTimer == 64, "massive attack ten-second delay")
step(64); check(count("BuildObject") == 7, "strict massive attack boundary")
step(64.1)
check(m.missionState == 10 and count("BuildObject") == 15, "massive wave eight vehicles")
check(count("CameraPath", "camera_massive_attack") == 1, "massive attack cinematic falls through same frame")
check(last("CameraPath")[3] == 2000 and last("CameraPath")[4] == 10, "massive attack camera parameters")
check(objectives["bd02002.otf"] == "green", "second objective completion")
m = reload(); done = true; step(65)
check(m.missionState == 11 and count("AudioMessage", "bd02005.wav") == 1, "next narration without unintended fall-through")
check(count("RemoveObject") == 0, "massive wave persists until fifth narration completes")
done = false; step(66); check(m.missionState == 11, "fifth narration blocks retreat")
done = true; step(67)
check(m.missionState == 13 and m.stateTimer == 71 and not m.recyclerRetreated, "retreat state and preserved unused timer")
check(count("RemoveObject") == 8 and count("BuildObject") == 18, "massive-wave cleanup, nav and harassment spawns")
check(last("SetObjectiveName")[3] == "Nav Alpha" and objectives["bd02003.otf"] == "white", "nav and retreat objective")
check(count("Goto", m.recycler) == 1 and count("Attack") == 0, "retreat and harassment retain Goto behavior")
distances[m.recycler .. ":trigger_1"] = 100; step(68)
check(not m.recyclerRetreated, "ambush radius is strictly below 100")
distances[m.recycler .. ":trigger_1"] = 99; step(69)
check(m.recyclerRetreated and count("BuildObject") == 24 and count("Attack") == 6, "six-fighter ambush")
m = reload(); step(70)
check(count("BuildObject") == 24, "ambush latch survives reload")
objects[m.recycler].command = AiCommand.NONE; done = false; step(70.1)
check(m.missionState == 14 and count("AudioMessage", "bd02006.wav") == 1, "idle recycler starts bomber warning before unused timer")
step(70.2); check(count("BuildObject") == 24, "bomber warning blocks spawn")
done = true; step(71)
check(m.missionState == 15 and m.soundhandle == nil and count("BuildObject") == 26, "two bombers and cleared audio sentinel")
check(count("RemoveObject") == 14 and count("Attack") == 8, "turret/harassment cleanup and bomber attacks")
objects[m.bomber1_scripted].current = 25; objects[m.bomber2_scripted].current = 50
done = false; step(72)
check(objects[m.bomber1_scripted].current == 100 and objects[m.bomber2_scripted].current == 100, "both bombers topped up")
distances[m.bomber2_scripted .. ":camera_bomber_chasecam"] = 50; step(73)
check(m.missionState == 16, "either bomber triggers final camera at inclusive fifty meters")
step(74)
check(m.missionState == 16 and count("AudioMessage", "bd02009.wav") == 0, "ending cannot bypass living recycler")
objects[m.recycler].current = 90; step(75)
check(m.recyclerHealth == 0 and count("AudioMessage", "bd02008.wav") == 1, "first recycler hit narration")
step(76); check(count("AudioMessage", "bd02008.wav") == 1, "hit narration one-shot")
objects[m.recycler] = nil; objects[labels.player] = nil; step(77)
check(m.missionState == 16 and count("AudioMessage", "bd02009.wav") == 1 and count("FailMission") == 0, "scripted ending permits recycler/player death")
check(count("CameraPathDir") == 1, "destroyed recycler camera fallback")
m = reload(); step(78)
check(m.missionState == 16 and count("AudioMessage", "bd02009.wav") == 1, "saved ending waits and does not repeat narration")
done = true; step(79)
check(m.missionState == 17 and m.stateTimer == 82, "final narration starts three-second hold")
step(82); check(count("SucceedMission") == 0, "strict end-hold boundary")
step(82.1)
check(m.missionState == 18 and last("SucceedMission")[2] == 87.1 and last("SucceedMission")[3] == "bd02win.des", "original victory delay and debrief")
step(83); check(count("SucceedMission") == 1, "victory one-shot")

-- Failure grace period, player replacement, failure precedence and missing objects.
m = reset(true)
check(m.deadTimer == 2, "initially dead player gets intended two-second grace")
step(2); check(count("FailMission") == 0, "strict death-grace boundary")
step(2.1)
check(m.lost and last("FailMission")[2] == 4.1 and last("FailMission")[3] == "bd02lose.des", "player-death debrief and delay")
step(5); check(count("FailMission") == 1 and count("AudioMessage") == 0, "lost mission freezes")
m = reset(); objects[labels.player].alive = false; step(1)
check(m.deadTimer == 3, "later player death arms grace")
labels.player = object(); step(2)
check(m.user == labels.player and m.deadTimer == 0, "player handle refresh and recovery reset grace")
m.missionState = 15; m.bomber1_scripted = object()
distances[m.bomber1_scripted .. ":camera_bomber_chasecam"] = 0
objects[m.recycler] = nil; step(3)
check(m.lost and m.missionState == 15 and last("FailMission")[3] == "bd02lsea.des", "recycler loss takes precedence over cinematic entry")
check(count("CameraReady") == 0, "defeat does not enter ending")
m = reset(); m.missionState = 4; objects[m.recycler] = nil; step(1)
check(count("CameraFinish") == 1 and m.lost, "pre-ending defeat releases cinematic")
m = reset(false, true)
check(count("SetCloaked") == 0, "missing turrets are safe")
m.missionState = 4; m.wave1_scout1 = object(); objects[m.wave1_scout1] = nil; step(1)
check(m.missionState == 5 and m.stateTimer == 6, "missing decloak subject releases view with original delay")
m.missionState = 15; m.bomber1_scripted = object(); m.bomber2_scripted = object()
objects[m.bomber1_scripted] = nil; objects[m.bomber2_scripted] = nil; step(2)
check(m.missionState == 15, "missing bombers neither crash nor satisfy distance gate")
check(count("AddHealth") == 0, "missing bombers are not resurrected")
print("bd02 Lua 5.1 mock-host checks: " .. checks .. " passed")
