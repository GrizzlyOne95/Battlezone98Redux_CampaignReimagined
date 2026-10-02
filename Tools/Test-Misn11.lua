-- Run from the repository root: lua5.1 Tools/Test-Misn11.lua
-- This host models stock APIs; it cannot qualify native AI / real save handles.
assert(_VERSION == "Lua 5.1", "run with Lua 5.1")
local now, objects, labels, calls, distances, serial, missing
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function count(name, arg)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end
    end
    return n
end
local function called(name, ...)
    local args = {...}
    for _, c in ipairs(calls) do
        if c[1] == name then
            local match = true
            for i = 1, select("#", ...) do
                if c[i + 1] ~= args[i] then match = false end
            end
            if match then return true end
        end
    end
    return false
end
local function spawn(odf, team)
    serial = serial + 1
    objects[serial] = {alive = true, health = 1000, odf = odf, team = team}
    return serial
end
function GetHandle(label)
    if missing[label] then return nil end
    if not labels[label] then labels[label] = spawn("mapobject", 1) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function IsAlive(h) return IsValid(h) and objects[h].alive end
function IsOdf(h, odf)
    assert(IsValid(h), "invalid IsOdf")
    return objects[h].odf == odf
end
function AllObjects()
    local list = {}
    for h in pairs(objects) do list[#list + 1] = h end
    table.sort(list)
    local i = 0
    return function() i = i + 1; return list[i] end
end
local function key(h, target, point)
    return tostring(h) .. ":" .. tostring(target) .. ":" .. tostring(point)
end
function GetDistance(h, target, point)
    assert(IsValid(h), "invalid distance origin")
    assert(type(target) == "string" or IsValid(target), "invalid distance target")
    record("GetDistance", h, target, point)
    return distances[key(h, target, point)] or 10000
end
function BuildObject(odf, team, where)
    assert(type(where) == "string" or IsValid(where), "invalid spawn location")
    local h = spawn(odf, team)
    record("BuildObject", odf, team, where, h)
    return h
end
function RemoveObject(h)
    assert(IsValid(h), "invalid removal")
    objects[h] = nil
    record("RemoveObject", h)
end
function AudioMessage(name) record("AudioMessage", name); return 1 end
function AddHealth(h, amount)
    assert(IsValid(h), "invalid health write")
    objects[h].health = objects[h].health + amount
    record("AddHealth", h, amount)
end
function SetTeamNum(h, team)
    assert(IsValid(h), "invalid team write")
    objects[h].team = team
    record("SetTeamNum", h, team)
end
for _, name in ipairs({"SetObjectiveOn", "SetObjectiveOff", "SetObjectiveName"}) do
    local op = name
    _G[op] = function(h, ...)
        assert(IsValid(h), "invalid object write: " .. op)
        record(op, h, ...)
    end
end
for _, name in ipairs({"SetUserTarget", "SetScrap", "ClearObjectives",
    "AddObjective", "Goto", "Attack", "Defend", "FailMission", "SucceedMission"}) do
    local op = name
    _G[op] = function(...) record(op, ...) end
end
local function clear() calls = {} end
local function near(h, target, distance, point)
    distances[key(h, target, point)] = distance
end
local function kill(h) objects[h].alive = false end
local function reset(absent)
    now, serial = 0, 0
    objects, labels, calls, distances, missing = {}, {}, {}, {}, absent or {}
    dofile("Scripts/misn11.lua")
    Start()
    check(not Save().start_done and count("AudioMessage") == 0, "Start only initializes")
    Update(0.05)
    return Save()
end

local m = reset()
check(m.start_done and m.start_delay == 15, "first Execute schedules departure")
check(m.camera_time == 99999 and m.audmsg == 0 and not m.escape_path,
    "unused native state retained")
check(called("SetScrap", 1, 50) and called("AudioMessage", "misn1101.wav"), "briefing/resources")
check(called("SetObjectiveName", m.cam1, "Waypoint 1")
    and called("SetObjectiveName", m.cam2, "Waypoint 2")
    and called("SetObjectiveName", m.cam3, "Launch Pad"), "waypoint names")
check(count("SetObjectiveOn") == 3 and called("SetObjectiveName", m.openh, "Transport 3"),
    "all transports marked")
check(called("SetUserTarget", m.cam1) and called("AddObjective", "misn1101.otf", "white"),
    "initial target/objective")
check(called("AddHealth", m.openh, 300), "Oppenheimer health restoration")
clear(); now = 15; Update(0.05)
check(count("Goto") == 0, "departure strict 15-second boundary")
check(count("AddHealth", m.openh) == 1, "health regeneration occurs every Update")
clear(); now = 15.01; Update(0.20)
check(called("Goto", m.tug1, "base1", 1) and called("Goto", m.tug2, "base1", 1)
    and called("Goto", m.openh, "base1", 0), "departure commands/priorities")
check(called("AddHealth", m.openh, 300) and m.start_delay == 99999,
    "health delta is not timestep scaled; timer disarmed")
clear(); Update(0.05)
check(count("Goto") == 0 and count("AudioMessage", "misn1102.wav") == 0,
    "departure emitted once")

near(m.cam1, m.openh, 50); Update(0.05)
check(not m.betrayal, "betrayal strict distance boundary")
near(m.cam1, m.openh, 49.9); now = 20; Update(0.05)
check(m.betrayal and m.betrayal_time == 35 and called("Goto", m.openh, "openheimer", 1),
    "betrayal departure and announcement delay")
local friendly = spawn("svfigh", 1)
local neutral = spawn("svfigh.odf", 0)
local unrelated = spawn("svtank", 2)
clear(); now = 35; Update(0.05)
check(not m.betrayal_message and objects[m.openh].team == 1, "betrayal strict timer boundary")
clear(); near(m.turr1, m.player, 0); now = 35.01; Update(0.05)
check(m.betrayal_message and objects[m.openh].team == 2, "betrayal changes real team")
check(called("AudioMessage", "misn1103.wav") and called("AudioMessage", "misn1104.wav")
    and called("AudioMessage", "misn1105.wav"), "betrayal messages")
check(called("Defend", m.turr1, 0) and called("Defend", m.turr3, 0), "turrets released")
check(called("BuildObject", "svfigh", 2, "strike1") and count("Goto") == 3
    and called("Goto", friendly, "strike_path1", 0)
    and called("Goto", neutral, "strike_path1", 0) and not called("Goto", unrelated),
    "first strike re-tasks all matching fighters across teams")
check(not m.pursuit_warning, "C++ numeric zero is false despite Lua truthiness")
check(called("AddObjective", "misn1102.otf", "white"), "betrayal objective")
clear(); near(m.turr1, m.player, 9000); Update(0.05)
check(m.pursuit_warning and called("AudioMessage", "misn1106.wav"),
    "source warning is not restricted by a guessed proximity threshold")
clear(); Update(0.05)
check(count("AudioMessage", "misn1106.wav") == 0 and count("BuildObject") == 0,
    "warning and first strike happen once")
check(called("AddHealth", m.openh, 300), "betrayer keeps source health protection")

clear(); near(m.cam1, m.tug1, 50); near(m.cam1, m.player, 50); Update(0.05)
check(not m.check1, "waypoint 1 strict boundary")
near(m.cam1, m.player, 49); Update(0.05)
check(m.check1 and called("SetUserTarget", m.cam2), "player can advance first waypoint")
clear(); near(m.tug1, "check2", 50, 1); near(m.tug1, m.cam2, 1); Update(0.05)
check(not m.check2, "second trigger uses check2 point 1 rather than cam2")
near(m.tug1, "check2", 49, 1); Update(0.05)
check(m.check2 and called("SetObjectiveOff", m.openh) and called("SetUserTarget", m.cam3),
    "second checkpoint hides betrayer marker and advances target")
check(called("GetDistance", m.tug1, "check2", 1), "path point passed to stock API")
check(called("BuildObject", "svfigh", 2, "strike2") and count("Goto") == 4,
    "second strike also redirects surviving first-strike fighters")
check(not m.restart, "convoy waits for second blockade")
clear(); kill(m.turr2); Update(0.05)
check(m.restart and called("Goto", m.tug1, "base2", 1)
    and called("Goto", m.tug2, "base2", 1), "blockade removal releases convoy")
clear(); near(m.launch, m.player, 450); near(m.launch, m.tug1, 450); Update(0.05)
check(not m.launch_attack, "launch attack strict distance boundary")
near(m.launch, m.tug1, 449); Update(0.05)
check(m.launch_attack and count("BuildObject", "svtank") == 2, "tug proximity starts pad ambush")
check(called("AddHealth", m.launch, -0.90), "original pad health delta kept literally")
check(called("Attack", m.tank1, m.launch, 1) and called("Attack", m.tank2, m.launch, 1)
    and count("Attack") == 2, "only the two new tanks attack; cut scan remains inactive")
clear(); kill(m.launch); now = 50; Update(0.05)
check(m.launch_gone and m.escape_time == 90 and called("AudioMessage", "misn1109.wav"),
    "natural pad destruction uses 40-second delay")
clear(); now = 90; Update(0.05)
check(not called("Goto", m.tug1, "escape"), "escape strict timer boundary")
now = 90.01; Update(0.05)
check(called("Goto", m.tug1, "escape") and called("Goto", m.tug2, "escape")
    and called("AudioMessage", "misn1110.wav"), "escape departure with default command priority")
check(called("SetObjectiveOn", m.launch2) and called("SetObjectiveName", m.launch2, "Launch Pad 2")
    and called("AddObjective", "misn1103.otf", "white"), "second pad objective")
clear(); Update(0.05)
check(count("AudioMessage", "misn1110.wav") == 0, "escape orders emitted once")
near(m.tug2, m.cam3, 50); Update(0.05)
check(not m.escape_start, "final wave proximity strict boundary")
near(m.tug2, m.cam3, 49); now = 100; Update(0.05)
check(m.escape_start and m.last_wave_time == 115, "final-wave delay begins at old pad camera")
clear(); now = 115; Update(0.05)
check(not m.last_wave, "final wave strict timer boundary")
clear(); now = 115.01; Update(0.05)
check(m.last_wave and count("BuildObject", "svfigh") == 3
    and called("BuildObject", "avcamr", 1, "last_camera"), "final wave and camera spawn")
check(count("Attack") == 7 and called("Attack", friendly, m.tug2, 1),
    "all six preexisting/new-strike fighters attack transport 2")
local final_fighter
for _, c in ipairs(calls) do
    if c[1] == "BuildObject" and c[4] == m.launch2 then final_fighter = c[5] end
end
check(final_fighter and called("Attack", final_fighter, m.player)
    and not called("Attack", final_fighter, m.tug2, 1), "last fighter is spawned after scan for player attack")
clear(); Update(0.05)
check(count("BuildObject") == 0, "final wave emitted once")
near(m.player, m.launch2, 200); Update(0.05)
check(not m.got_there1, "arrival strict boundary")
near(m.player, m.launch2, 199); Update(0.05)
check(m.got_there1 and not m.won, "player arrival latched independently")
near(m.player, m.launch2, 10000); near(m.tug1, m.launch2, 199); Update(0.05)
check(m.got_there1 and m.got_there2 and not m.won, "player may leave before transport 1 arrives")
near(m.tug1, m.launch2, 10000); near(m.tug2, m.launch2, 199); now = 120; Update(0.05)
check(m.got_there3 and m.won and called("SucceedMission", 135, "misn11w1.des"),
    "independent arrivals yield original success schedule")
clear(); Update(0.05)
check(count("SucceedMission") == 0, "success emitted once")

m = reset(); m.check2 = true; m.restart = true
near(m.launch, m.player, 449); now = 20; Update(0.05)
clear(); kill(m.tank1); kill(m.tank2); now = 30; Update(0.05)
check(not IsValid(m.launch) and m.launch_gone and m.escape_time == 40,
    "both tanks dying forces pad removal and 10-second delay")
check(called("RemoveObject", m.launch) and not called("AudioMessage", "misn1109.wav"),
    "forced-removal source branch does not invent pad-loss audio")
clear(); Update(0.05)
check(m.escape_time == 40 and count("AudioMessage", "misn1109.wav") == 0,
    "natural pad-loss branch does not overwrite forced delay on next frame")
kill(m.cam3); Update(0.05)
check(m.escape_start and m.last_wave_time == 45, "destroyed camera triggers original fallback before escape order")
now = 40; Update(0.05)
check(not called("Goto", m.tug1, "escape"), "forced escape strict boundary")
now = 40.01; Update(0.05)
check(called("Goto", m.tug1, "escape"), "forced escape proceeds at 10 seconds")

m = reset(); near(m.cam1, m.tug1, 49); Update(0.05)
check(m.check1, "transport can also advance waypoint 1")
m = reset(); kill(m.openh); now = 1; clear(); Update(0.05)
check(m.lost and called("FailMission", 16, "misn11l1.des"), "pre-betrayal Oppenheimer death fails")
check(called("AudioMessage", "misn1111.wav") and called("AudioMessage", "misn1112.wav"),
    "original loss messages")
check(count("AddHealth", m.openh) == 0, "dead transport is not resurrected")
clear(); Update(0.05)
check(count("FailMission") == 0, "loss emitted once")
m = reset(); m.betrayal = true; kill(m.openh); Update(0.05)
check(not m.lost, "Oppenheimer death after betrayal does not fail mission")
m = reset(); m.betrayal = true; kill(m.tug2); clear(); now = 10; Update(0.05)
check(m.lost and called("FailMission", 25, "misn11l1.des")
    and called("AddObjective", "misn1102.otf", "white"), "post-betrayal cargo loss objective and failure")
m = reset(); kill(m.tug1); m.last_wave = true
m.got_there1, m.got_there2, m.got_there3 = true, true, true
clear(); Update(0.05)
check(m.lost and not m.won and count("SucceedMission") == 0, "dead cargo prevents success despite latched arrivals")
m = reset(); m.betrayal = true; m.betrayal_time = 1; objects[m.openh] = nil
clear(); now = 2; Update(0.05)
check(m.betrayal_message and count("SetTeamNum") == 0 and not m.lost,
    "missing betrayer null guard preserves announcement/reinforcement flow")
m = reset({apcamr3_camerapod = true, avhaul0_tug = true})
check(m.lost and m.cam1 == nil and m.tug1 == nil,
    "missing startup objects cannot crash or create false proximity; cargo failure retained")
m = reset(); objects[m.cam1] = nil; Update(0.05)
check(not m.betrayal and not m.check1, "removed waypoint handle cannot falsely trigger progression")

m = reset(); now = 5; near(m.cam1, m.openh, 49); Update(0.05)
local snapshot = {}
for k, v in pairs(Save()) do snapshot[k] = v end
-- Simulate returning only serialized state into a fresh mission chunk, without
-- calling Start. Numeric mock handles do not test engine handle rebasing.
dofile("Scripts/misn11.lua"); clear(); Load(snapshot); now = 10; Update(0.05)
check(Save() == snapshot and snapshot.betrayal_time == 20 and snapshot.start_delay == 15,
    "save/load keeps in-flight timers and mission state")
check(count("AudioMessage", "misn1101.wav") == 0 and count("SetScrap") == 0
    and count("BuildObject") == 0, "load does not replay startup or spawn duplicates")
now = 20; Update(0.05)
check(not snapshot.betrayal_message, "restored betrayal respects strict timer boundary")
now = 20.01; Update(0.05)
check(snapshot.betrayal_message and count("BuildObject", "svfigh") == 1,
    "restored delayed betrayal resumes once")
snapshot.last_wave = true; snapshot.got_there1 = true; snapshot.got_there2 = true
snapshot.launch_gone = true; snapshot.launch_attack = true; snapshot.escape_start = true
snapshot.escape_time = 60; snapshot.last_wave_time = 99999
local escape_snapshot = {}
for k, v in pairs(Save()) do escape_snapshot[k] = v end
dofile("Scripts/misn11.lua"); clear(); Load(escape_snapshot)
near(escape_snapshot.tug2, escape_snapshot.launch2, 199); now = 30; Update(0.05)
check(escape_snapshot.got_there1 and escape_snapshot.got_there2 and escape_snapshot.won,
    "late-game arrival latches and wave flags survive reload")
check(count("BuildObject") == 0 and count("SucceedMission") == 1,
    "late reload does not duplicate wave; success still scheduled")
local new_player = spawn("avtank", 1); labels.player = new_player
Update(0.05)
check(Save().player == new_player, "current player handle refreshed after vehicle change")
print("misn11: " .. checks .. " checks passed (" .. _VERSION .. ")")
