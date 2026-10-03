-- Run from repository root: lua5.1 Tools/Test-BlackDog04.lua
local now, objects, labels, calls, serial, player, distances, info, tug, done
local cancelled, arrived, inside, timer, config
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
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
local function object(odf)
    serial = serial + 1
    objects[serial] = {odf = odf, health = 1}
    return serial
end
function IsValid(h) return objects[h] ~= nil end
function GetHandle(label)
    if config.missing == label then return nil end
    if not labels[label] then labels[label] = object(label) end
    return labels[label]
end
function GetPlayerHandle() return player end
function GetTime() return now end
function GetHealth(h) assert(IsValid(h)); return objects[h].health end
function GetDistance(a, b, point)
    assert(IsValid(a) and (type(b) == "string" or IsValid(b)), "unsafe distance")
    return distances[tostring(a) .. ":" .. tostring(b)] or 10000
end
function IsInsideArea(path, h)
    assert(path == "base_limit" and IsValid(h)); return inside
end
function BuildObject(odf, team, path)
    record("BuildObject", odf, team, path)
    if config.failed == odf then return nil end
    local h = object(odf); AddObject(h); return h
end
function BuildObjectAtPortal(odf, team, portal)
    assert(IsValid(portal)); record("BuildObjectAtPortal", odf, team, portal)
    return object(odf)
end
function Goto(h, path, priority) assert(IsValid(h)); record("Goto", h, path, priority) end
function Attack(h, target, priority)
    assert(IsValid(h) and IsValid(target)); record("Attack", h, target, priority)
end
function RemoveObject(h) assert(IsValid(h)); objects[h] = nil; record("RemoveObject", h) end
for _, name in ipairs({"Hide", "UnHide", "SetObjectiveOn", "SetObjectiveOff",
                      "SetObjectiveName", "SetUserTarget", "SetPerceivedTeam",
                      "PortalOut", "DeactivatePortal"}) do
    _G[name] = function(h, ...) assert(IsValid(h), name); record(name, h, ...) end
end
for _, name in ipairs({"SetScrap", "SetPilot", "ClearObjectives", "AddObjective",
                      "CameraReady", "CameraFinish", "HideCockpitTimer",
                      "StopCockpitTimer", "SucceedMission", "FailMission"}) do
    _G[name] = function(...) record(name, ...) end
end
function CameraPath(path, height, speed, subject)
    assert(IsValid(subject)); record("CameraPath", path, height, speed, subject)
    return arrived
end
function CameraCancelled() return cancelled end
function AudioMessage(file)
    record("AudioMessage", file)
    return "message:" .. #calls
end
function IsAudioMessageDone(message) assert(message ~= nil); return done[message] or false end
function StopAudioMessage(message) assert(message ~= nil); record("StopAudioMessage", message) end
function StartCockpitTimer(seconds, warn, alert)
    timer = seconds; record("StartCockpitTimer", seconds, warn, alert)
end
function GetCockpitTimer() return timer end
function IsInfo(odf) return info[odf] or false end
function GetTug(h) assert(IsValid(h)); return tug end
local function reset(options)
    config = options or {}
    now, serial = 0, 0
    objects, labels, calls, distances, info, done = {}, {}, {}, {}, {}, {}
    cancelled, arrived, inside, timer, tug = false, false, false, 60, nil
    player = object("player")
    dofile("Scripts/bd04.lua"); Start()
end
local function tick(time) now = time; Update(0.1) end
local function distance(a, b, value) distances[tostring(a) .. ":" .. tostring(b)] = value end
local function intro()
    tick(0); arrived = true; tick(0.1); arrived = false
    tick(1.7); tick(4.2); tick(6.2); tick(7.2)
end
local function inspect()
    info.cbport = true; tick(8)
    info.cbport = false; tick(10.1)
    info.obdataa = true; tick(10.2); info.obdataa = false
end

reset(); tick(0)
check(count("SetScrap") == 1 and last("SetScrap")[3] == 8, "startup scrap")
check(count("BuildObject", "aspilo") == 1 and count("Hide") == 1, "intro pilot/hide")
local s = Save(); distance(s.pilot, "nav_1", 0.5); tick(0.5)
distance(s.pilot, "nav_2", 0.5); tick(0.6)
check(count("BuildObject", "apcamr") == 2, "walking pilot builds both navs")
tick(2.7)
check(s.cameraComplete[0] and count("UnHide") == 1, "nav delay finishes camera")
check(count("PortalOut") == 1 and last("SetPerceivedTeam")[3] == 2, "outward portal/disguise")
tick(4.3); tick(6.8); tick(8.8); tick(9.8)
check(count("BuildObjectAtPortal") == 2 and count("DeactivatePortal") == 1, "portal units/shutdown")
check(s.gotoScav and count("SetUserTarget") == 1, "scav objective starts")
local reminders = count("AudioMessage", "bd04003.wav"); tick(130)
check(count("AudioMessage", "bd04003.wav") == reminders + 1, "120s reminder")
player = s.scav3; tick(131)
check(s.objective1Complete and count("AudioMessage", "bd04010.wav") == 1, "scav entry")
distance(s.scav3, "trigger_1", 399); inside = true; tick(132)
check(s.trigger1 and not s.doAttack and count("AudioMessage", "bd04005.wav") == 0, "safe route")

