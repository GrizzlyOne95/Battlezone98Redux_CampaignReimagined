-- Run from repository root: lua5.1 Tools/Test-Chinese04.lua
-- Decision tests only: engine AI, cameras, assets and handle remapping need BZR.
local objects, labels, events, now, player, messages, nextHandle
local distances, cockpit, info, cameraDone, cameraCancel
local function event(kind, ...) events[#events + 1] = {kind, ...} end
local function count(kind, value)
    local n = 0
    for _, e in ipairs(events) do
        if e[1] == kind and (value == nil or e[2] == value) then n = n + 1 end
    end
    return n
end
local function object(label, odf)
    nextHandle = nextHandle + 1
    objects[nextHandle] = {health = 100, max = 100, odf = odf or "test", cloak = false}
    if label then labels[label] = nextHandle end
    return nextHandle
end
function GetHandle(label) return labels[label] end
function GetPlayerHandle() return player end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) assert(IsValid(h)); return objects[h].health > 0 end
function GetCurHealth(h) assert(IsValid(h)); return objects[h].health end
function GetMaxHealth(h) assert(IsValid(h)); return objects[h].max end
function AddHealth(h, n) assert(IsValid(h)); objects[h].health = objects[h].health + n end
function GetDistance(h, target) assert(IsValid(h)); return distances[target] or 1000 end
function GetOdf(h) assert(IsValid(h)); return objects[h].odf end
function IsInfo(odf) assert(type(odf) == "string"); return info[odf] or false end
function IsCloaked(h) assert(IsValid(h)); return objects[h].cloak end
function Decloak(h) assert(IsValid(h)); objects[h].cloak = false; event("decloak", h) end
function EnableCloaking(h, enabled) assert(IsValid(h)); event("enable_cloak", h, enabled) end
function BuildObject(odf, team, path)
    local h = object(nil, odf)
    event("build", odf, team, path, h)
    AddObject(h)
    return h
