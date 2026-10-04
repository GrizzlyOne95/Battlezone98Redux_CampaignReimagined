-- Run from repository root: lua5.1 Tests/tran05_spec.lua
-- API stubs check script logic; they do not simulate engine AI or cinematics.
local now, objects, calls, shots, audioDone, distances
local function Record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function Count(name, arg)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end
    end
    return n
end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function IsOdf(h, odf) assert(IsValid(h)); return objects[h].odf == odf end
function GetTime() return now end
function GetPlayerHandle() return "player" end
function GetHandle(label) return label end
function GetLastEnemyShot(h) assert(IsValid(h)); return shots[h] or 0 end
function GetDistance(a, b)
    assert(IsValid(a) and IsValid(b), "invalid distance endpoint")
    return distances[a .. ":" .. b] or distances[b .. ":" .. a] or 1000
end
function AudioMessage(file) Record("AudioMessage", file); return file end
function IsAudioMessageDone(msg) assert(msg ~= nil); return audioDone[msg] or false end
function CameraCancelled() return false end
function CameraPath(...) Record("CameraPath", ...); return false end
for _, name in ipairs({"SetPilot", "SetScrap", "SetAIP", "SetUserTarget",
    "CameraReady", "CameraFinish", "StopAudioMessage", "ClearObjectives",
    "AddObjective", "SetObjectiveOn", "Goto", "Attack", "Follow", "Retreat",
    "AddHealth", "FailMission", "SucceedMission"}) do
    local fn = name
    _G[fn] = function(...) Record(fn, ...) end
end
function RemoveObject(h) assert(IsValid(h)); objects[h] = nil; Record("RemoveObject", h) end
local serial = 0
function BuildObject(odf, team, path)
    serial = serial + 1
    local h = "built" .. serial
    objects[h] = {alive = true, team = team, odf = odf}
    Record("BuildObject", odf, team, path)
    AddObject(h) -- synchronous case; deferred case tested separately
    return h
end
local function Reset()
    now, objects, calls, shots, audioDone, distances = 100, {}, {}, {}, {}, {}
    for _, h in ipairs({"player", "fake_player", "avland0_wingman", "sscr_171_scrap",
        "abcomm1_i76building", "avrecy-1_recycler", "apscrap-1_camerapod",
        "sscr_176_scrap", "apbase-1_camerapod"}) do
        objects[h] = {alive = true, team = 1, odf = "fixture"}
    end
    Start()
    Update(0.05)
end
local function Scav()
    objects.scav = {alive = true, team = 1, odf = "avscav"}
    AddObject("scav")
end
local function FinishIntro()
    audioDone["misn0230.wav"] = true
    Update(0.05)
    assert(not Save().camera3 and not IsValid("fake_player"))
    assert(Count("CameraFinish") == 1 and Count("AudioMessage", "misn0224.wav") == 1)
end
assert(loadfile("Scripts/tran05.lua"))()
Reset()
assert(Count("SetPilot", 1) == 1 and Count("SetScrap", 1) == 1)
FinishIntro()
Scav()
distances["scav:sscr_171_scrap"] = 74
Update(0.05)
assert(Save().message1 and Save().message4 and Count("BuildObject", "svfigh") == 1)
assert(Count("Goto", Save().bscout) == 1)
for _, c in ipairs(calls) do
    if c[1] == "Goto" and c[2] == Save().bscout then assert(c[3] == "patrol1" and c[4] == 0) end
end
distances["scav:sscr_176_scrap"] = 199
Update(0.05)
assert(Save().message5 and Save().wave_timer == 130)
now = 130
Update(0.05)
assert(Count("BuildObject", "svfigh") == 2, "strict wave deadline")
now = 130.01
Update(0.05)
assert(Count("BuildObject", "svfigh") == 3 and Save().wave_timer == 175.01)
shots.scav = 1
Update(0.05)
assert(Save().message2)
local retreatPriority
for _, c in ipairs(calls) do
    if c[1] == "Follow" and c[2] == "scav" then retreatPriority = c[4] end
end
assert(retreatPriority == 0, "native retreat command is player-commandable")
distances["scav:abcomm1_i76building"] = 299
Update(0.05)
local m = Save()
assert(m.message3 and m.bscav == "scav" and m.scav2 ~= "scav")
assert(Count("BuildObject", "avscav") == 1 and Count("Retreat", m.scav2) == 1)
local nextHealth = m.NextSecond
now = nextHealth
Update(0.05)
assert(Count("AddHealth", "scav") == 0)
now = nextHealth + 0.01
Update(0.05)
assert(Count("AddHealth", "scav") == 1)
now = m.last_wave_time + 0.01
Update(0.05)
assert(m.last_wave_time == 99999 and Count("Attack") == 1)
distances[m.scav2 .. ":abcomm1_i76building"] = 199
Update(0.05)
assert(m.mission_won and not m.mission_lost and Count("SucceedMission") == 0)
-- Save/load must not restart intro, timers or spawns.
local before, deadline = #calls, m.wave_timer
Load(m)
assert(#calls == before and Save().wave_timer == deadline)
audioDone["misn0234.wav"] = true
objects["abcomm1_i76building"].alive = false
Update(0.05)
assert(not m.mission_lost and Count("SucceedMission") == 1)

-- Independent base loss before any scav exists, with failure audio wait.
Reset()
FinishIntro()
objects["abcomm1_i76building"].alive = false
Update(0.05)
assert(Save().mission_lost and Count("FailMission") == 0)
audioDone["misn0227.wav"] = true
Update(0.05)
assert(Count("FailMission") == 1 and Count("SucceedMission") == 0)

-- Same-frame base loss and second-scav arrival: failure owns shared audio.
Reset()
FinishIntro()
Scav()
m = Save()
m.message1, m.message4, m.message3 = true, true, true
m.scav2 = BuildObject("avscav", 1, "spawn3")
distances[m.scav2 .. ":abcomm1_i76building"] = 10
objects["abcomm1_i76building"].alive = false
Update(0.05)
assert(m.mission_lost and not m.mission_won and m.audmsg == "misn0227.wav")

-- Deleted scav must enter loss instead of querying its position/shot data.
Reset()
FinishIntro()
Scav()
m = Save()
m.message1, m.message5 = true, true
objects.scav = nil
Update(0.05)
assert(m.mission_lost)

-- A deferred fighter callback still sets message4 on the next update.
Reset()
FinishIntro()
Scav()
objects.deferred = {alive = true, team = 2, odf = "svfigh"}
AddObject("deferred")
Update(0.05)
assert(Save().found2 and Save().message4)
-- Rescue deliberately does not depend on message2, matching native order.
m = Save()
m.message1 = true
distances["scav:abcomm1_i76building"] = 299
Update(0.05)
assert(m.message3 and not m.message2)
print("tran05: mission flow, strict timers, priorities, persistence and failure cases passed")
