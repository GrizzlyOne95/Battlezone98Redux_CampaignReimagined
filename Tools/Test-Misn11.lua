-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Run from the repository root: lua5.1 Tools/Test-Misn11.lua
-- Offline (single-player) behavior of the co-op-capable misn11: the real CRCoop runs with
-- single-player semantics, so every check below is the DLL's own flow plus the documented
-- CR changes (CCA on team 5, CCA-only fighter scans, the blockade walker, the backup squad,
-- the ambush, misn1114/1115). Multi-player behavior is in Test-Misn11Coop.lua.
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
local function strikeGotos()
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == "Goto" and type(c[3]) == "string" and c[3]:find("strike_path", 1, true) then n = n + 1 end
    end
    return n
end
local function spawn(odf, team)
    serial = serial + 1
    objects[serial] = {alive = true, health = 1000, odf = odf, team = team}
    return serial
end
local LABEL_TEAM = {svturr0_turrettank = 5, svturr1_turrettank = 5, svturr2_turrettank = 5,
    svturr3_turrettank = 5, second_blockade = 5, svwalk0_walker = 5, svartl0_howitzer = 5,
    ["svartl0(1)_howitzer"] = 5}
function GetHandle(label)
    if missing[label] then return nil end
    if not labels[label] then labels[label] = spawn("mapobject", LABEL_TEAM[label] or 1) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTeamNum(h) assert(IsValid(h), "invalid team read"); return objects[h].team end
