-- Run from repository root: lua5.1 Tools/Test-BlackDog01.lua
-- Mock-host regression checks; engine visuals/audio/ODF behavior need in-game QA.
local now, objects, labels, calls, distances, done, cancelled, cameraArrived, nearest
local serial, objectives, missing, failedSpawn
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function record(name, ...) calls[#calls + 1] = {name, ...} end
local function count(name, arg)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end end
    return n
end
local function last(name)
    for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end
local function object(odf, team)
    serial = serial + 1
    objects[serial] = {odf = odf, team = team, health = 1, alive = true, deployed = false, cloaked = false}
    return serial
end
function GetHandle(label)
    if missing[label] then return nil end
    if not labels[label] then labels[label] = object(label, 1) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetHealth(h) assert(IsValid(h)); return objects[h].health end
function IsDeployed(h) assert(IsValid(h)); return objects[h].deployed end
function IsCloaked(h) assert(IsValid(h)); return objects[h].cloaked end
function GetDistance(h, where)
    assert(IsValid(h) and (type(where) == "string" or IsValid(where)), "unsafe distance")
    return distances[tostring(h) .. ":" .. tostring(where)] or 10000
end
function GetNearestUnitOnTeam(path, point, team)
    assert(path == "spawn_nav_beacon" and point == 0 and team == 1, "nearest overload")
    return nearest
end
function SetScrap(team, value) record("SetScrap", team, value) end
function SetPilot(team, value) record("SetPilot", team, value) end
function Goto(h, path, priority) assert(IsValid(h)); record("Goto", h, path, priority) end
function BuildObject(odf, team, path)
    record("BuildObject", odf, team, path)
    if failedSpawn == odf then return nil end
    local h = object(odf, team)
    AddObject(h) -- synchronous engine callback must not change the mission gate
    return h
end
function SetPilotClass(h, odf) assert(IsValid(h) and odf == ""); record("SetPilotClass", h, odf) end
function Patrol(h, path, priority) assert(IsValid(h)); record("Patrol", h, path, priority) end
function Cloak(h) assert(IsValid(h)); objects[h].cloaked = true; record("Cloak", h) end
function SetCloaked(h) assert(IsValid(h)); objects[h].cloaked = true; record("SetCloaked", h) end
function Decloak(h) assert(IsValid(h)); objects[h].cloaked = false; record("Decloak", h) end
function Attack(h, target, priority)
    assert(IsValid(h) and IsValid(target)); record("Attack", h, target, priority)
end
function Retreat(h, path, priority) assert(IsValid(h)); record("Retreat", h, path, priority) end
function SetObjectiveName(h, name) assert(IsValid(h)); record("SetObjectiveName", h, name) end
function SetUserTarget(h) assert(IsValid(h)); record("SetUserTarget", h) end
function ClearObjectives() objectives = {}; record("ClearObjectives") end
function AddObjective(name, color)
    objectives[name] = color
    local n = 0; for _ in pairs(objectives) do n = n + 1 end
    assert(n <= 3, "unexpected objectives")
    record("AddObjective", name, color)
end
function AudioMessage(name)
    local h = "audio:" .. name
    record("AudioMessage", name)
    return h
end
function IsAudioMessageDone(h) assert(type(h) == "string"); return done[h] or false end
function StopAudioMessage(h) assert(type(h) == "string"); record("StopAudioMessage", h) end
function CameraReady() record("CameraReady"); return true end
function CameraPath(path, height, speed, target)
    assert(IsValid(target), "unsafe camera target")
    record("CameraPath", path, height, speed, target)
    return cameraArrived
end
function CameraCancelled() return cancelled end
function CameraFinish() record("CameraFinish"); return true end
function FailMission(time, description) record("FailMission", time, description) end
function SucceedMission(time, description) record("SucceedMission", time, description) end
local function copy(x)
    if type(x) ~= "table" then return x end
    local y = {}; for k, v in pairs(x) do y[k] = copy(v) end; return y
end
local function tick(time) now = time; Update(0.05); return Save() end
local function finish(name) done["audio:" .. name] = true end
local function near(h, where, distance) distances[tostring(h) .. ":" .. tostring(where)] = distance end
local function reset(config)
    config = config or {}
    now, serial = 0, 0
    objects, labels, calls, distances, done, objectives = {}, {}, {}, {}, {}, {}
    missing, failedSpawn = config.missing or {}, config.failedSpawn
    cancelled, cameraArrived, nearest = false, false, nil
    dofile("Scripts/bd01.lua")
    Start()
    return tick(0)
end
local function navPhase()
    local m = reset()
    cameraArrived = true
    tick(1)
    objects[m.recycler].deployed = true
    tick(2)
    tick(22)
    finish("BD01002.WAV")
    tick(23)
    return m
end
local function wavePhase(which)
    local m = navPhase()
    objects[m[which or "badGuy1_ambush"]].alive = false
    tick(24)
    tick(29)
    return m
end

local m = reset()
check(count("SetScrap") == 1 and last("SetScrap")[3] == 12, "starting scrap")
check(last("SetPilot")[2] == 1 and last("SetPilot")[3] == 10, "starting pilots")
check(count("Goto") == 3 and last("Goto")[4] == 0, "startup movement commandable")
check(count("AudioMessage", "bd01001.wav") == 1, "opening sound once")
check(objectives["bd01001.otf"] == "white" and not objectives["bd01002.otf"], "initial objective gate")
check(last("CameraPath")[2] == "camera_start_arc" and last("CameraPath")[3] == 3000
    and last("CameraPath")[4] == 3500, "opening camera parameters")
for i = 0, 3 do check(m.soundStarted[i] == false and m.soundPlayed[i] == false, "sound slots initialized") end
check(m.soundStarted[4] == nil and m.delayTime3 == 999999 and m.scavengers[0] == nil, "unused state retained without overflow")
AddObject(object("avscav", 1))
tick(1)
check(not m.scavengersCreated and count("BuildObject") == 0, "building scavenger does not bypass deployment")
cancelled = true; tick(5); cancelled = false
check(m.cameraComplete[0] and m.sound8Time == 95 and count("StopAudioMessage", "audio:" .. "bd01001.wav") == 1, "opening cancel anchors 90 seconds")
tick(95); check(count("AudioMessage", "bd01008.wav") == 0, "deployment reminder strict boundary")
tick(95.1); check(count("AudioMessage", "bd01008.wav") == 1, "first deployment reminder")
finish("bd01008.wav"); tick(96)
check(m.sound9Time == 126, "second reminder follows completed first audio")
tick(126); check(count("AudioMessage", "bd01009.wav") == 0, "second reminder strict boundary")
tick(126.1); finish("bd01009.wav"); tick(127)
check(last("FailMission")[2] == 128 and last("FailMission")[3] == "bd01lseb.des", "no deployment failure")
tick(128); check(count("FailMission") == 1, "failure issued once")

-- Deployment during the opening shot cannot be undone by camera completion.
m = reset(); objects[m.recycler].deployed = true; tick(1)
cameraArrived = true; tick(2); objects[m.recycler].deployed = false; tick(93)
check(m.sound8Time == 999999.9 and count("AudioMessage", "bd01008.wav") == 0,
    "camera completion does not re-arm completed deployment reminders")

-- Deployment during the final reminder succeeds even on audio completion frame.
m = reset(); cameraArrived = true; tick(1); tick(91.1)
finish("bd01008.wav"); tick(92); tick(122.1); finish("bd01009.wav")
objects[m.recycler].deployed = true; tick(123)
check(m.objective1Complete and m.delayTime1 == 143 and count("FailMission") == 0, "late valid deployment cancels failure")
check(count("StopAudioMessage", "audio:" .. "bd01009.wav") == 1, "obsolete deployment audio stopped")
tick(142.9); check(count("BuildObject") == 0, "deployment delay preserved")
tick(143); check(count("BuildObject") == 3 and count("SetPilotClass") == 2, "beacon and two pilot-class-free ambushers")
check(count("Patrol") == 2 and count("Cloak") == 2, "ambushers still patrol cloaked")
check(last("SetObjectiveName")[3] == "Nav Alpha", "beacon name")
check(not m.beaconSpawned2 and count("SetUserTarget") == 0, "BD01002 blocks subsequent flow")
Load(copy(Save())); m = Save(); tick(144)
check(count("AudioMessage", "BD01002.WAV") == 1 and count("BuildObject") == 3, "save during blocking audio resumes without duplication")
finish("BD01002.WAV"); tick(145)
check(m.beaconSpawned2 and m.sound6Time == 205 and last("SetUserTarget")[2] == m.beacon, "Nav Alpha target after audio")
check(objectives["bd01001.otf"] == "green" and objectives["bd01002.otf"] == "white", "second objective visible")
tick(205); check(count("AudioMessage", "bd01006.wav") == 0, "nav first reminder strict boundary")
tick(205.1); finish("bd01006.wav"); tick(206)
check(m.sound7Time == 236, "nav second reminder follows audio")
tick(236.1); finish("bd01007.wav"); tick(237)
check(last("FailMission")[2] == 238 and last("FailMission")[3] == "bd01lsec.des", "nav timeout failure")

m = navPhase(); tick(83.1); finish("bd01006.wav"); tick(84); tick(114.1)
finish("bd01007.wav"); near(m.user, m.beacon, 99); tick(115)
check(m.objective2Complete and count("FailMission") == 0 and m.sound7 == nil, "player proximity wins over stale final reminder")
check(count("StopAudioMessage", "audio:" .. "bd01007.wav") == 1, "obsolete nav audio stopped")
check(not m.ambushRetreat and not m.wave1Ready, "nav arrival alone does not start attack wave")
m = navPhase(); nearest = object("avscav", 1); near(nearest, "spawn_nav_beacon", 100); tick(24)
check(not m.objective2Complete, "ally range strictly below 100")
near(nearest, "spawn_nav_beacon", 99); tick(25)
check(m.objective2Complete, "ally can complete Nav objective")
m = navPhase(); objects[m.badGuy2_ambush].cloaked = false; tick(24)
check(m.objective2Complete and not m.ambushRetreat, "decloak completes objective without killing ambusher")

for _, killed in ipairs({"badGuy1_ambush", "badGuy2_ambush"}) do
    m = navPhase(); objects[m[killed]].alive = false; tick(24)
    local survivor = killed == "badGuy1_ambush" and m.badGuy2_ambush or m.badGuy1_ambush
    check(m.ambushRetreat and m.delayTime2 == 29 and last("Retreat")[2] == survivor, "correct survivor retreats")
    check(last("Retreat")[3] == "ambush_retreat_path" and last("Retreat")[4] == 1, "retreat path and priority")
    tick(28.9); check(not m.wave1Ready, "five-second retreat delay")
    cameraArrived = false; tick(29)
    check(m.wave1Ready and count("SetCloaked") == 2 and m.wave2Delay == 89, "first pair and 60-second wave timer")
    check(last("CameraPath")[2] == "camera_attack_view" and last("CameraPath")[3] == 2000
        and last("CameraPath")[4] == 1000, "attack camera parameters")
    check(count("Attack", survivor) == 1 and count("AudioMessage", "bd01003.wav") == 1, "survivor attacks recycler during camera")
    cancelled = true; tick(30); cancelled = false
    check(m.cameraComplete[1] and count("SetCloaked") == 4 and count("Decloak") == 4, "camera cancel creates second wave1 pair")
    check(count("StopAudioMessage", "audio:" .. "bd01003.wav") == 1, "attack camera cancel stops audio")
    tick(88.9); check(not m.wave2Ready, "wave2 delay not early")
    tick(89)
    check(m.wave2Ready and count("BuildObject", "cvltnk") == 1 and count("BuildObject", "cvfigh") == 10, "all eleven enemies spawned")
    check(count("SetCloaked") == 4, "wave2 does not gain extra cloaking")
    for key, h in pairs(m) do
        if type(key) == "string" and key:match("^badGuy") and h ~= survivor then objects[h].alive = false end
    end
    tick(90); check(count("AudioMessage", "bd01004.wav") == 0, "surviving ambusher blocks victory")
    objects[survivor].alive = false; tick(91)
    check(m.objective3Complete and objectives["bd01003.otf"] == "green", "all enemies completes objective")
    check(count("SucceedMission") == 0, "congratulations audio gates victory")
    Load(copy(Save())); m = Save(); finish("bd01004.wav"); tick(92)
    check(last("SucceedMission")[2] == 96 and last("SucceedMission")[3] == "bd01win.des", "four-second win delay")
    tick(93); check(count("SucceedMission") == 1, "loaded victory issued once")
end

m = wavePhase(); tick(89)
for key, h in pairs(m) do if type(key) == "string" and key:match("^badGuy") then objects[h].alive = false end end
objects[m.recycler].health = 0; objects[m.recycler].alive = false; tick(90)
finish("bd01005.wav"); finish("bd01004.wav"); tick(91)
check(last("FailMission")[2] == 95 and last("FailMission")[3] == "bd01lsea.des", "recycler loss four-second delay")
check(count("SucceedMission") == 0 and count("AudioMessage", "bd01004.wav") == 0, "loss overrides simultaneous enemy elimination")

m = wavePhase(); tick(89)
for key, h in pairs(m) do if type(key) == "string" and key:match("^badGuy") then objects[h].alive = false end end
tick(90); objects[m.recycler].health = 0; finish("bd01004.wav"); tick(91)
check(count("SucceedMission") == 0, "recycler lost during congratulatory audio blocks success")

-- Camera remains active beyond wave2: unbuilt camera reinforcements are not dead.
m = navPhase(); objects[m.badGuy1_ambush].alive = false; tick(24)
cameraArrived = false; tick(29); tick(89)
for key, h in pairs(m) do if type(key) == "string" and key:match("^badGuy") then objects[h].alive = false end end
tick(90)
-- A still-existing destroyed subject keeps the mock camera running until arrival.
check(not m.cameraComplete[1] and count("AudioMessage", "bd01004.wav") == 0, "pending camera pair blocks premature victory")
objects[m.badGuy1_wave1] = nil; tick(91)
check(m.cameraComplete[1] and IsAlive(m.badGuy3_wave1), "missing camera subject releases shot and creates reinforcements")

m = reset({missing = {recycler = true, wingman1_bobcat = true, wingman2_bobcat = true}})
check(count("Goto") == 0 and m.cameraComplete[0], "missing map objects do not produce invalid engine calls")
finish("bd01005.wav"); tick(1)
check(last("FailMission")[3] == "bd01lsea.des", "missing recycler uses original failure path")
m = reset({failedSpawn = "apcamr"}); cameraArrived = true; tick(1)
objects[m.recycler].deployed = true; tick(2); tick(22); finish("BD01002.WAV"); tick(23)
check(count("SetUserTarget") == 0 and not m.objective2Complete, "missing beacon and nearest unit cannot falsely satisfy distance")
local before = count("BuildObject"); local saved = copy(Save()); Load(saved); tick(24)
check(count("BuildObject") == before and Save().sound6Time == 83, "loaded timers/handles preserved without respawning")

print("BlackDog01: " .. checks .. " checks passed (" .. _VERSION .. ")")
