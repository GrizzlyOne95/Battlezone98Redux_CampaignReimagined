-- Run from the repository root with Lua 5.1: lua5.1 Tools/Test-Misns2.lua
-- Mock host regression checks; actual AI movement, audio and cameras need BZR.
local now, objects, labels, calls, distances, nearest, enemies, audioDone
local serial, audioSerial, cancelled, objectiveCount, missingLabels
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, arg)
    local result = 0
    for _, call in ipairs(calls) do
        if call[1] == name and (arg == nil or call[2] == arg) then result = result + 1 end
    end
    return result
end
local function has(name, ...)
    local args = {...}
    for _, call in ipairs(calls) do
        local match = call[1] == name
        for i, arg in ipairs(args) do match = match and call[i + 1] == arg end
        if match then return true end
    end
    return false
end
local function craft(odf, team)
    serial = serial + 1
    objects[serial] = {odf = odf or "svtank", team = team or 1, alive = true}
    return serial
end
function GetHandle(label)
    if missingLabels[label] then return nil end
    if not labels[label] then labels[label] = craft() end
    return labels[label]
end
function IsValid(h) return h ~= nil and objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetTeamNum(h) assert(IsValid(h), "invalid team query"); return objects[h].team end
function GetTime() return now end
function GetDistance(h, target)
    assert(IsValid(h), "invalid distance origin")
    assert(type(target) == "string" or IsValid(target), "invalid distance target")
    return distances[tostring(h) .. ":" .. tostring(target)] or 10000
end
function GetNearestVehicle(path, point)
    assert(type(path) == "string" and point == 1, "native path point must remain 1")
    record("GetNearestVehicle", path, point)
    return nearest[path]
end
function GetNearestEnemy(h)
    assert(IsValid(h), "invalid nearest-enemy origin")
    return enemies[h]
end
function BuildObject(odf, team, where)
    local h = craft(odf, team)
    record("BuildObject", odf, team, where, h)
    AddObject(h)
    return h
end
function RemoveObject(h)
    objects[h] = nil
    record("RemoveObject", h)
end
function AudioMessage(name)
    audioSerial = audioSerial + 1
    record("AudioMessage", name, audioSerial)
    return audioSerial
end
function IsAudioMessageDone(id) return audioDone[id] == true end
function StopAudioMessage(id) audioDone[id] = true; record("StopAudioMessage", id) end
function CameraCancelled() return cancelled end
function CameraReady() record("CameraReady"); return true end
function CameraFinish() record("CameraFinish"); return true end
function CameraPath(path, height, speed, target)
    record("CameraPath", path, height, speed, target)
    return false
end
function ClearObjectives() objectiveCount = 0; record("ClearObjectives") end
function AddObjective(name, color)
    objectiveCount = objectiveCount + 1
    assert(objectiveCount <= 10, "objective buffer overflow")
    assert(color == "white" or color == "red" or color == "green", "invalid objective color")
    record("AddObjective", name, color)
end
for _, name in ipairs({"Attack", "Follow", "Goto", "Retreat", "SetIndependence",
    "SetObjectiveName", "SetObjectiveOn", "FailMission", "SucceedMission"}) do
    local operation = name
    _G[operation] = function(...) record(operation, ...) end
end
local function reset(missing)
    now, serial, audioSerial, objectiveCount, cancelled = 0, 0, 0, 0, false
    objects, labels, calls, distances = {}, {}, {}, {}
    nearest, enemies, audioDone, missingLabels = {}, {}, {}, missing or {}
    dofile("Scripts/misns2.lua")
    Start()
    local m = Save()
    check(not m.missionstart and m.wave1start == 99999999, "Setup state")
    Update(0.05)
    return Save()
end
local function near(h, target, distance)
    distances[tostring(h) .. ":" .. tostring(target)] = distance
end
local function kill(h) objects[h].alive = false end
local function query(path, distance, team)
    local h = craft(nil, team)
    nearest[path] = h
    near(h, path, distance)
    return h