function SetVector(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
function GetLabel() return nil end
function GetPosition() return SetVector(0, 0, 0) end
function GetTerrainHeightAndNormal() return 20, SetVector(0, 1, 0) end
function DisplayMessage() end
function Ally() end
function UnAlly() end
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
    assert(type(where) == "string" or type(where) == "table" or IsValid(where), "invalid spawn location")
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
AiCommand = { FORMATION = 6 }
function SetCommand(h, cmd, prio, who) if cmd == AiCommand.FORMATION then record("Formation", h, who, prio) else record("SetCommand", h, cmd, prio, who) end end
for _, name in ipairs({"SetUserTarget", "SetScrap", "ClearObjectives",
    "AddObjective", "Goto", "Attack", "Defend", "FailMission", "SucceedMission"}) do
    local op = name
    _G[op] = function(...) record(op, ...) end
end
local function noop() end
local modules = {
    RequireFix = {Initialize = noop}, exu = {},
    Environment = {Init = noop, Update = noop, OnObjectCreated = noop},
    -- The real module plays through AudioMessage and returns its handle.
    ScriptSubtitles = {Play = function(file) return AudioMessage(file) end,
        Queue = function(file) return AudioMessage(file) end, Stop = noop, Update = noop, Initialize = noop},
    CRIoSites11 = {mission = "misn11"},
    CRIoWeather = {Seed = 1,
        Init = function(config) record("IoInit", config) end,
        Update = function(dt) record("IoUpdate", dt) end,
        Shutdown = function() record("IoShutdown") end,
        OnObjectCreated = noop,
        Save = function() record("IoSave"); return {tag = "weather"} end,
        Load = function(state) record("IoLoad", state) end,
        AnnounceState = function() record("IoAnnounce") end,
        ApplyNetEvent = function(...) record("IoNetEvent", ...) end,
        SetTargetLevel = function(level) record("IoTarget", level) end,
        ForceLevel = function(level, seconds, transition) record("IoForce", level, seconds, transition) end,
        ReleaseForcedLevel = function() record("IoRelease") end,
        Quake = function(strength, duration) record("IoQuake", strength, duration) end},
}
function require(name) return assert(modules[name], name) end
local function clear() calls = {} end
local function near(h, target, distance, point)
    distances[key(h, target, point)] = distance
    -- Mission code asks both ways round (unit -> player, player -> unit): the host is symmetric.
    if type(target) == "number" then distances[key(target, h, point)] = distance end
end
local function kill(h) objects[h].alive = false end
local function reset(absent)
    now, serial = 0, 0
    objects, labels, calls, distances, missing = {}, {}, {}, {}, absent or {}
    labels.player = spawn("avtank", 1)
    modules.CRCoopDiagnostics = assert(loadfile("Scripts/CRCoopDiagnostics.lua"))()
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRCoopRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    modules.CRCoop = assert(loadfile("Scripts/CRCoop.lua"))()
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
local ccafighter = spawn("svfigh", 5)
clear(); now = 35; Update(0.05)
check(not m.betrayal_message and objects[m.openh].team == 1, "betrayal strict timer boundary")
clear(); near(m.turr1, labels.player, 0); now = 35.01; Update(0.05)
check(m.betrayal_message and objects[m.openh].team == 5, "betrayal changes real team (CCA is team 5)")
check(called("AudioMessage", "misn1103.wav") and called("AudioMessage", "misn1104.wav")
    and called("AudioMessage", "misn1105.wav"), "betrayal messages")
check(called("Defend", m.turr1, 0) and called("Defend", m.turr3, 0), "turrets released")
check(called("BuildObject", "svfigh", 5, "strike1") and strikeGotos() == 2
    and called("Goto", ccafighter, "strike_path1", 0)
    and not called("Goto", friendly) and not called("Goto", neutral) and not called("Goto", unrelated),
    "first strike re-tasks only CCA fighters (a guest's or ally's svfigh is never retasked)")
check(not m.pursuit_warning, "C++ numeric zero is false despite Lua truthiness")
check(called("AddObjective", "misn1102.otf", "white"), "betrayal objective")
clear(); near(m.turr1, labels.player, 9000); Update(0.05)
check(m.pursuit_warning and called("AudioMessage", "misn1106.wav"),
    "source warning is not restricted by a guessed proximity threshold")
clear(); Update(0.05)
check(count("AudioMessage", "misn1106.wav") == 0 and count("BuildObject") == 0,
    "warning and first strike happen once")
check(called("AddHealth", m.openh, 300), "betrayer keeps source health protection")

clear(); near(m.cam1, m.tug1, 50); near(labels.player, m.cam1, 50); Update(0.05)
check(not m.check1, "waypoint 1 strict boundary")
near(labels.player, m.cam1, 49); Update(0.05)
check(m.check1 and called("SetUserTarget", m.cam2), "player can advance first waypoint")
clear(); near(m.tug1, "check2", 50, 1); near(m.tug1, m.cam2, 1); Update(0.05)
check(not m.check2, "second trigger uses check2 point 1 rather than cam2")
near(m.tug1, "check2", 49, 1); Update(0.05)
check(m.check2 and called("SetObjectiveOff", m.openh) and called("SetUserTarget", m.cam3),
    "second checkpoint hides betrayer marker and advances target")
check(called("GetDistance", m.tug1, "check2", 1), "path point passed to stock API")
check(called("BuildObject", "svfigh", 5, "strike2") and strikeGotos() == 3,
    "second strike also redirects surviving first-strike fighters")
check(not m.restart, "convoy waits for second blockade")
clear(); kill(m.turr2); Update(0.05)
check(not m.restart, "the walker beside the blockade must die too")
kill(m.walker); Update(0.05)
check(m.restart and called("Goto", m.tug1, "base2", 1)
    and called("Goto", m.tug2, "base2", 1), "blockade removal releases convoy")
clear(); near(labels.player, m.launch, 450); near(m.launch, m.tug1, 450); Update(0.05)
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
local tug2Attackers = 0
for _, c in ipairs(calls) do if c[1] == "Attack" and c[3] == m.tug2 and c[4] == 1 then tug2Attackers = tug2Attackers + 1 end end
check(tug2Attackers == 5 and not called("Attack", friendly) and not called("Attack", neutral),
    "the five CCA fighters (not a guest's or an ally's) attack transport 2")
local final_fighter
for _, c in ipairs(calls) do
    if c[1] == "BuildObject" and c[4] == m.launch2 then final_fighter = c[5] end
end
check(final_fighter and called("Attack", final_fighter, labels.player)
    and not called("Attack", final_fighter, m.tug2, 1), "last fighter is spawned after scan for player attack")
clear(); Update(0.05)
check(count("BuildObject") == 0, "final wave emitted once")
near(labels.player, m.launch2, 200); Update(0.05)
check(not m.got_there1, "arrival strict boundary")
near(labels.player, m.launch2, 199); Update(0.05)
check(m.got_there1 and not m.won, "player arrival latched independently")
near(labels.player, m.launch2, 10000); near(m.tug1, m.launch2, 199); Update(0.05)
check(m.got_there1 and m.got_there2 and not m.won, "player may leave before transport 1 arrives")
near(m.tug1, m.launch2, 10000); near(m.tug2, m.launch2, 199); now = 120; Update(0.05)
check(m.got_there3 and m.won and called("SucceedMission", 135, "misn11w1.des"),
    "independent arrivals yield original success schedule")
clear(); Update(0.05)
check(count("SucceedMission") == 0, "success emitted once")

m = reset(); m.check2 = true; m.restart = true
near(labels.player, m.launch, 449); now = 20; Update(0.05)
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
local waveBuilds = 0
for _, c in ipairs(calls) do if c[1] == "BuildObject" and type(c[4]) == "string" then waveBuilds = waveBuilds + 1 end end
check(waveBuilds == 0 and count("SucceedMission") == 1,
    "late reload does not duplicate wave; success still scheduled")
local new_player = spawn("avtank", 1); labels.player = new_player
near(new_player, escape_snapshot.launch2, 5)
Update(0.05)
check(escape_snapshot.won, "current player handle is read live after a vehicle change")

-- ---------------------------------------------------------------- CR additions (offline)
local function ordered(name, unit, target) return called(name, unit, target, 1) end
m = reset()
check(not called("SetAIControl") and not called("SetAIP"), "script-only CCA: no strategic AI")
check(called("IoInit") and count("IoTarget", 2) == 1, "Io weather starts calm then steps to level 2 at the start")
check(called("SetObjectiveName", m.cam1, "Waypoint 1"), "presentation applies locally offline")
-- Respawn rally phase flips when the convoy moves out.
check(modules.CRCoop.GetMissionPhase() == 0, "rally phase 0 until the convoy departs")
now = 15.01; Update(0.05)
check(modules.CRCoop.GetMissionPhase() == 1, "convoy departure advances the rally phase")

-- Pickets wake on convoy/player proximity and hunt; walker wakes at check2; artillery after betrayal.
m = reset(); clear(); now = 20; Update(0.05)
check(count("Attack") == 0, "idle CCA units stay idle until triggered")
near(m.picket1, m.tug1, 379); now = 24; Update(0.05)
check(ordered("Attack", m.picket1, m.tug1) and not called("Attack", m.picket2), "picket 1 wakes on the convoy and hunts the tug")
clear(); now = 27; Update(0.05)
check(count("Attack", m.picket1) == 0, "an unchanged hunt is not re-issued every pass")
now = 34; Update(0.05)
check(count("Attack", m.picket1) == 1, "the hunt is refreshed on the reissue interval")
near(labels.player, m.picket2, 379); now = 40; Update(0.05)
check(ordered("Attack", m.picket2, labels.player), "a human near a picket wakes it too")
m = reset(); near(m.picket1, m.tug1, 900); now = 20; Update(0.05); clear()
near(m.walker, m.tug1, 300); now = 30; Update(0.05)
check(count("Attack", m.walker) == 0, "walker idles before the convoy halts")
m.check2 = true; now = 40; Update(0.05)
check(ordered("Attack", m.walker, m.tug1), "walker advances on the convoy once check2 fires")
m = reset(); near(m.art1, labels.player, 649); now = 20; Update(0.05)
check(count("Attack", m.art1) == 0, "artillery holds fire before the betrayal")
m.betrayal_message = true; now = 24; Update(0.05)
check(ordered("Attack", m.art1, labels.player) and not called("Attack", m.art2), "artillery shells a human within 650 m after the defection")

-- Backup squad: called when the tug nears Waypoint 1, forms up on the defector, engages chasers.
m = reset(); now = 15.01; Update(0.05); clear()
near(m.openh, m.cam1, 250); now = 16; Update(0.05)
check(not m.backup_called, "backup call distance is strict")
near(m.openh, m.cam1, 249); now = 17; Update(0.05)
check(m.backup_called and #m.backup == 3 and count("BuildObject", "svtank", 5) == 2 and count("BuildObject", "svfigh", 5) == 1,
    "backup squad (2 svtank + 1 svfigh) built on the CCA team")
for _, unit in ipairs(m.backup) do
    check(objects[unit].team == 5 and called("Goto", unit, m.art1, 1), "squad rendezvous at the outpost artillery")
end
check(not called("Formation"), "squad does not form on the tug before it defects")
near(m.cam1, m.openh, 49); now = 18; Update(0.05)
check(m.betrayal, "defection begins")
local friendlyFighter = spawn("svfigh", 1)
now = 33.01; Update(0.05)
check(m.betrayal_message, "defection announced")
now = 33.5; Update(0.05)
for _, unit in ipairs(m.backup) do check(called("Formation", unit, m.openh, 1), "squad forms up on the defector") end
-- The strike scan never takes the squad.
local squadFighter = m.backup[3]
check(not called("Goto", squadFighter, "strike_path1", 0), "squad fighter is not retasked by the strike scan")
-- Chasers: a human within 350 m draws every living squad member.
clear(); near(m.openh, labels.player, 351); now = 36; Update(0.05)
check(count("Attack") == 0, "no chaser outside 350 m")
near(m.openh, labels.player, 349); now = 38.1; Update(0.05)
for _, unit in ipairs(m.backup) do check(ordered("Attack", unit, labels.player), "squad engages the chaser") end
clear(); now = 40.3; Update(0.05)
check(count("Attack", m.backup[1]) == 0, "chaser order is not repeated")
kill(m.backup[2]); near(m.openh, labels.player, 5000); now = 42.5; Update(0.05)
check(called("Formation", m.backup[1], m.openh, 1) and not called("Formation", m.backup[2]),
    "surviving squad returns to formation when the chase ends")

-- misn1114 on nearing the defector; misn1115 after contact is broken for 8 s.
m = reset(); m.start_delay = 99999; m.betrayal = true; m.betrayal_message = true; now = 100
near(m.openh, labels.player, 451); clear(); Update(0.05)
check(count("AudioMessage", "misn1114.wav") == 0, "misn1114 distance is strict")
near(m.openh, labels.player, 449); Update(0.05)
check(count("AudioMessage", "misn1114.wav") == 1 and m.warned_massive, "Collins warns when a human nears the defector")
near(m.openh, labels.player, 449); now = 105; Update(0.05); now = 111; Update(0.05)
check(count("AudioMessage", "misn1115.wav") == 0, "no intel line while still in contact")
near(m.openh, labels.player, 701); now = 113; Update(0.05)
check(count("AudioMessage", "misn1115.wav") == 0, "intel line waits for the break to hold")
now = 120; Update(0.05)
check(count("AudioMessage", "misn1115.wav") == 0, "strict 8 s hold")
now = 121.1; Update(0.05)
check(count("AudioMessage", "misn1115.wav") == 1 and m.intel_logged, "Corbett logs the intel once contact is broken")
now = 140; Update(0.05)
check(count("AudioMessage", "misn1115.wav") == 1 and count("AudioMessage", "misn1114.wav") == 1, "both lines play once")
-- Re-engaging resets the break timer.
m = reset(); m.start_delay = 99999; m.betrayal = true; m.betrayal_message = true; now = 100
near(m.openh, labels.player, 400); Update(0.05); clear()
near(m.openh, labels.player, 800); now = 114; Update(0.05); near(m.openh, labels.player, 500); now = 119; Update(0.05)
near(m.openh, labels.player, 800); now = 121; Update(0.05); now = 128; Update(0.05)
check(count("AudioMessage", "misn1115.wav") == 0, "re-engaging restarts the break hold")
now = 130; Update(0.05)
check(count("AudioMessage", "misn1115.wav") == 1, "intel line follows a clean break")
-- A wiped-out squad also ends the chase.
m = reset(); m.start_delay = 99999; m.betrayal = true; m.betrayal_message = true; m.backup_called = true; m.warned_massive = true
m.warned_massive_time = 0; now = 50; m.backup = {}; near(m.openh, labels.player, 100); Update(0.05); now = 59; Update(0.05)
check(m.intel_logged, "a destroyed squad also lets Corbett log the intel")

-- Weather beats and the pad quake.
m = reset(); clear(); m.betrayal_message = true; Update(0.05)
check(count("IoTarget", 3) == 1, "level 3 on the betrayal")
m.check2 = true; Update(0.05); Update(0.05)
check(count("IoTarget", 4) == 1, "level 4 on the second strike")
m.launch_gone = true; Update(0.05); Update(0.05)
check(count("IoForce", 5, 60, 10) == 1 and count("IoQuake", 0.9, 8) == 1, "level-5 burst and a quake when the pad dies, once")
check(Save().weatherState ~= nil or called("IoSave"), "weather state is saved")
m = reset(); m.last_wave = true; m.got_there1, m.got_there2, m.got_there3 = true, true, true; clear(); Update(0.05)
check(called("SucceedMission") and called("IoRelease") and count("IoTarget", 1) == 1, "calm on the win")

print("misn11: " .. checks .. " checks passed (" .. _VERSION .. ")")