reset(); intro(); s = Save(); player = s.scav3; inside = true; tick(8)
check(s.inBaseSound1 ~= nil and not s.doAttack, "bad scav entry warns first")
done[s.inBaseSound1] = true; tick(9); tick(10.1)
check(s.inBaseSound2 ~= nil and not s.doAttack, "second warning after one second")
done[s.inBaseSound2] = true; tick(11); tick(11.1)
check(s.doAttack and count("Attack") == 9, "nine turret attacks once")
player = object("new vehicle"); tick(11.2)
check(count("Attack") == 18 and last("Attack")[3] == player, "retarget changed vehicle")
reset(); intro(); inside = true; tick(8)
check(Save().doAttack and count("Attack") == 9, "non-scav entry attacks immediately")

reset(); intro(); info.cbport = true; tick(8); info.cbport = false
s = Save(); check(s.objective2Complete and last("StartCockpitTimer")[2] == 60, "portal inspection/countdown")
tick(10.1); check(count("AudioMessage", "bd04004.wav") == 1, "two second briefing delay")
timer = 0; tick(68); local warning = s.sound5
for i = 1, 30 do tick(68 + i / 10) end
check(count("AudioMessage", "bd04005.wav") == 1 and s.sound5 == warning, "timeout must not restart audio")
Load(Save()); tick(72)
check(count("AudioMessage", "bd04005.wav") == 1, "timeout latch survives load")
done[warning] = true; tick(73)
check(count("AudioMessage", "bd04006.wav") == 1, "second timeout warning")
done[s.sound6] = true; tick(74); tick(74.1)
check(s.doAttack and count("Attack") == 9, "timeout warning leads to attack")

reset(); intro(); inspect(); s = Save()
check(s.idFragment and s.objective3Complete and count("StopCockpitTimer") == 1, "fragment inspection")
check(not s.won, "null beacon cannot win")
tug = player; tick(11)
check(s.gotFragment and count("BuildObject", "bvfigh") == 3 and count("BuildObject", "bvtank") == 3, "six escorts")
distance(s.fragment, s.navBeacon, 1); tick(40.9)
check(not s.won and count("BuildObject", "bvhraza") == 0, "temporary beacon cannot win; 30s delay")
tick(41.1)
check(s.dropZoneReady and count("BuildObject", "bvhraza") == 5, "five bomber support")
check(count("BuildObject", "cvfighg") == 12 and count("BuildObject", "cvtnk") == 3, "extraction attack waves")
check(count("SetUserTarget") == 1, "disabled nav targeting stays disabled")
local buildCount = count("BuildObject"); Load(Save()); tick(42)
check(count("BuildObject") == buildCount, "load cannot replay spawn event")
distance(s.fragment, s.navBeacon, 50); tick(43); check(not s.won, "strict 50m threshold")
distance(s.fragment, s.navBeacon, 49); tick(44)
check(s.won and count("AudioMessage", "bd04008.wav") == 1, "drop zone victory")
done[s.congrats] = true; tick(45)
check(last("SucceedMission")[2] == 45.1 and last("SucceedMission")[3] == "bd04win.des", "absolute success time")
tick(46); check(count("SucceedMission") == 1, "success once")

reset(); intro(); s = Save()
for i = 1, 4 do distance(s.hauler, "return_" .. i, 299) end
tick(8); tick(9); Load(Save()); tick(10)
check(count("BuildObject", "cvfigh") == 12 and count("Attack") == 12, "four ungated one-shot ambushes")
objects[s.hauler].health = 0; tick(11); tick(12)
check(s.lost and count("FailMission") == 1 and last("FailMission")[2] == 12, "hauler loss once")
reset(); intro(); s = Save(); objects[s.portal].health = 0; tick(8)
check(s.lost and last("FailMission")[3] == "bd04lose.des", "portal loss")

reset(); cancelled = true; tick(0); s = Save()
check(s.cameraComplete[0] and s.cameraComplete[1], "cancel both shots")
check(count("StopAudioMessage") == 1, "no stop on missing portal audio")
cancelled = false; tick(1.6); tick(4.1); tick(7.1)
check(count("BuildObjectAtPortal") == 2 and count("DeactivatePortal") == 1, "cancel keeps scheduled portal spawns")
reset({failed = "aspilo"}); tick(0)
check(Save().cameraComplete[0] and count("UnHide") == 1, "missing pilot finishes camera")
reset({missing = "portal"}); arrived = true; tick(0)
check(Save().lost and count("FailMission") == 1, "missing portal fails safely")
reset(); intro(); objects[Save().fragment] = nil; player = nil; tick(8)
check(not Save().gotFragment and not Save().won, "nil cargo/player cannot trigger pickup/victory")
print("BlackDog04: " .. checks .. " checks passed (" .. _VERSION .. ")")