end
function Attack(h, target) assert(IsValid(h) and IsValid(target)); event("attack", h, target) end
function Retreat(h, target) assert(IsValid(h) and IsValid(target)); event("retreat", h, target) end
function Goto(h, path) assert(IsValid(h)); event("goto", h, path) end
function RemoveObject(h) assert(IsValid(h)); objects[h] = nil; event("remove", h) end
function SetUserTarget(h) assert(IsValid(h)); event("target", h) end
function SetPerceivedTeam(h, team) assert(IsValid(h)); event("perceived", team, h) end
function SetObjectiveOn(h) assert(IsValid(h)); event("marker_on", h) end
function SetObjectiveOff(h) assert(IsValid(h)); event("marker_off", h) end
function SetObjectiveName(h, name) assert(IsValid(h)); event("name", name, h) end
function SetScrap(team, n) event("scrap", team, n) end
function SetPilot(team, n) event("pilot", team, n) end
function ClearObjectives() event("clear") end
function AddObjective(name, color) event("objective", name, color) end
function AudioMessage(name)
    local message = {name = name, done = false}
    messages[#messages + 1] = message
    event("audio", name)
    return message
end
function IsAudioMessageDone(message) assert(type(message) == "table"); return message.done end
function StopAudioMessage(message) assert(type(message) == "table"); event("stop_audio", message.name) end
function StartCockpitTimer(n) cockpit = n; event("timer", n) end
function GetCockpitTimer() return cockpit end
function HideCockpitTimer() event("hide_timer") end
function CameraReady() event("ready"); return true end
function CameraFinish() event("finish"); return true end
function CameraCancelled() return cameraCancel end
function CameraPath(path, height, speed, target)
    assert(IsValid(target)); event("camera", path, height, speed); return cameraDone
end
function CameraPathDir(path, height, speed) event("camera_dir", path, height, speed); return cameraDone end
function PortalIn(h) assert(IsValid(h)); event("portal_in", h) end
function DeactivatePortal(h) assert(IsValid(h)); event("portal_off", h) end
function Hide(h) assert(IsValid(h)); event("hide", h) end
function FailMission(time, file) event("fail", file, time) end
function SucceedMission(time, file) event("win", file, time) end
local function reset(cloaked)
    objects, labels, events, messages, distances, info = {}, {}, {}, {}, {}, {}
    now, nextHandle, cockpit = 0, 0, 0
    cameraDone, cameraCancel = false, false
    for _, label in ipairs({"target_silo", "nav_1", "cca_factory", "factory", "portal"}) do object(label, label .. "_odf") end
    for i = 1, 25 do object("empty_" .. i) end
    for i = 1, 4 do object("turret_" .. i) end
    player = object("player")
    objects[player].cloak = cloaked
    dofile("Scripts/ch04.lua")
    Start()
end
local function tick()
    Update(0.1)
    -- Loading saved state must not replay any one-shot side effects.
    local n = #events
    Load(Save())
    assert(#events == n)
end
local function route()
    tick()
    assert(count("camera", "camera_start") == 1, "startup camera fall-through")
    cameraCancel = true; tick(); cameraCancel = false
    assert(count("stop_audio", "ch04001.wav") == 1)
    now = 5; tick(); assert(count("timer") == 0, "strict intro delay")
    now = 5.1; tick(); assert(cockpit == 130)
    for i = 0, 5 do
        local h = Save().navPoints[i]
        distances[h] = 50; tick(); assert(Save().uptonavpoint == i, "strict nav radius")
        distances[h] = 49; tick()
    end
    assert(count("build", "apcamr") == 5 and count("remove") == 6)
    assert(count("name", "Pit Entrance") == 1)
    distances.trigger_1 = 70; tick(); tick()
    local deadline = Save().stateTimer
    now = deadline; tick(); assert(count("build", "sspilo") == 0)
    now = deadline + 0.1; tick()
    assert(count("build", "sspilo") == 10 and count("camera", "camera_alarm") == 1, "alarm fall-through")
    cameraCancel = true; tick(); cameraCancel = false
    assert(count("build", "sspilo") == 16 and count("retreat") == (IsValid(labels.empty_1) and 16 or 15))
    distances[labels.target_silo] = 200; tick()
    assert(count("goto") == 2)
    info.target_silo_odf = true; tick()
end
for _, cloaked in ipairs({true, false}) do
    reset(cloaked); route()
    assert(count("attack") == 29, "all base craft/turrets alerted")
    assert(count("audio", "ch04002.wav") == (cloaked and 1 or 0))
    tick()
    if cloaked then assert(count("portal_in") == 0); messages[#messages].done = true; tick() end
    assert(count("portal_in") == 1 and count("build", "svfigha") == 8 and count("build", "svtanka") == 4)
    assert(count("build", "svfigh") == 8 and count("attack") == 41, "portal guards have no initial Attack")
    local previous = player
    player = object(nil)
    tick()
    assert(count("attack") == 88, "47 survivors retarget after player change")
    assert(count("decloak", previous) == (cloaked and 2 or 1))
    messages[#messages].done = true; tick()
    assert(count("audio", "ch04008.wav") == 1)
    messages[#messages].done = true; tick()
    local deadline = Save().portalTimeOut
    assert(deadline == now + 135)
    distances[labels.portal] = 100; tick(); assert(count("hide") == 0)
    distances[labels.portal] = 99; tick(); assert(count("hide") == 1)
    objects[player].health = 1
    cameraDone = true; tick()
    assert(objects[player].health == 100)
    now = now + 2; tick(); assert(count("win") == 0)
    now = now + 0.1; tick()
    assert(count("win", "ch04win.des") == 1 and count("portal_off") == 1)
    assert(events[#events][3] == now + 4)
    tick(); assert(count("win") == 1 and count("fail") == 0)
end
reset(true); tick(); cameraDone = true; tick(); now = 6; tick()
cockpit = 0; tick(); tick(); assert(count("fail", "ch04lsea.des") == 1)
reset(true); route(); messages[#messages].done = true; tick()
messages[#messages].done = true; tick(); messages[#messages].done = true; tick()
now = Save().portalTimeOut; tick(); assert(count("fail") == 0)
now = now + 0.1; distances[labels.portal] = 0; tick(); tick()
assert(count("fail", "ch04lseb.des") == 1 and count("hide") == 0, "timeout takes precedence")
reset(false)
objects[labels.factory], objects[labels.portal], objects[labels.empty_1], objects[labels.turret_1] = nil, nil, nil, nil
route(); tick()
assert(count("attack") == 39, "missing base units skipped without dropping surviving orders")
assert(count("portal_in") == 0)
print("Chinese04: startup, routes, waves, cloak, retargeting, deadlines, victory, missing handles and save/load passed")