end
local function spawnsAt(path)
    local result = 0
    for _, c in ipairs(calls) do
        if c[1] == "BuildObject" and c[4] == path then result = result + 1 end
    end
    return result
end
local function finishOpening(m)
    audioDone[m.aud1] = true
    Update(0.05)
end
local function reload()
    local saved = {}
    for key, value in pairs(Save()) do saved[key] = value end
    dofile("Scripts/misns2.lua")
    Load(saved)
    return Save()
end

local m = reset()
check(m.missionstart and m.player == labels.svtank0_wingman, "original player label")
check(has("SetObjectiveName", m.cam1, "Launch Pad"), "launch-pad marker name")
check(has("CameraPath", "cinpath1", 500, 200, m.t1), "opening camera values")
check(objectiveCount == 3 and has("AddObjective", "misns201.otf", "white"), "initial objectives")
check(not m.nicetry and not m.wave2gone and not m.wave3gone, "nil nearest handles cannot trigger")
check(not m.openingcindone, "opening waits for audio")
finishOpening(m)
check(m.openingcindone and has("AudioMessage", "misns202.wav"), "opening audio completion")
check(count("CameraFinish") == 1 and has("StopAudioMessage", m.aud1), "opening cleanup")
now = 10; Update(0.05)
check(not m.wave1gone, "wave 1 strict 10-second boundary")
now = 10.01; Update(0.05)
check(m.wave1gone and spawnsAt("bdsp1") == 2, "wave 1 original roster")
check(has("Attack", m.bd1, m.t1, 1) and has("Attack", m.bd2, m.t3, 1), "wave 1 targeting")
check(m.bd3 == nil and m.bd4 == nil, "disabled wave 1 craft stay cut")
kill(m.bd1); kill(m.bd2); Update(0.05)
check(m.cintimeset and has("AudioMessage", "misns203.wav"), "surrender lead-in")
now = m.cintime; Update(0.05)
check(not m.surrender, "surrender strict 3-second boundary")
now = now + 0.01; Update(0.05)
check(m.surrender and spawnsAt("100") == 1 and spawnsAt("110") == 1, "eleven cinematic tanks")
check(has("CameraPath", "platooncam", 1000, 600, m.bd100), "platoon cinematic")
audioDone[m.aud2] = true; Update(0.05)
check(not m.bdcindone, "platoon camera waits for both audio messages")
audioDone[m.aud3] = true; Update(0.05)
check(m.bdcindone and m.platooncamdone and has("AudioMessage", "misns206.wav"), "platoon completion")
check(count("RemoveObject") == 9 and not IsValid(m.bd100), "nine cinematic tanks removed")
check(IsAlive(m.bd103) and IsAlive(m.bd104), "two cinematic attackers survive")
check(has("Attack", m.bd103, m.t3) and has("Attack", m.bd104, m.t2), "survivor orders")
local before = #calls; Update(0.05)
check(count("RemoveObject") == 9 and #calls >= before, "cinematic cleanup does not repeat")

m = reset(); cancelled = true; Update(0.05)
check(m.openingcindone and has("StopAudioMessage", m.aud1), "opening skip")
m.surrender = true; m.bd100 = craft("bvtank", 2); m.bd103 = craft("bvtank", 2); m.bd104 = craft("bvtank", 2)
for n = 101, 110 do if m["bd" .. n] == nil then m["bd" .. n] = craft("bvtank", 2) end end
Update(0.05)
check(m.bdcindone and count("RemoveObject") == 9, "platoon skip retains combat handoff")

m = reset(); query("bdsp2", 420, 2); Update(0.05)
check(not m.wave2gone, "wave 2 strict distance boundary")
near(nearest.bdsp2, "bdsp2", 419); Update(0.05)
check(m.wave2gone and spawnsAt("bdsp2") == 4, "wave 2 nearest branch has no added team filter")
check(has("Attack", m.bd5, m.t3, 1) and has("Attack", m.bd6, m.t1, 1), "wave 2 nearest orders")
m = reset(); near(m.t1, "nav1", 199); Update(0.05)
check(m.wave2gone and has("Attack", m.bd5, m.t1, 1) and has("Attack", m.bd7, m.t2, 1), "wave 2 APC branch orders")
Update(0.05); check(spawnsAt("bdsp2") == 4, "wave 2 latch")

m = reset(); query("bdsp3", 449, 2); Update(0.05)
check(not m.wave3gone, "wave 3 retains explicit friendly-team test")
objects[nearest.bdsp3].team = 1; Update(0.05)
check(m.wave3gone and objects[m.bd9].odf == "bvartl", "wave 3 nearest spawn")
check(not has("Attack", m.bd9) and not has("BuildObject", "proxmine"), "wave 3 nearest branch keeps source orders and no mines")
check(not m.artwarning and m.alerttime == 99999999999, "nearest branch retains unscheduled warning")
m = reset(); near(m.t2, "nav3", 399); Update(0.05)
check(m.wave3gone and not m.wave4gone, "wave 3 APC proximity")
local mines = 0
for n = 1, 19 do if has("BuildObject", "proxmine", 2, "mine" .. n) then mines = mines + 1 end end
check(mines == 19 and count("BuildObject", "proxmine") == 19, "all nineteen mine paths")
check(has("Attack", m.bd9, m.t3) and has("Follow", m.bd11, m.bd9), "APC artillery orders")
local warningTime = m.alerttime
now = warningTime; Update(0.05); check(not m.artwarning, "warning strict 15-second boundary")
objects[m.bd9] = nil; now = warningTime + 0.01; Update(0.05)
check(m.artwarning and has("AudioMessage", "misns210.wav") and has("SetObjectiveOn", m.bd10), "warning safe with removed artillery")
check(m.bd12 == nil and count("SetObjectiveOn") == 1, "missing later-wave markers are skipped")

m = reset(); query("bdsp4", 449, 1); Update(0.05)
check(m.wave4gone and objects[m.bd13].odf == "bvtank", "wave 4 nearest roster retains tank")
check(not has("Attack", m.bd12), "wave 4 nearest autonomous orders retained")
m = reset(); near(m.t3, "nav3", 199); Update(0.05)
check(m.wave3gone and m.wave4gone and objects[m.bd13].odf == "bvartl", "wave 4 APC roster retains second artillery")
check(has("Attack", m.bd12, m.t1) and has("Attack", m.bd13, m.t2), "wave 4 APC orders")
kill(m.bd9); kill(m.bd10); kill(m.bd12); kill(m.bd13); Update(0.05)
check(m.bdplatoonspawned and spawnsAt("bdspmain") == 4, "artillery-clear platoon has four tanks")
check(has("Attack", m.bd15, m.t1) and m.bd19 == nil, "artillery-clear platoon targets")
m = reset(); query("bdspmain", 419, 1); Update(0.05)
check(m.bdplatoonspawned and spawnsAt("bdspmain") == 7, "near-base platoon has seven units")
check(not has("Attack", m.bd15), "near-base platoon retains autonomous source orders")
m = reset(); near(m.player, m.launchpad, 549); Update(0.05)
check(m.wave5gone and spawnsAt("bdsp5") == 3 and m.bd25 == nil, "wave 5 roster preserves cuts")
check(has("Attack", m.bd22, m.t1) and has("Attack", m.bd24, m.t3), "wave 5 orders")

m = reset(); near(m.player, "bdnet4", 549); Update(0.05)
check(m.camnet1found and spawnsAt("bdnet4") == 6 and m.nav1 == nil, "cutoff ambush and disabled first camera net")
check(m.wave4gone and not m.wave3gone, "cutoff flag fix does not suppress wave 3")
local artillery = m.bd12
query("bdsp4", 10, 1); Update(0.05)
check(m.bd12 == artillery and spawnsAt("bdsp4") == 3, "wave 4 cannot overwrite cutoff artillery")
enemies[m.cutoff1] = m.player; near(m.player, m.cutoff1, 399); Update(0.05)
check(m.nicetry and count("AudioMessage", "misns209.wav") == 1, "cutoff taunt")

m = reset(); near(m.player, "bdnet9", 409); Update(0.05)
check(m.camnet2found and count("BuildObject", "apcamr") == 8, "all eight second-network cameras")
check(has("AudioMessage", "misns207.wav") and not m.sneaktimeset, "camera-network discovery")
for n = 7, 14 do check(has("BuildObject", "apcamr", 2, "bdnet" .. n), "camera path " .. n) end
local detector = craft(nil, 2); nearest.bdnet10 = detector; near(detector, "bdnet10", 19); Update(0.05)
check(m.wave3gone and has("Attack", m.bd10, m.t2), "camera proximity retains unfiltered nearest query")

for n = 7, 14 do
    m = reset(); near(m.player, "bdnet12", 409); Update(0.05)
    kill(m["nav" .. n]); Update(0.05)
    check(m.sneaktimeset and m.sneaktime == now + 45, "any destroyed camera starts patrol timer: " .. n)
    check(count("AudioMessage", "misns208.wav") == 1, "camera-loss warning once")
end
now = m.sneaktime; Update(0.05); check(not m.patrolsent, "patrol strict 45-second boundary")
now = now + 0.01; Update(0.05)
check(m.patrolsent and objects[m.pat1].odf == "svfigh", "patrol keeps source Soviet fighter ODF")
check(has("Goto", m.pat1, "bdnet9") and has("Goto", m.pat2, "bdnet12"), "patrol destinations")
local saved = Save()
local spawnCount, radioCount = count("BuildObject"), count("AudioMessage")
Load(saved); Update(0.05)
check(Save() == saved and count("BuildObject") == spawnCount and count("AudioMessage") == radioCount, "restore preserves state without replaying spawns or audio")

for scout = 1, 2 do
    m = reset(); m.patrolsent = true; m.pat1 = craft("svfigh", 2); m.pat2 = craft("svfigh", 2)
    local detected = craft()
    enemies[m["pat" .. scout]] = detected
    near(detected, m["pat" .. scout], 49)
    Update(0.05)
    check(m.wave3gone and has("Attack", m.bd9, detected), "correct scout-enemy pairing: " .. scout)
    check(spawnsAt("bdsp3") == 3, "detected patrol creates one artillery group")
    check(not m.playerfound, "unassigned source playerfound flag is retained")
end
m = reset(); m.patrolsent = true; m.pat1 = craft("svfigh", 2); m.pat2 = craft("svfigh", 2)
near(m.pat1, "bdnet9", 19); Update(0.05)
check(m.bdplatoonspawned and m.wave3gone and spawnsAt("bdspmain") == 7, "patrol destination fallback")
check(has("Attack", m.bd19, m.t3) and has("SetIndependence", m.bd21, 1), "fallback platoon orders")
objects[m.pat1] = nil; objects[m.pat2] = nil; Update(0.05)
check(m.wave3gone, "removed patrol handles are safe")

m = reset({cam1 = true})
check(m.missionstart and not has("SetObjectiveName"), "missing camera label does not dereference")
m = reset(); kill(m.t1); near(m.t1, m.launchpad, 1); Update(0.05)
check(m.missionfail and not m.t1arrive and not m.missionwon, "destroyed APC cannot arrive")
check(count("FailMission") == 0 and has("AudioMessage", "misns212.wav"), "failure waits for audio")
Update(0.05); check(has("AddObjective", "misns201.otf", "red"), "failure objective repaint")
now = 50; audioDone[m.aud10] = true; Update(0.05); Update(0.05)
check(count("FailMission") == 1 and has("FailMission", 50, "misns2l1.des"), "failure scheduled once at audio completion")

m = reset(); near(m.t1, m.launchpad, 100); Update(0.05)
check(not m.t1arrive, "arrival strict 100 m boundary")
for n = 1, 3 do near(m["t" .. n], m.launchpad, 99) end
Update(0.05)
check(m.missionwon and m.t1arrive and m.t2arrive and m.t3arrive, "all three APC arrivals")
check(has("AudioMessage", "misns216.wav") and has("AudioMessage", "misns217.wav") and has("AudioMessage", "misns218.wav"), "individual arrival radios")
check(has("AudioMessage", "misns213.wav") and has("AudioMessage", "misns214.wav") and has("AudioMessage", "misns215.wav"), "victory radio trio")
check(has("Retreat", m.bd22, "bdspmain", 1000), "victory retreat priority")
audioDone[m.aud50] = true; audioDone[m.aud51] = true; Update(0.05)
check(count("SucceedMission") == 0, "victory waits for all three audio messages")
check(has("AddObjective", "misns203.otf", "green") and objectiveCount == 3, "arrival objective repaint")
now = 60; audioDone[m.aud52] = true; Update(0.05); Update(0.05)
check(count("SucceedMission") == 1 and has("SucceedMission", 60, "misns2w1.des"), "success scheduled once at audio completion")

m = reset(); for n = 1, 3 do near(m["t" .. n], m.launchpad, 1) end
Update(0.05); kill(m.t2)
audioDone[m.aud50] = true; audioDone[m.aud51] = true; audioDone[m.aud52] = true
Update(0.05)
check(m.missionfail and count("SucceedMission") == 0, "APC death during victory radio prevents success")
audioDone[m.aud10] = true; Update(0.05)
check(count("FailMission") == 1, "failure takes precedence over retained arrival flags")

m = reset()
local openingAudio, openingDeadline = m.aud1, m.wave1start
local readyCount = count("CameraReady")
m = reload(); Update(0.05)
check(m.aud1 == openingAudio and m.wave1start == openingDeadline, "opening restore preserves audio and timer")
check(count("AudioMessage", "misns200.wav") == 1 and count("CameraReady") == readyCount, "opening restore does not restart cinematic")
audioDone[m.aud1] = true; Update(0.05)
check(m.openingcindone, "restored opening continues to audio-gated completion")
now = 11; Update(0.05); kill(m.bd1); kill(m.bd2); Update(0.05)
now = m.cintime + 0.01; Update(0.05)
local cinematicTank = m.bd100
m = reload(); Update(0.05)
check(m.bd100 == cinematicTank and spawnsAt("100") == 1, "platoon restore retains cinematic objects")
audioDone[m.aud2] = true; audioDone[m.aud3] = true; Update(0.05)
check(m.bdcindone and count("RemoveObject") == 9, "restored platoon completes cleanup once")

m = reset()
m.wave1gone, m.wave2gone, m.wave3gone, m.wave4gone, m.wave5gone = true, true, true, true, true
m.cintimeset, m.bdplatoonspawned = true, true
local retreatHandles = {}
for n = 3, 27 do m["bd" .. n] = craft("bvtank", 2); retreatHandles[#retreatHandles + 1] = m["bd" .. n] end
for n = 100, 110 do m["bd" .. n] = craft("bvtank", 2); retreatHandles[#retreatHandles + 1] = m["bd" .. n] end
for n = 1, 6 do m["cutoff" .. n] = craft("bvtank", 2); retreatHandles[#retreatHandles + 1] = m["cutoff" .. n] end
for n = 1, 2 do m["pat" .. n] = craft("svfigh", 2); retreatHandles[#retreatHandles + 1] = m["pat" .. n] end
for n = 1, 3 do near(m["t" .. n], m.launchpad, 1) end
Update(0.05)
check(count("Retreat") == 44, "complete 44-unit victory retreat sweep")
for _, h in ipairs(retreatHandles) do check(has("Retreat", h, "bdspmain", 1000), "original retreat handle " .. h) end
audioDone[m.aud50], audioDone[m.aud51], audioDone[m.aud52] = true, true, true
Update(0.05); m = reload(); Update(0.05)
check(m.outcomeSent and count("SucceedMission") == 1, "outcome latch survives save/load")

print("misns2: " .. checks .. " checks passed (" .. _VERSION .. ")")
